"""
build_dataset.py
=================
Builds ONE image-classification dataset for the CNN assistive navigation project.

It pulls from several public sources, converts them all into the same folder
structure, removes duplicates, balances the classes, splits into
train / val / test, writes a manifest for your report, and zips the result.

FINAL CLASSES
    chair, door, bag, wall, table, stairs, person, background

HOW TO RUN (Google Colab)
    1. Upload this file to Colab.
    2. Run:  !python build_dataset.py --sources openimages,homeobjects
    3. Add the optional sources once you have their keys/files (see SETUP below).
    4. Download /content/assistive_dataset.zip when it finishes.

SETUP FOR THE OPTIONAL SOURCES
    Kaggle     : upload kaggle.json to /content/, then add "kaggle" to --sources
    Roboflow   : export ROBOFLOW_API_KEY, then add "roboflow" to --sources
    Mendeley   : download the zip manually, unzip to /content/mendeley_stairs/,
                 then add "mendeley" to --sources
    Your own   : put images in /content/local/<class>/ , always included

NOTE ON WALL AND BACKGROUND
    No public dataset covers these two. You must supply them yourself in
    /content/local/wall/ and /content/local/background/ . The script will warn
    you if they are missing.
"""

import argparse
import csv
import hashlib
import importlib
import os
import random
import shutil
import subprocess
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

# Pillow is deliberately NOT imported here.
#
# Installing fiftyone can change the installed Pillow version. If Pillow were
# already loaded into memory at that point, half the package would be the old
# version and half the new one, and it crashes with an error about '_Ink'.
# So the install happens first, then load_pillow() brings it in.
Image = None

# --------------------------------------------------------------------------
# CONFIGURATION
# --------------------------------------------------------------------------

CLASSES = ["chair", "door", "bag", "wall", "table", "stairs", "person", "background"]

IMG_SIZE = 224          # final image size, matches MobileNetV3 input
MIN_BOX_PX = 80         # ignore boxes smaller than this, they blur when resized
BOX_PADDING = 0.10      # keep 10% context around each cropped object
PER_CLASS_CAP = 900     # max images per class before splitting
JPEG_QUALITY = 90       # lower this to about 75 for a noticeably smaller zip
SPLIT = (0.70, 0.15, 0.15)   # train / val / test
SEED = 42

random.seed(SEED)

# Where everything lives. In Colab this is /content. Running locally (VS Code,
# a terminal) it becomes a folder next to this script. Override with --work-dir.
BASE = Path("/content") if Path("/content").is_dir() else Path(__file__).resolve().parent

WORK = BASE / "_work"                      # scratch space, safe to delete after
STAGE = BASE / "_stage"                    # all crops land here first
OUT = BASE / "assistive_dataset"           # the finished dataset
LOCAL = BASE / "local"                     # your own photos go here
ZIP_PATH = BASE / "assistive_dataset.zip"
KAGGLE_JSON = BASE / "kaggle.json"
MENDELEY_DIR = BASE / "mendeley_stairs"

# Each record: (staged_file_path, class_name, group_id, source_name)
# group_id keeps every crop from the SAME original photo in the SAME split,
# which stops the model from being tested on a photo it already trained on.
RECORDS = []
SEEN_HASHES = set()


# --------------------------------------------------------------------------
# HELPERS
# --------------------------------------------------------------------------

def sh(cmd):
    print(f"  $ {cmd}")
    subprocess.run(cmd, shell=True, check=True)


def pip(pkg, module=None):
    """Install a package only if it isn't already importable."""
    try:
        importlib.import_module(module or pkg)
        return
    except ImportError:
        pass
    print(f"  installing {pkg}...")
    subprocess.run([sys.executable, "-m", "pip", "install", "-q", pkg], check=True)


