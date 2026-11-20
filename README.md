# Smart Assistive Navigation and Caregiver Alert System

A CNN-based mobile system that helps visually impaired users detect obstacles
indoors, and alerts a paired caregiver in an emergency.

Final-year project, BSc Informatics and Computer Science, Strathmore University.

- **Author:** Benedict Muuo (164926)
- **Supervisor:** Dr Esther Khakhata

---

## What it does

A phone camera watches the path ahead. A convolutional neural network running
on the device recognises what is in front of the user and speaks a warning. An
ultrasonic sensor on a wearable unit reports how far away the obstacle is. The
object and the distance together decide how urgent the warning should be.

If the user presses the SOS button, their location is sent to a paired
caregiver straight away.

The model runs entirely on the phone. No internet connection is needed for
obstacle detection.

### Classes recognised

`chair` · `table` · `door` · `bag` · `person` · `stairs` · `wall` · `background`

`background` means a clear path with nothing in the way. It matters as much as
the objects do: without it the model is forced to name an obstacle in every
frame, including empty corridors.

---

## Repository layout

```
.
├── model/            Dataset building, training and the exported model
│   ├── build_dataset.py     Collects and prepares the training images
│   ├── train_model.py       Trains, evaluates and exports the CNN
│   ├── exported/            The model that ships in the app
│   └── results/             Evaluation output: plots, metrics
├── app/              Flutter mobile application
├── firmware/         ESP32 sensor unit
├── docs/             Dataset notes, model card, design decisions
└── scripts/          Repository and project setup helpers
```

---

## Current status

All six stages are complete. The version that was tested and demonstrated is
release [**v1.0.0**](../../releases/tag/v1.0.0).

| Stage | Work | State |
|-------|------|-------|
| 1 | CNN model — dataset, training, evaluation, export | Done |
| 2 | Mobile app shell — authentication, screens, SOS | Done |
| 3 | On-device inference — camera stream, speech output | Done |
| 4 | Sensor unit — ESP32, Bluetooth link, risk rules | Done |
| 5 | Testing and evaluation | Done |
| 6 | Final build and documentation | Done |

Progress is tracked in this repository's
[milestones](../../milestones) and [issues](../../issues).

---

## The model

| | |
|---|---|
| Base | MobileNetV3-Small, pretrained on ImageNet |
| Method | Transfer learning, two phases |
| Input | 224 × 224 RGB |
| Classes | 8 |
| Training images | 2,240 (280 per class) |
| Validation accuracy | 85.2% |
| Test accuracy | 78.5% |
| Inference time | 2.1 ms |

Full evaluation, including per-class scores and known weaknesses, is in
[`docs/model-card.md`](docs/model-card.md).

---

## Rebuilding the model

The dataset is not stored in this repository. It is about 3,200 images, and it
can be rebuilt from public sources at any time, so the script is version
controlled instead of the images.

Both steps run in Google Colab.

**1. Build the dataset** (around one hour, no GPU needed)

```bash
python model/build_dataset.py --sources openimages,homeobjects,ade20k --cap 400
```

**2. Train the model** (around 20 minutes, needs a GPU runtime)

```bash
unzip -q assistive_dataset.zip -d assistive_dataset
python model/train_model.py
```

Everything is written to `training_output/`: the trained model, the TFLite
files for the phone, the evaluation plots and the metrics.

Dataset sources and licences are documented in
[`docs/dataset.md`](docs/dataset.md).

---

## Setting up

You need Flutter 3.24 (Dart 3.5), the Android SDK, Arduino IDE 2 with the
"esp32 by Espressif Systems" board package, and the Firebase CLI.

**1. Firebase.** Create a Firebase project with Email/Password sign-in and
Cloud Firestore turned on. The config files are not committed, because this
repository is public. Sign in with `firebase login`, then from the `app` folder
run:

```bash
flutterfire configure --project=<your-firebase-project> --platforms=android
```

That generates `lib/firebase_options.dart` and `android/app/google-services.json`.
Then deploy the security rules from the `firebase` folder:

```bash
cd firebase
firebase deploy --only firestore:rules --project <your-firebase-project>
```

**2. Sensor unit.** Wire and upload the firmware as described in
[`firmware/README.md`](firmware/README.md). Set `SIMULATION` to `false` before
uploading to the real board.

## Running the app

Connect an Android phone (Android 8.0 or later, with Bluetooth) by USB, then:

```bash
cd app
flutter pub get
flutter run --release
```

Sign in, start navigation and point the camera at an object. With the sensor
unit switched on, the app says "Distance sensor connected." Without it, the app
carries on with camera-only warnings.

## Testing

```bash
cd app
flutter analyze
flutter test
```

The 53 unit tests in `app/test` cover the prediction smoother, the
announcement rules, the distance bands, the risk table and alert rules, the
Bluetooth message parser and the data models.

## Deployment

The app is released as a signed APK on the
[releases page](../../releases). To install it, download the APK on the phone
and allow installation from an unknown source when asked. Each release lists a
SHA-256 checksum of the APK.

Releases are built from `main` on Windows with two PowerShell scripts:

```powershell
.\scripts\setup_signing.ps1            # once: creates the upload key and key.properties
.\scripts\release.ps1 -Version 1.0.0   # tests, builds, signs, checks and publishes
```

`release.ps1` stops unless `main` is clean and up to date. The signing key,
`key.properties` and the Firebase config files are never committed.

To roll back, uninstall the app and install the APK of the previous release,
and redeploy `firebase/firestore.rules` from the matching tag.

## Development workflow

Branch naming, commit message format and the pull request process are set out
in [`CONTRIBUTING.md`](CONTRIBUTING.md).
