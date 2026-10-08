#!/usr/bin/env bash
#
# Creates the labels, milestones and issues for this project on GitHub.
#
# Needs the GitHub CLI. Install it, then sign in once:
#     gh auth login
#
# Run from inside the repository:
#     bash scripts/setup_github.sh
#
# Safe to run twice - anything that already exists is skipped.
#
# Milestone dates follow the two-week plan in docs/two-week-plan.md,
# targeting 15 October 2026. Edit them if your deadline moves.

set -u

# ---------------------------------------------------------------------
# Find the GitHub CLI.
#
# On Windows, gh is often installed but missing from Git Bash's PATH even
# when PowerShell can see it, because Git Bash starts with its own
# environment. Look in the usual install locations before giving up.
# ---------------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  for dir in "/c/Program Files/GitHub CLI" \
             "/c/Program Files (x86)/GitHub CLI" \
             "$HOME/AppData/Local/Programs/GitHub CLI"; do
    if [ -x "$dir/gh.exe" ]; then
      PATH="$PATH:$dir"
      export PATH
      echo "Found gh in $dir"
      break
    fi
  done
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: the GitHub CLI (gh) was not found."
  echo
  echo "It may be installed but invisible to this shell. In PowerShell, run:"
  echo '    Get-ChildItem "C:\Program Files\GitHub CLI"'
  echo
  echo "If gh.exe is there, close VS Code completely and reopen it, then run"
  echo "this script again. If it is not, install it with:"
  echo "    winget install --id GitHub.cli"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1 && ! gh repo view >/dev/null 2>&1; then
  echo "ERROR: gh is installed but not signed in. Run:  gh auth login"
  exit 1
fi

echo "==> Labels"

# Report honestly: created, already there, or genuinely failed.
# Do not treat every non-zero exit as "already exists".
report() {
  local what="$1" out="$2" code="$3"
  if [ "$code" -eq 0 ]; then
    echo "    created  $what"
  elif echo "$out" | grep -qiE "already exists|already_exists"; then
    echo "    exists   $what"
  else
    echo "    FAILED   $what"
    echo "             $(echo "$out" | head -2 | tr '\n' ' ')"
  fi
}

label() {
  local out
  out=$(gh label create "$1" --color "$2" --description "$3" 2>&1)
  report "$1" "$out" $?
}

label "model"         "1D76DB" "CNN, dataset, training"
label "app"           "0E8A16" "Flutter application"
label "firmware"      "5319E7" "ESP32 sensor unit"
label "docs"          "C2E0C6" "Documentation"
label "accessibility" "D93F0B" "Screen reader, contrast, touch targets"
label "testing"       "FBCA04" "Tests and evaluation"

echo
echo "==> Milestones"

milestone() {
  local out
  out=$(gh api repos/{owner}/{repo}/milestones \
          -f title="$1" -f description="$2" -f due_on="$3" 2>&1)
  report "$1" "$out" $?
}

# Times are midday UTC so the date reads correctly in Nairobi (UTC+3).
milestone "M1 - CNN model"           "Days 1-2. Local images, retrain, model card"            "2026-10-02T12:00:00Z"
milestone "M2 - App shell"           "Days 3-6. Firebase, authentication, screens, a11y"      "2026-10-06T12:00:00Z"
milestone "M3 - On-device detection" "Days 7-8. Camera, TFLite, speech output"                "2026-10-08T12:00:00Z"
milestone "M4 - Alerts and risk"     "Days 9-11. SOS, distance source, risk rules, hardware"  "2026-10-11T12:00:00Z"
milestone "M5 - Testing"             "Day 12. Unit tests, trials, latency, battery"           "2026-10-12T12:00:00Z"
milestone "M6 - Final build"         "Days 13-14. Release, demo video, Chapters 4 and 5"      "2026-10-14T12:00:00Z"

echo
echo "==> Issues"

issue() {
  local title="$1" body="$2" milestone="$3" labels="$4" out
  if gh issue list --state all --search "\"$title\" in:title" --json title \
       --jq '.[].title' 2>/dev/null | grep -Fxq "$title"; then
    echo "    exists   $title"
    return
  fi
  out=$(gh issue create --title "$title" --body "$body" \
          --milestone "$milestone" --label "$labels" 2>&1)
  if [ $? -eq 0 ]; then
    echo "    created  $title"
  else
    echo "    FAILED   $title"
    echo "             $(echo "$out" | head -2 | tr '\n' ' ')"
  fi
}