def install_deps(source_names):
    """Install everything up front, before Pillow is loaded."""
    needed = {"openimages": ("fiftyone", "fiftyone"),
              "homeobjects": ("ultralytics", "ultralytics"),
              "kaggle": ("kaggle", "kaggle"),
              "roboflow": ("roboflow", "roboflow")}
    for name in source_names:
        if name in needed:
            pkg, mod = needed[name]
            try:
                pip(pkg, mod)
            except subprocess.CalledProcessError:
                print(f"  !! could not install {pkg}")


def load_pillow():
    global Image
    pip("pillow", "PIL")
    from PIL import Image as _Image
    Image = _Image


def save_crop(img, box, cls, group_id, source):
    """Crop, pad, resize, de-duplicate and stage one training image."""
    if cls not in CLASSES:
        return False

    W, H = img.size
    x1, y1, x2, y2 = box
    if (x2 - x1) < MIN_BOX_PX or (y2 - y1) < MIN_BOX_PX:
        return False

    pw = int((x2 - x1) * BOX_PADDING)
    ph = int((y2 - y1) * BOX_PADDING)
    box = (max(0, x1 - pw), max(0, y1 - ph), min(W, x2 + pw), min(H, y2 + ph))

    try:
        crop = img.crop(box).convert("RGB").resize((IMG_SIZE, IMG_SIZE))
    except Exception:
        return False

    digest = hashlib.md5(crop.tobytes()).hexdigest()
    if digest in SEEN_HASHES:
        return False
    SEEN_HASHES.add(digest)

    dest_dir = STAGE / cls
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{source}_{digest[:10]}.jpg"
    crop.save(dest, quality=JPEG_QUALITY)

    RECORDS.append((dest, cls, f"{source}:{group_id}", source))
    return True


def save_whole(path, cls, source):
    """Use a complete image as one training sample (for wall / background / local)."""
    try:
        img = Image.open(path).convert("RGB")
    except Exception:
        return False
    return save_crop(img, (0, 0, img.size[0], img.size[1]), cls, path.stem, source)


# --------------------------------------------------------------------------
# GENERIC FORMAT READERS
# --------------------------------------------------------------------------

def read_voc(root, label_map, source):
    """Pascal VOC: an .xml next to each image, holding <object><name> and <bndbox>."""
    import xml.etree.ElementTree as ET
    root = Path(root)
    n = 0
    for xml in root.rglob("*.xml"):
        try:
            tree = ET.parse(xml)
        except Exception:
            continue
        stem = xml.stem
        img_path = None
        for ext in (".jpg", ".jpeg", ".png", ".JPG", ".PNG"):
            cand = xml.with_suffix(ext)
            if cand.exists():
                img_path = cand
                break
        if img_path is None:
            hits = list(root.rglob(stem + ".jpg")) + list(root.rglob(stem + ".png"))
            if not hits:
                continue
            img_path = hits[0]

        try:
            img = Image.open(img_path)
        except Exception:
            continue

        for obj in tree.findall(".//object"):
            name = (obj.findtext("name") or "").strip().lower()
            cls = label_map.get(name)
            if cls is None:
                continue
            bb = obj.find("bndbox")
            if bb is None:
                continue
            try:
                box = (int(float(bb.findtext("xmin"))), int(float(bb.findtext("ymin"))),
                       int(float(bb.findtext("xmax"))), int(float(bb.findtext("ymax"))))
            except (TypeError, ValueError):
                continue
            if save_crop(img, box, cls, stem, source):
                n += 1
    print(f"  -> {n} images from {source}")
    return n


