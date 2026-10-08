# Model card — obstacle classifier

A record of what this model is, how well it works, and where it fails.

Last trained: 15 September 2026

---

## What the model does

Takes one camera frame and names the most prominent object in it, from eight
possible classes. The app uses that name, together with a distance reading
from the ultrasonic sensor, to decide what to say to the user.

| | |
|---|---|
| Task | Image classification, single label |
| Base model | MobileNetV3-Small, pretrained on ImageNet |
| Method | Transfer learning, two phases |
| Input | 224 × 224 RGB, raw 0–255 values |
| Output | 8 probabilities that sum to 1 |
| Framework | TensorFlow / Keras |
| Deployed as | TFLite, float16 quantised |

**Classes, in the order the model outputs them:**

```
0  background      5  stairs
1  bag             6  table
2  chair           7  wall
3  door
4  person
```

This order is fixed by `exported/labels.txt`. The app must read the labels from
that file rather than hard-coding the order — if the model is retrained with a
different class list, the numbers shift.

---

## How it was trained

**Phase 1 — new layers only.** The MobileNetV3 base was frozen and only the
three new layers on top were trained, for 15 epochs at learning rate 0.001.
This avoids damaging the pretrained weights while the new layers still produce
random output.

Validation accuracy went from 58.8% to 81.7%.

**Phase 2 — fine-tuning.** The top 44 of 157 base layers were unfrozen, with
all batch normalisation layers kept frozen, for 15 more epochs at learning rate
0.00001.

Validation accuracy went from 81.9% to 85.2%.

**Layers added on top of the base:**

```
GlobalAveragePooling2D  →  Dropout(0.3)  →  Dense(8, softmax)
```

**Augmentation during training:** horizontal flip, rotation up to 8%, zoom up
to 15%, brightness ±20%, contrast ±20%. These layers are removed before TFLite
export, as the operations have no TFLite equivalent.

**Guards against overfitting:** dropout, augmentation, early stopping on
validation loss, learning-rate reduction on plateau, and class weighting.

---

## Results

Measured on 480 test images the model never saw during training — 60 per class.

**Overall test accuracy: 78.5%**

| Class | Precision | Recall | F1 | Support |
|-------|-----------|--------|-----|---------|
| background | 0.98 | 1.00 | 0.99 | 60 |
| wall | 0.85 | 0.97 | 0.91 | 60 |
| door | 0.83 | 0.90 | 0.86 | 60 |
| stairs | 0.89 | 0.83 | 0.86 | 60 |
| bag | 0.75 | 0.73 | 0.74 | 60 |
| table | 0.70 | 0.67 | 0.68 | 60 |
| person | 0.71 | 0.57 | 0.63 | 60 |
| chair | 0.56 | 0.62 | 0.59 | 60 |

The safety-critical classes score highest. `background` at 0.99 means the model
almost never claims an obstacle is present when the path is clear. `wall` at
0.91 and `stairs` at 0.86 are the two classes where a missed warning would
cause the most harm.

**Most frequent mistakes**

| Mistake | Count |
|---------|-------|
| table called chair | 12 |
| chair called table | 10 |
| person called chair | 9 |
| person called bag | 8 |
| bag called person | 6 |

Two pairs account for almost all errors. Chairs and tables are both furniture
with flat tops and four legs, and the training crops often show only part of
either. People and bags get confused because most people in the source photos
are carrying one.

Neither mistake is dangerous in use. A chair called a table still warns the
user that furniture is ahead, at the right distance. No obstacle is being
mistaken for a clear path, which is the error that would matter.

---

## Confidence threshold

The model gives a probability with every prediction. Below a chosen threshold,
the app stays silent instead of speaking.

| Threshold | Frames answered | Accuracy when it answers |
|-----------|-----------------|--------------------------|
| 0.0 | 100.0% | 78.5% |
| 0.5 | 92.3% | 81.9% |
| 0.6 | 82.5% | 84.3% |
| **0.7** | **74.0%** | **88.5%** |
| 0.8 | 62.9% | 92.7% |
| 0.9 | 51.7% | 95.6% |

**0.7 is the chosen operating point.** The model answers about three frames in
four, and is right 88.5% of the time when it does. The frames it skips are
mostly the ones it would have got wrong.

Staying silent is the right behaviour for this application. A user who hears
nothing keeps using their cane and their own judgement. A user told "clear
path" when a staircase is ahead has been actively misled.

At 2–3 classifications per second, skipping a quarter of frames is not
noticeable — a real obstacle stays in view across many frames.

---

## Speed and size

| | |
|---|---|
| Inference time | 2.1 ms per image |
| Measured on | Colab T4 GPU, not a phone |

Phone performance will be slower, likely 10–30 ms. That still leaves plenty of
room at the 2–3 frames per second the app uses, and well inside the 1-second
alert target.

---

## Limitations

**No Kenyan images.** Every training image comes from international public
datasets. Corridors, furniture, doors and wall finishes at Strathmore may look
different from anything the model has seen. This is the most serious
limitation and the reason local photographs are planned.

**Trained on crops, used on full frames.** The training images are tightly
cropped around single objects. The phone camera sees whole scenes with several
objects at once. The model names only the most prominent one.

**Wall and background come from scene photos, not a corridor camera.** The
`wall` and `background` images were cut from labelled regions of indoor scene
photographs. They teach the model what a flat surface and a clear floor look
like, but not from the exact angle a chest-mounted phone would see.

**One object per frame.** A chair in front of a doorway produces one answer,
not two.

**Indoor only.** No outdoor obstacles — vehicles, kerbs, potholes, crossings —
are in the class list.

**Lighting not separately measured.** Accuracy in dim corridors has not been
tested on its own.

---

## Planned improvements

1. Add 100–150 locally photographed images per class and retrain. Compare
   against these numbers to show the effect.
2. Collect `wall` and `background` from a chest-mounted phone at walking
   height, matching real use.
3. Measure accuracy separately in good and poor light.
4. Measure inference time on the actual demonstration phone.

---

## Files

| File | What it is |
|------|-----------|
| `model/exported/model_fp16.tflite` | The model the app loads |
| `model/exported/labels.txt` | Class names, in output order |
| `model/results/confusion_matrix.png` | Which classes get confused |
| `model/results/training_curves.png` | Accuracy and loss per epoch |
| `model/results/results.json` | All metrics as data |

The full Keras model, needed only for further training, is attached to the
repository's releases rather than committed, because of its size.