# --- M1: CNN model (days 1-2) -------------------------------------------

issue "Build the training dataset from public sources" \
"Collect images for all eight classes and prepare them for training.

Done when:
- [x] Open Images, HomeObjects-3K and ADE20K sources working
- [x] All eight classes populated at 400 images each
- [x] Split 70/15/15 by source photograph, not at random
- [x] manifest.csv records the source of every image" \
"M1 - CNN model" "model"

issue "Train and evaluate the CNN classifier" \
"Two-phase transfer learning on MobileNetV3-Small.

Done when:
- [x] Phase 1 trains the new layers with the base frozen
- [x] Phase 2 fine-tunes the top of the base
- [x] Per-class precision, recall and F1 recorded
- [x] Confusion matrix and training curves saved

Result: 85.2% validation, 78.5% test accuracy." \
"M1 - CNN model" "model"

issue "Export the model to TFLite for the phone" \
"Convert the trained model into a file the Flutter app can load.

Done when:
- [x] Augmentation layers removed before conversion
- [x] float16 model converts and runs
- [x] labels.txt written in the model's output order
- [x] Inference time measured (2.1 ms)" \
"M1 - CNN model" "model"

issue "Collect local images around Strathmore" \
"All current training images come from international datasets. The model has
never seen the environment where it will be demonstrated. This is the single
biggest weakness in the current model.

Target 100+ images per class, covering varied angles, distances and lighting.
Walls and clear floors should be photographed at chest height, matching how
the phone will actually be carried.

Done when:
- [ ] 100+ images per class collected
- [ ] Placed in local/<class>/ folders
- [ ] Dataset rebuilt with them included
- [ ] Consent recorded for any images showing people" \
"M1 - CNN model" "model"

issue "Retrain with local images and compare results" \
"Retrain once local images are collected and record the difference.

Done when:
- [ ] Model retrained on the combined dataset
- [ ] New metrics compared against 78.5% test accuracy
- [ ] Model card updated with before and after
- [ ] Chair and table confusion checked for improvement" \
"M1 - CNN model" "model"

# --- M2: App shell (days 3-6) -------------------------------------------

issue "Set up the Flutter project and Firebase" \
"Create the app and connect it to Firebase.

Done when:
- [ ] Flutter project created under app/
- [ ] Firebase project connected
- [ ] Authentication, Firestore and Cloud Messaging enabled
- [ ] Config files kept out of version control

Risk: Firebase setup can overrun. If still blocked after half a day, hard-code
a test pairing and return to this during M4." \
"M2 - App shell" "app"

issue "Build authentication and caregiver pairing" \
"Users register, sign in, choose a role, and link to each other.

Done when:
- [ ] Register and sign in screens
- [ ] Role choice: user or caregiver
- [ ] Pairing flow linking a user to a caregiver
- [ ] Firestore rules restrict each account to its own data" \
"M2 - App shell" "app"

issue "Build the main screens" \
"Home, live camera and settings for the user; alert list for the caregiver.

Done when:
- [ ] Home screen with start navigation and SOS
- [ ] Live camera screen
- [ ] Settings screen
- [ ] Caregiver alert list

The caregiver map view is explicitly out of scope for two weeks. The list
alone demonstrates the feature." \
"M2 - App shell" "app"

issue "Make every screen work with a screen reader" \
"The primary user cannot see the interface, so this is built in rather than
added at the end.

Done when:
- [ ] Every control has a semantic label
- [ ] Touch targets at least 48dp
- [ ] Agreed colour palette applied
- [ ] Whole app operated with TalkBack on and the screen off

The screen-off test is the real one. An app that only works visually has
missed the point of the project." \
"M2 - App shell" "app,accessibility"

# --- M3: On-device detection (days 7-8) ---------------------------------

issue "Run the TFLite model on camera frames" \
"Load the model in Flutter and classify the live camera feed. This is the core
contribution - protect the time for it.

Done when:
- [ ] Model and labels bundled as app assets
- [ ] Classifying 2-3 frames per second, not every frame
- [ ] Confidence threshold of 0.7 applied
- [ ] Output smoothed: accept a label only if it appears in 3 of the last 5