def read_yolo(root, label_map, source):
    """YOLO: labels/*.txt with 'class cx cy w h' normalised, names from data.yaml."""
    root = Path(root)
    names = {}

    yamls = list(root.rglob("data.yaml")) + list(root.rglob("*.yaml"))
    for y in yamls:
        text = y.read_text(errors="ignore")
        if "names" not in text:
            continue
        try:
            import yaml
            cfg = yaml.safe_load(text)
        except Exception:
            continue
        raw = cfg.get("names")
        if isinstance(raw, list):
            names = {i: str(v).lower() for i, v in enumerate(raw)}
        elif isinstance(raw, dict):
            names = {int(k): str(v).lower() for k, v in raw.items()}
        if names:
            break

    if not names:
        print(f"  !! could not read class names for {source}, skipping")
        return 0

    n = 0
    for txt in root.rglob("*.txt"):
        if txt.name in ("classes.txt", "requirements.txt", "README.txt"):
            continue
        img_path = None
        for parent in (Path(str(txt.parent).replace("labels", "images")), txt.parent):
            for ext in (".jpg", ".jpeg", ".png"):
                cand = parent / (txt.stem + ext)
                if cand.exists():
                    img_path = cand
                    break
            if img_path:
                break
        if img_path is None:
            continue

        try:
            img = Image.open(img_path)
        except Exception:
            continue
        W, H = img.size

        for line in txt.read_text(errors="ignore").splitlines():
            parts = line.split()
            if len(parts) < 5:
                continue
            try:
                idx = int(float(parts[0]))
                cx, cy, w, h = (float(p) for p in parts[1:5])
            except ValueError:
                continue
            cls = label_map.get(names.get(idx, ""))
            if cls is None:
                continue
            box = (int((cx - w / 2) * W), int((cy - h / 2) * H),
                   int((cx + w / 2) * W), int((cy + h / 2) * H))
            if save_crop(img, box, cls, txt.stem, source):
                n += 1
    print(f"  -> {n} images from {source}")
    return n


def read_folders(root, source):
    """Plain structure: <root>/<class_name>/*.jpg"""
    root = Path(root)
    if not root.exists():
        return 0
    n = 0
    for cls_dir in sorted(root.iterdir()):
        if not cls_dir.is_dir():
            continue
        cls = cls_dir.name.strip().lower()
        if cls not in CLASSES:
            print(f"  !! folder '{cls}' is not a known class, skipped")
            continue
        for img in cls_dir.rglob("*"):
            if img.suffix.lower() in (".jpg", ".jpeg", ".png") and save_whole(img, cls, source):
                n += 1
    print(f"  -> {n} images from {source}")
    return n


# --------------------------------------------------------------------------
# SOURCES
# --------------------------------------------------------------------------

def find_det_field(ds):
    """
    Locate the field holding the bounding boxes. It is called 'detections' in
    some fiftyone versions and 'ground_truth' in others, so check by type.
    """
    import fiftyone.core.labels as fol
    probe = ds.first()
    if probe is None:
        return None
    for name in ("ground_truth", "detections", "positive_labels"):
        if isinstance(getattr(probe, name, None), fol.Detections):
            return name
    for name in probe.field_names:
        if isinstance(getattr(probe, name, None), fol.Detections):
            return name
    return None


