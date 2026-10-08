"""
train_model.py
==============
Trains the object classifier for the CNN assistive navigation project.

Base model : MobileNetV3-Small (built for phones)
Method     : transfer learning in two phases
Output     : Keras model, TFLite model, labels.txt, plots, metrics

HOW TO RUN (Google Colab, GPU runtime)
    Runtime -> Change runtime type -> T4 GPU
    !unzip -q /content/drive/MyDrive/assistive_dataset.zip -d /content/assistive_dataset
    !python train_model.py

    Options:
        --epochs1 15      head-training epochs
        --epochs2 15      fine-tuning epochs
        --batch 32
        --data /content/assistive_dataset

Everything it produces goes into /content/training_output/
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


# --------------------------------------------------------------------------
# CONFIG
# --------------------------------------------------------------------------

IMG_SIZE = 224
SEED = 42
OUT = Path("/content/training_output")

tf.random.set_seed(SEED)
np.random.seed(SEED)


# --------------------------------------------------------------------------
# DATA
# --------------------------------------------------------------------------

def load_data(data_dir, batch):
    data_dir = Path(data_dir)
    for split in ("train", "val", "test"):
        if not (data_dir / split).exists():
            raise SystemExit(f"Missing folder: {data_dir / split}")

    def load(split, shuffle):
        return keras.utils.image_dataset_from_directory(
            data_dir / split,
            image_size=(IMG_SIZE, IMG_SIZE),
            batch_size=batch,
            label_mode="categorical",
            shuffle=shuffle,
            seed=SEED,
        )

    train_ds = load("train", True)
    val_ds = load("val", False)
    test_ds = load("test", False)

    class_names = train_ds.class_names
    print(f"\nClasses ({len(class_names)}): {class_names}")

    n_train = sum(len(f) for f in [list((data_dir / 'train').rglob('*.jpg'))])
    print(f"Training images: {n_train}")
    if len(class_names) < 8:
        print("\nNOTE: fewer than 8 classes. If 'background' is missing, the model")
        print("must pick an object for every image, including empty corridors.")
        print("Treat tonight's accuracy as a pipeline check, not a final result.\n")

    auto = tf.data.AUTOTUNE
    return (train_ds.cache().prefetch(auto),
            val_ds.cache().prefetch(auto),
            test_ds.cache().prefetch(auto),
            class_names)


def class_weights(data_dir, class_names):
    """Stop a large class from dominating a small one."""
    counts = []
    for c in class_names:
        counts.append(len(list((Path(data_dir) / "train" / c).glob("*.jpg"))))
    total = sum(counts)
    n = len(counts)
    weights = {i: total / (n * max(1, c)) for i, c in enumerate(counts)}
    print("Images per class:", dict(zip(class_names, counts)))
    return weights


# --------------------------------------------------------------------------
# MODEL
# --------------------------------------------------------------------------

def build_model(n_classes):
    """
    MobileNetV3-Small expects raw 0-255 pixel values because it does its own
    scaling inside (include_preprocessing=True). Do NOT add a Rescaling layer
    or the images get scaled twice and accuracy collapses.
    """
    augment = keras.Sequential([
        layers.RandomFlip("horizontal"),
        layers.RandomRotation(0.08),
        layers.RandomZoom(0.15),
        layers.RandomBrightness(0.2, value_range=(0, 255)),
        layers.RandomContrast(0.2),
    ], name="augment")

    base = keras.applications.MobileNetV3Small(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
        include_preprocessing=True,
    )
    base.trainable = False

    inputs = keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = augment(inputs)
    x = base(x, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    outputs = layers.Dense(n_classes, activation="softmax", name="predictions")(x)

    model = keras.Model(inputs, outputs)
    return model, base


def unfreeze_top(base, fraction=0.35):
    """
    Unfreeze the last portion of the base for fine-tuning, but keep every
    BatchNormalization layer frozen. Unfreezing BN on a small dataset wrecks
    the running statistics the base model depends on.
    """
    base.trainable = True
    cutoff = int(len(base.layers) * (1 - fraction))
    frozen_bn = 0
    for i, layer in enumerate(base.layers):
        if i < cutoff:
            layer.trainable = False
        elif isinstance(layer, layers.BatchNormalization):
            layer.trainable = False
            frozen_bn += 1
    trainable = sum(1 for l in base.layers if l.trainable)
    print(f"Fine-tuning {trainable}/{len(base.layers)} base layers "
          f"({frozen_bn} BatchNorm layers kept frozen)")


# --------------------------------------------------------------------------
# TRAINING
# --------------------------------------------------------------------------

def train(model, base, train_ds, val_ds, weights, epochs1, epochs2):
    ckpt = str(OUT / "best.keras")

    def callbacks(patience):
        return [
            keras.callbacks.ModelCheckpoint(ckpt, monitor="val_accuracy",
                                            save_best_only=True, verbose=0),
            keras.callbacks.EarlyStopping(monitor="val_loss", patience=patience,
                                          restore_best_weights=True, verbose=1),
            keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.3,
                                              patience=3, min_lr=1e-7, verbose=1),
        ]

    print("\n" + "=" * 60)
    print("PHASE 1 - training the new layers (base frozen)")
    print("=" * 60)
    model.compile(optimizer=keras.optimizers.Adam(1e-3),
                  loss="categorical_crossentropy",
                  metrics=["accuracy"])
    h1 = model.fit(train_ds, validation_data=val_ds, epochs=epochs1,
                   class_weight=weights, callbacks=callbacks(5), verbose=1)

    print("\n" + "=" * 60)
    print("PHASE 2 - fine-tuning the top of the base model")
    print("=" * 60)
    unfreeze_top(base)
    model.compile(optimizer=keras.optimizers.Adam(1e-5),
                  loss="categorical_crossentropy",
                  metrics=["accuracy"])
    h2 = model.fit(train_ds, validation_data=val_ds, epochs=epochs2,
                   class_weight=weights, callbacks=callbacks(6), verbose=1)

    return h1, h2


def plot_history(h1, h2):
    def join(key):
        return list(h1.history[key]) + list(h2.history[key])

    split_at = len(h1.history["accuracy"])
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))

    for ax, (a, b, title) in zip(axes, [
            ("accuracy", "val_accuracy", "Accuracy"),
            ("loss", "val_loss", "Loss")]):
        ax.plot(join(a), label="training")
        ax.plot(join(b), label="validation")
        ax.axvline(split_at - 0.5, color="grey", ls="--", lw=1)
        ax.text(split_at - 0.4, ax.get_ylim()[0], " fine-tuning starts",
                fontsize=8, color="grey")
        ax.set_title(title)
        ax.set_xlabel("epoch")
        ax.legend()
        ax.grid(alpha=0.3)

    plt.tight_layout()
    plt.savefig(OUT / "training_curves.png", dpi=150)
    print(f"Saved {OUT / 'training_curves.png'}")


# --------------------------------------------------------------------------
# EVALUATION
# --------------------------------------------------------------------------

def evaluate(model, test_ds, class_names):
    print("\n" + "=" * 60)
    print("EVALUATION ON THE TEST SET")
    print("=" * 60)

    probs = model.predict(test_ds, verbose=0)
    y_true = np.concatenate([np.argmax(y, axis=1) for _, y in test_ds])
    y_pred = np.argmax(probs, axis=1)
    conf = np.max(probs, axis=1)

    acc = float((y_true == y_pred).mean())
    print(f"\nOverall accuracy: {acc:.1%}\n")

    # per-class precision / recall / f1, written out by hand so the script
    # does not depend on scikit-learn being present
    print(f"{'class':<14}{'precision':>11}{'recall':>9}{'f1':>8}{'support':>9}")
    print("-" * 51)
    rows = []
    for i, name in enumerate(class_names):
        tp = int(((y_pred == i) & (y_true == i)).sum())
        fp = int(((y_pred == i) & (y_true != i)).sum())
        fn = int(((y_pred != i) & (y_true == i)).sum())
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        sup = int((y_true == i).sum())
        rows.append({"class": name, "precision": prec, "recall": rec,
                     "f1": f1, "support": sup})
        print(f"{name:<14}{prec:>11.2f}{rec:>9.2f}{f1:>8.2f}{sup:>9}")

    # confusion matrix
    n = len(class_names)
    cm = np.zeros((n, n), dtype=int)
    for t, p in zip(y_true, y_pred):
        cm[t, p] += 1

    fig, ax = plt.subplots(figsize=(1.1 * n + 3, 1.1 * n + 2))
    ax.imshow(cm, cmap="Blues")
    ax.set_xticks(range(n), class_names, rotation=45, ha="right")
    ax.set_yticks(range(n), class_names)
    ax.set_xlabel("predicted")
    ax.set_ylabel("actual")
    ax.set_title(f"Confusion matrix (accuracy {acc:.1%})")
    for i in range(n):
        for j in range(n):
            ax.text(j, i, cm[i, j], ha="center", va="center",
                    color="white" if cm[i, j] > cm.max() / 2 else "black")
    plt.tight_layout()
    plt.savefig(OUT / "confusion_matrix.png", dpi=150)
    print(f"\nSaved {OUT / 'confusion_matrix.png'}")

    # biggest confusions, useful for the write-up
    pairs = [(class_names[i], class_names[j], int(cm[i, j]))
             for i in range(n) for j in range(n) if i != j and cm[i, j] > 0]
    pairs.sort(key=lambda p: p[2], reverse=True)
    if pairs:
        print("\nMost common mistakes:")
        for a, b, c in pairs[:5]:
            print(f"  {a} predicted as {b}: {c} times")

    # confidence thresholds - how much is given up to stay silent when unsure
    print("\nConfidence threshold trade-off:")
    print(f"{'threshold':>10}{'answered':>11}{'accuracy':>11}")
    print("-" * 32)
    thresholds = []
    for t in (0.0, 0.5, 0.6, 0.7, 0.8, 0.9):
        keep = conf >= t
        coverage = float(keep.mean())
        kept_acc = float((y_true[keep] == y_pred[keep]).mean()) if keep.any() else 0.0
        thresholds.append({"threshold": t, "coverage": coverage,
                           "accuracy": kept_acc})
        print(f"{t:>10.1f}{coverage:>10.1%}{kept_acc:>11.1%}")
    print("\nPick the threshold where accuracy is high and coverage is still")
    print("reasonable. Saying nothing beats announcing the wrong object.")

    return {"test_accuracy": acc, "per_class": rows,
            "thresholds": thresholds,
            "confusion_matrix": cm.tolist(),
            "class_names": class_names}


# --------------------------------------------------------------------------
# EXPORT
# --------------------------------------------------------------------------

def export(model, class_names, test_ds):
    print("\n" + "=" * 60)
    print("EXPORTING FOR THE PHONE")
    print("=" * 60)

    (OUT / "labels.txt").write_text("\n".join(class_names))
    model.save(OUT / "model.keras")

    sm_dir = OUT / "saved_model"
    try:
        model.export(str(sm_dir))          # Keras 3
    except AttributeError:
        tf.saved_model.save(model, str(sm_dir))
    converter = tf.lite.TFLiteConverter.from_saved_model(str(sm_dir))

    # float16: smaller, no accuracy loss worth worrying about
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    fp16 = converter.convert()
    (OUT / "model_fp16.tflite").write_bytes(fp16)

    # int8: smallest and fastest, needs sample images to calibrate
    def rep_data():
        for images, _ in test_ds.take(20):
            for img in images:
                yield [tf.expand_dims(tf.cast(img, tf.float32), 0)]

    try:
        c2 = tf.lite.TFLiteConverter.from_saved_model(str(sm_dir))
        c2.optimizations = [tf.lite.Optimize.DEFAULT]
        c2.representative_dataset = rep_data
        int8 = c2.convert()
        (OUT / "model_int8.tflite").write_bytes(int8)
    except Exception as e:
        int8 = None
        print(f"  int8 conversion skipped: {e}")

    print(f"\n{'file':<24}{'size':>10}")
    print("-" * 34)
    for f in ("model.keras", "model_fp16.tflite", "model_int8.tflite"):
        p = OUT / f
        if p.exists():
            print(f"{f:<24}{p.stat().st_size / 1024 / 1024:>9.1f} MB")

    # rough speed check on this machine - the phone will differ
    interp = tf.lite.Interpreter(model_content=fp16)
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]
    dummy = np.random.rand(*inp["shape"]).astype(inp["dtype"])
    interp.set_tensor(inp["index"], dummy)
    for _ in range(5):
        interp.invoke()
    start = time.time()
    for _ in range(50):
        interp.invoke()
    ms = (time.time() - start) / 50 * 1000
    print(f"\nInference: {ms:.1f} ms per image (this machine, not the phone)")
    return ms


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="/content/assistive_dataset")
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--epochs1", type=int, default=15)
    ap.add_argument("--epochs2", type=int, default=15)
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    print("GPU:", tf.config.list_physical_devices("GPU") or "none (this will be slow)")

    train_ds, val_ds, test_ds, class_names = load_data(args.data, args.batch)
    weights = class_weights(args.data, class_names)

    model, base = build_model(len(class_names))
    h1, h2 = train(model, base, train_ds, val_ds, weights,
                   args.epochs1, args.epochs2)

    plot_history(h1, h2)
    results = evaluate(model, test_ds, class_names)
    ms = export(model, class_names, test_ds)
    results["inference_ms"] = ms

    with open(OUT / "results.json", "w") as f:
        json.dump(results, f, indent=2)

    print("\n" + "=" * 60)
    print(f"Done. Everything is in {OUT}")
    print("Copy it to Drive before the runtime disconnects:")
    print("  !cp -r /content/training_output /content/drive/MyDrive/")
    print("=" * 60)


if __name__ == "__main__":
    main()