Risk: tflite_flutter can fail to build over Android NDK version mismatches.
Cap this at two hours before asking for help." \
"M3 - On-device detection" "app,model"

issue "Speak detections aloud" \
"Turn predictions into speech the user can act on.

Done when:
- [ ] Text-to-speech connected
- [ ] An urgent alert interrupts one still being spoken
- [ ] Nothing is said below the confidence threshold
- [ ] Speech rate adjustable

Target for end of M3: point the phone at a chair, hear 'chair ahead'." \
"M3 - On-device detection" "app,accessibility"

# --- M4: Alerts and risk (days 9-11) ------------------------------------

issue "Send an SOS alert with location to the caregiver" \
"Pressing SOS captures the user's position and notifies their caregiver.

Done when:
- [ ] Location permission requested and handled
- [ ] Alert document written to Firestore
- [ ] Push notification delivered to the paired caregiver
- [ ] Works end to end between two devices" \
"M4 - Alerts and risk" "app"

issue "Add the DistanceSource interface with a mock implementation" \
"The sensor hardware has been ordered but not arrived, and the app cannot wait
for it. Build the distance input behind an interface with two implementations.

This is not a workaround. The system must already survive the sensor
disconnecting mid-walk, so 'no sensor' is the permanent case of behaviour that
has to exist anyway. The design degrades gracefully to vision-only operation.

Done when:
- [ ] DistanceSource interface defined
- [ ] MockDistanceSource produces plausible readings
- [ ] App depends only on the interface, never the sensor directly
- [ ] Switching implementations is a one-line change" \
"M4 - Alerts and risk" "app"

issue "Implement the risk rules" \
"Combine object class and distance band into a risk level, and turn that into
an alert. Pure logic, so it works with the mock distance source.

Done when:
- [ ] Distance bands defined: near under 1m, medium 1-3m, far beyond 3m
- [ ] Risk table covering every class and band
- [ ] Hysteresis stops the level flickering at boundaries
- [ ] Low, medium and high map to different speech and vibration" \
"M4 - Alerts and risk" "app"

issue "Build the ESP32 sensor unit and BLE link" \
"Only if the hardware arrives in time. The mock implementation demonstrates
identical logic, so this is the first thing to cut.

Done when:
- [ ] Ultrasonic sensor read reliably on the ESP32
- [ ] Readings broadcast over BLE
- [ ] BleDistanceSource implemented in Flutter
- [ ] Disconnection announced, vision-only mode continues" \
"M4 - Alerts and risk" "firmware,app"

# --- M5: Testing (day 12) -----------------------------------------------

issue "Unit test the risk rules" \
"The risk logic is pure decision-making, so it can be tested directly without
hardware or a camera.

Done when:
- [ ] Every class and distance combination covered
- [ ] Hysteresis behaviour tested at the boundaries
- [ ] Tests run and pass" \
"M5 - Testing" "testing"

issue "Run scenario trials in real environments" \
"Test the system where it will actually be used.

Done when:
- [ ] 20-30 trials logged across a room, a corridor and an outdoor path
- [ ] Each trial records what was said and what was really there
- [ ] Results collected in a spreadsheet as you go

Record during the trials, not afterwards from memory." \
"M5 - Testing" "testing"

issue "Measure latency, battery and SOS delivery" \
"Record the numbers Chapter 4 needs.

Done when:
- [ ] Time from object appearing to speech starting, target under 1 second
- [ ] Battery drain over 30 minutes of continuous use
- [ ] SOS end-to-end delivery time
- [ ] Inference time on the demonstration phone" \
"M5 - Testing" "testing"

# --- M6: Final build (days 13-14) ---------------------------------------

issue "Produce the release build and demo video" \
"Done when:
- [ ] Release APK built and installs cleanly on a fresh device
- [ ] Demo video recorded
- [ ] README setup instructions verified from scratch
- [ ] Repository tidy: issues closed, milestones completed" \
"M6 - Final build" "docs"

issue "Write Chapters 4 and 5" \
"Implementation, testing, conclusions, limitations and future work, written
from the logs and metrics collected along the way.

Done when:
- [ ] Chapter 4 complete with results tables
- [ ] Chapter 5 complete, including the vision-only degradation argument
- [ ] All dataset sources cited in APA 7th edition" \
"M6 - Final build" "docs"

echo
echo "Done. Check them at:"
gh repo view --json url --jq '.url + "/milestones"'