def src_openimages():
    """
    Google Open Images V7 - the main source.

    Each class is downloaded on its own. Sharing one batch across all classes
    means common objects (chair, person) fill up while rare ones (handbag,
    stairs) come back nearly empty.
    """
    print("[Open Images V7]")
    pip("fiftyone", "fiftyone")
    import fiftyone as fo
    import fiftyone.zoo as foz

    # One or more Open Images labels per target class. Widening 'bag' and
    # 'table' pulls in far more usable images for those classes.
    groups = {
        "chair":  ["Chair"],
        "table":  ["Table", "Desk", "Coffee table", "Kitchen & dining room table"],
        "door":   ["Door"],
        "bag":    ["Handbag", "Backpack", "Suitcase", "Briefcase"],
        "person": ["Person"],
        "stairs": ["Stairs"],
    }

    total = 0
    per_class = {}

    for cls, oi_labels in groups.items():
        # Ask for more photos than needed, since not every box is usable.
        want = max(60, int(PER_CLASS_CAP * 1.6))
        name = f"oiv7_{cls}"
        try:
            if fo.dataset_exists(name):
                fo.delete_dataset(name)
            ds = foz.load_zoo_dataset(
                "open-images-v7",
                split="train",
                label_types=["detections"],
                classes=oi_labels,
                max_samples=want,
                dataset_name=name,
            )
        except Exception as e:
            print(f"  !! {cls}: {e}")
            continue

        field = find_det_field(ds)
        if field is None:
            print(f"  !! {cls}: no detection field found")
            continue

        wanted = set(oi_labels)
        count = 0
        for sample in ds:
            if count >= PER_CLASS_CAP:
                break
            dets = getattr(sample, field, None)
            if dets is None:
                continue
            try:
                img = Image.open(sample.filepath)
            except Exception:
                continue
            W, H = img.size
            for det in dets.detections:
                if det.label not in wanted or count >= PER_CLASS_CAP:
                    continue
                x, y, w, h = det.bounding_box
                box = (int(x * W), int(y * H), int((x + w) * W), int((y + h) * H))
                if save_crop(img, box, cls, Path(sample.filepath).stem, "oiv7"):
                    count += 1

        try:
            fo.delete_dataset(name)      # free the disk as we go
        except Exception:
            pass

        per_class[cls] = count
        total += count
        print(f"  {cls}: {count}")

    print(f"  -> {total} images from oiv7  {per_class}")


def src_homeobjects():
    """HomeObjects-3K - extra chair, table and door in varied lighting."""
    print("[HomeObjects-3K]")
    pip("ultralytics", "ultralytics")
    from ultralytics.utils.downloads import safe_download

    dest = WORK / "homeobjects"
    dest.mkdir(parents=True, exist_ok=True)
    zip_file = dest / "homeobjects-3K.zip"
    if not zip_file.exists():
        safe_download(
            "https://github.com/ultralytics/assets/releases/download/v0.0.0/homeobjects-3K.zip",
            file=str(zip_file),
        )
    with zipfile.ZipFile(zip_file) as z:
        z.extractall(dest)

    read_yolo(dest, {"chair": "chair", "table": "table", "door": "door"}, "homeobj")


def src_kaggle():
    """Kaggle door / window / stairs set. Needs kaggle.json at /content/."""
    print("[Kaggle door-window-stairs]")
    cred = KAGGLE_JSON
    if not cred.exists():
        print(f"  !! {cred} not found, skipping")
        return
    pip("kaggle", "kaggle")
    os.makedirs(os.path.expanduser("~/.kaggle"), exist_ok=True)
    shutil.copy(cred, os.path.expanduser("~/.kaggle/kaggle.json"))
    os.chmod(os.path.expanduser("~/.kaggle/kaggle.json"), 0o600)

    dest = WORK / "kaggle_dws"
    dest.mkdir(parents=True, exist_ok=True)
    sh(f"kaggle datasets download -d nderalparslan/dwsonder -p {dest} --unzip")

    read_voc(dest, {"door": "door", "stairs": "stairs", "stair": "stairs",
                    "upstair": "stairs", "downstair": "stairs"}, "kaggle")


def src_roboflow():
    """Obstacles for Blind. Needs ROBOFLOW_API_KEY in the environment."""
    print("[Roboflow obstacles-for-blind]")
    key = os.environ.get("ROBOFLOW_API_KEY")
    if not key:
        print("  !! ROBOFLOW_API_KEY not set, skipping")
        return
    pip("roboflow", "roboflow")
    from roboflow import Roboflow

    rf = Roboflow(api_key=key)
    project = rf.workspace("obstacles-for-blind-zjnnn").project("obstacles-for-blind")
    version = project.version(1)
    ds = version.download("yolov8", location=str(WORK / "roboflow"))

    read_yolo(ds.location, {"door": "door", "doors": "door",
                            "stairs": "stairs", "stair": "stairs",
                            "person": "person", "people": "person"}, "roboflow")


def src_mendeley():
    """Mendeley staircase set. Download the zip by hand, unzip to /content/mendeley_stairs/."""
    print("[Mendeley staircase]")
    root = MENDELEY_DIR
    if not root.exists():
        print(f"  !! {root} not found, skipping")
        return
    read_voc(root, {"upstair": "stairs", "downstair": "stairs",
                    "upstairs": "stairs", "downstairs": "stairs",
                    "stairs": "stairs", "stair": "stairs"}, "mendeley")


def src_local():
    """Your own photos: /content/local/<class>/*.jpg"""
    print("[Your own images]")
    if not LOCAL.exists():
        print(f"  !! {LOCAL} not found - wall and background will be missing")
        return
    read_folders(LOCAL, "local")


def src_ade20k():
    """
    ADE20K - fills the 'wall' and 'background' classes automatically.

    Every pixel in this dataset is labelled, so instead of looking for boxed
    objects we cut square patches out of regions that are entirely wall
    (label 1) or entirely floor (label 4). A patch of bare floor is exactly
    what 'background' means here: a clear path with nothing in the way.

    The download is about 1 GB, so this source takes a while the first time.
    """
    print("[ADE20K wall and floor patches]")
    try:
        import numpy as np
    except ImportError:
        pip("numpy", "numpy")
        import numpy as np

    dest = WORK / "ade20k"
    dest.mkdir(parents=True, exist_ok=True)
    zip_file = dest / "ADEChallengeData2016.zip"
    root = dest / "ADEChallengeData2016"

    if not root.exists():
        if not zip_file.exists():
            url = ("https://data.csail.mit.edu/places/ADEchallenge/"
                   "ADEChallengeData2016.zip")
            print("  downloading ~1 GB, this takes a few minutes...")
            try:
                sh(f"wget -q --show-progress -c {url} -O {zip_file}")
            except subprocess.CalledProcessError:
                print("  !! download failed, skipping ADE20K")
                return
        print("  unzipping...")
        try:
            with zipfile.ZipFile(zip_file) as z:
                z.extractall(dest)
        except zipfile.BadZipFile:
            print("  !! zip is corrupt, delete it and run again")
            return

    ann_dir = root / "annotations" / "training"
    img_dir = root / "images" / "training"
    if not ann_dir.exists():
        print("  !! annotation folder not found, skipping")
        return

    # ADE20K label ids: 1 = wall, 4 = floor
    wanted = {1: "wall", 4: "background"}
    # Try big patches first and fall back to smaller ones. A corridor floor is
    # often a band only ~200px tall, so insisting on one large size throws
    # away most of the dataset.
    PATCH_SIZES = (320, 256, 192, 160)
    PURITY = 0.95         # patch must be almost entirely that one surface
    TRIES = 25            # random windows attempted per size
    PER_PHOTO = 3         # keep variety, don't flood from one scene

    counts = defaultdict(int)
    files = sorted(ann_dir.glob("*.png"))
    random.shuffle(files)

    for ann_path in files:
        if all(counts[c] >= PER_CLASS_CAP for c in wanted.values()):
            break
        img_path = img_dir / (ann_path.stem + ".jpg")
        if not img_path.exists():
            continue
        try:
            mask = np.array(Image.open(ann_path))
            img = Image.open(img_path).convert("RGB")
        except Exception:
            continue

        H, W = mask.shape[:2]

        for label_id, cls in wanted.items():
            if counts[cls] >= PER_CLASS_CAP:
                continue
            if (mask == label_id).mean() < 0.08:
                continue                      # barely any of this surface here
            taken = 0
            for patch in PATCH_SIZES:
                if taken >= PER_PHOTO or counts[cls] >= PER_CLASS_CAP:
                    break
                if H < patch or W < patch:
                    continue
                for _ in range(TRIES):
                    if taken >= PER_PHOTO or counts[cls] >= PER_CLASS_CAP:
                        break
                    x = random.randint(0, W - patch)
                    y = random.randint(0, H - patch)
                    window = mask[y:y + patch, x:x + patch]
                    if (window == label_id).mean() < PURITY:
                        continue
                    if save_crop(img, (x, y, x + patch, y + patch), cls,
                                 ann_path.stem, "ade20k"):
                        counts[cls] += 1
                        taken += 1

    print(f"  -> {sum(counts.values())} images from ade20k  {dict(counts)}")


SOURCES = {
    "openimages": src_openimages,
    "homeobjects": src_homeobjects,
    "ade20k": src_ade20k,
    "kaggle": src_kaggle,
    "roboflow": src_roboflow,
    "mendeley": src_mendeley,
}


# --------------------------------------------------------------------------
# BALANCE, SPLIT, EXPORT
# --------------------------------------------------------------------------

def balance():
    """Cap each class, drawing evenly across sources so one source can't dominate."""
    by_class = defaultdict(lambda: defaultdict(list))
    for rec in RECORDS:
        by_class[rec[1]][rec[3]].append(rec)

    kept = []
    for cls, by_source in by_class.items():
        pools = [v[:] for v in by_source.values()]
        for p in pools:
            random.shuffle(p)
        picked = []
        while len(picked) < PER_CLASS_CAP and any(pools):
            for p in pools:
                if p and len(picked) < PER_CLASS_CAP:
                    picked.append(p.pop())
            pools = [p for p in pools if p]
        kept.extend(picked)
    return kept


def split_and_export(kept):
    """
    Split by source photo, not by individual image.

    One photo can produce crops of several classes (a chair AND a table in the
    same room shot). If those crops were split separately, the same photo would
    appear in both training and testing and the accuracy figure would be
    inflated. So the split is decided once per photo, for all its crops.
    """
    if OUT.exists():
        shutil.rmtree(OUT)

    groups = defaultdict(list)
    for rec in kept:
        groups[rec[2]].append(rec)

    # Photos yield very different numbers of crops - one classroom shot can give
    # ten chairs, and all ten must stay together. Assigning photos at random
    # therefore skews the proportions badly.
    #
    # Instead: place the biggest photos first, and send each one to whichever
    # split is furthest below its target FOR THE CLASSES IN THAT PHOTO. Scoring
    # per class rather than overall is what keeps every class at 70/15/15.
    totals = defaultdict(int)
    for items in groups.values():
        for r in items:
            totals[r[1]] += 1

    targets = {"train": SPLIT[0], "val": SPLIT[1], "test": SPLIT[2]}
    filled = {s: defaultdict(int) for s in targets}

    keys = list(groups.keys())
    random.shuffle(keys)
    keys.sort(key=lambda k: len(groups[k]), reverse=True)

    assign = {}
    for k in keys:
        counts = defaultdict(int)
        for r in groups[k]:
            counts[r[1]] += 1
        best, best_cost = None, None
        for s in targets:
            # cost = the worst class overshoot this placement would cause
            cost = 0.0
            for cls, c in counts.items():
                quota = max(1e-9, targets[s] * totals[cls])
                cost = max(cost, (filled[s][cls] + c) / quota)
            if best_cost is None or cost < best_cost:
                best, best_cost = s, cost
        assign[k] = best
        for cls, c in counts.items():
            filled[best][cls] += c

    # Safety net: a rare class could land entirely in train. Move one group
    # over so every class still has something to validate and test against.
    per_class = defaultdict(lambda: defaultdict(list))
    for k, items in groups.items():
        for r in items:
            per_class[r[1]][assign[k]].append(k)
    for cls, spread in per_class.items():
        for need in ("val", "test"):
            if not spread.get(need) and len(spread.get("train", [])) > 2:
                moved = spread["train"].pop()
                assign[moved] = need
                spread.setdefault(need, []).append(moved)

    manifest = []
    summary = defaultdict(lambda: defaultdict(int))

    for gid, items in groups.items():
        split = assign[gid]
        for path, cls, _, source in items:
            dest_dir = OUT / split / cls
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / path.name
            shutil.copy(path, dest)
            manifest.append([split, cls, source, dest.name])
            summary[cls][split] += 1

    with open(OUT / "manifest.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["split", "class", "source", "filename"])
        w.writerows(manifest)

    print("\n" + "=" * 58)
    print(f"{'class':<14}{'train':>8}{'val':>8}{'test':>8}{'total':>10}")
    print("-" * 58)
    grand = 0
    for cls in CLASSES:
        s = summary.get(cls, {})
        tot = sum(s.values())
        grand += tot
        flag = "   <-- EMPTY" if tot == 0 else ""
        print(f"{cls:<14}{s.get('train', 0):>8}{s.get('val', 0):>8}"
              f"{s.get('test', 0):>8}{tot:>10}{flag}")
    print("-" * 58)
    print(f"{'TOTAL':<14}{'':>8}{'':>8}{'':>8}{grand:>10}")
    print("=" * 58)

    missing = [c for c in CLASSES if not summary.get(c)]
    if missing:
        print(f"\nWARNING - no images for: {', '.join(missing)}")
        print("Add your own photos to /content/local/<class>/ and run again.")


def make_zip():
    if ZIP_PATH.exists():
        ZIP_PATH.unlink()
    print("\nZipping...")
    shutil.make_archive(str(ZIP_PATH.with_suffix("")), "zip", root_dir=OUT)
    size_mb = ZIP_PATH.stat().st_size / (1024 * 1024)
    print(f"Done: {ZIP_PATH}  ({size_mb:.0f} MB)")
    print("In Colab: from google.colab import files; files.download"
          f"('{ZIP_PATH}')")


# --------------------------------------------------------------------------

def main():
    global PER_CLASS_CAP, JPEG_QUALITY
    global BASE, WORK, STAGE, OUT, LOCAL, ZIP_PATH, KAGGLE_JSON, MENDELEY_DIR

    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", default="openimages,homeobjects",
                    help="comma list from: " + ",".join(SOURCES))
    ap.add_argument("--cap", type=int, default=400,
                    help="max images per class (400 = about 3200 images, ~45 MB)")
    ap.add_argument("--quality", type=int, default=JPEG_QUALITY,
                    help="JPEG quality 60-95, lower means a smaller zip")
    ap.add_argument("--work-dir", default=None,
                    help="folder to build in (defaults to /content on Colab, "
                         "otherwise the folder holding this script)")
    args = ap.parse_args()

    PER_CLASS_CAP = args.cap
    JPEG_QUALITY = args.quality

    if args.work_dir:
        BASE = Path(args.work_dir).expanduser().resolve()
        WORK, STAGE = BASE / "_work", BASE / "_stage"
        OUT, LOCAL = BASE / "assistive_dataset", BASE / "local"
        ZIP_PATH = BASE / "assistive_dataset.zip"
        KAGGLE_JSON, MENDELEY_DIR = BASE / "kaggle.json", BASE / "mendeley_stairs"

    print(f"Building in : {BASE}")
    print(f"Your photos : {LOCAL}  ({'found' if LOCAL.exists() else 'MISSING'})")
    print(f"Output zip  : {ZIP_PATH}\n")

    WORK.mkdir(parents=True, exist_ok=True)
    STAGE.mkdir(parents=True, exist_ok=True)

    chosen = [s.strip() for s in args.sources.split(",") if s.strip()]

    # Order matters: install everything first, THEN load Pillow.
    print("Checking dependencies...")
    install_deps(chosen)
    load_pillow()
    print(f"Pillow ready. Sources: {', '.join(chosen)}\n")

    for name in chosen:
        fn = SOURCES.get(name)
        if fn is None:
            print(f"Unknown source: {name}")
            continue
        try:
            fn()
        except Exception as e:
            print(f"  !! {name} failed: {e}")

    src_local()

    print(f"\nStaged {len(RECORDS)} images. Balancing and splitting...")
    kept = balance()
    split_and_export(kept)
    make_zip()


if __name__ == "__main__":
    main()
