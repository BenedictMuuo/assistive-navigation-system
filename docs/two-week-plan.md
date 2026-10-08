# Two-week delivery plan

Written 1 October 2026. Target: a working, demonstrable system by 15 October.

**Budget:** 14 days × 4.5 hours ≈ 63 hours.

That is enough for a system that works and can be defended. It is not enough
for everything in the original six-stage plan. This document says what gets
built properly, what gets simplified, and what gets cut if time runs short.

---

## The one decision that shapes everything

The ESP32 and ultrasonic sensor have been ordered but have not arrived. The
app cannot wait for them.

So the distance input is built behind an interface with two implementations:

```
DistanceSource (interface)
├── BleDistanceSource       real sensor over Bluetooth
└── MockDistanceSource      simulated, for development and as a fallback
```

The app is written against the interface, never against the sensor directly.
Everything — risk rules, alerts, testing — works today with the mock. When the
hardware arrives, one line changes which implementation is used.

This is not a workaround. The system already has to survive the sensor
disconnecting mid-walk, so "no sensor present" is just the permanent case of
behaviour that must exist anyway. It is worth saying exactly that in the
write-up and at the defence: the design degrades gracefully to vision-only
operation.

---

## Priority order

Work is sequenced so that stopping early still leaves something that works.

| Priority | What | Why it comes first |
|---|---|---|
| 1 | Obstacle detection with speech output | The core contribution. Without it there is no project. |
| 2 | SOS with caregiver alert | The second half of the title. Small and self-contained. |
| 3 | Risk rules with simulated distance | Shows the full logic working, no hardware needed. |
| 4 | Real BLE sensor | Only if the hardware arrives in time. |
| 5 | Caregiver map view | Nice to have. Cut first. |

---

## Day by day

### Days 1–2 — Finish the model (9 h)

- [ ] Photograph around campus: 100+ per class, 8 classes
      Corridors, classrooms, library, compound. Vary angle, distance, light.
      Wall and background at chest height, matching how the phone is carried.
- [ ] Record consent for any images showing people
- [ ] Upload to `local/<class>/` in Colab
- [ ] Rebuild the dataset including local images
- [ ] Retrain, compare against 78.5% test accuracy
- [ ] Update `docs/model-card.md` with before-and-after numbers

Photography is about 3 hours. The rest is mostly waiting on Colab, so do the
Flutter installation while it runs.

**Deliverable:** a model that has seen the environment it will be demonstrated in.

### Days 3–4 — Project and authentication (9 h)

- [ ] Flutter project created under `app/`
- [ ] Firebase project connected, config files gitignored
- [ ] Authentication, Firestore and Cloud Messaging enabled
- [ ] Register and sign-in screens
- [ ] Role choice: user or caregiver
- [ ] Pairing flow linking a user to a caregiver
- [ ] Firestore rules so each account reads only its own data

**Risk:** Firebase setup can swallow half a day when something misconfigures.
If you are still fighting it at the end of day 4, drop the caregiver role for
now and hard-code a test pairing. Come back to it on day 9.

### Days 5–6 — Screens and accessibility (9 h)

- [ ] Home screen: start navigation, SOS
- [ ] Live camera screen
- [ ] Settings screen
- [ ] Caregiver alert list
- [ ] Semantic label on every control
- [ ] Touch targets at least 48dp
- [ ] Agreed colour palette applied
- [ ] Whole app driven with TalkBack on and the screen off

Accessibility is built in here, not added later. The primary user cannot see
the interface, so an app that only works visually has missed the point. The
screen-off test is the real one.

### Days 7–8 — Detection and speech (9 h)

This is the heart of the project. Protect these two days.

- [ ] Model and `labels.txt` bundled as app assets
- [ ] Camera stream running
- [ ] Classifying 2–3 frames per second, not every frame
- [ ] Confidence threshold of 0.7 applied
- [ ] Output smoothed: accept a label only if it appears in 3 of the last 5
- [ ] Text-to-speech connected
- [ ] Urgent alerts interrupt speech already playing

**Risk:** `tflite_flutter` can be awkward with Android NDK versions. If it
fails to build, the error usually names a version mismatch in
`android/app/build.gradle`. Budget two hours for this specifically; if it goes
past that, say so and we fix it together rather than losing a day.

**Deliverable:** point the phone at a chair, hear "chair ahead". From here you
have something to demonstrate no matter what happens next.

### Day 9 — SOS and caregiver alerts (4.5 h)

- [ ] Location permission requested and handled
- [ ] SOS writes an alert document to Firestore
- [ ] Push notification reaches the paired caregiver
- [ ] Tested end to end across two devices

If you deferred caregiver pairing on day 4, finish it here.

### Day 10 — Risk rules and distance (4.5 h)

- [ ] `DistanceSource` interface defined
- [ ] `MockDistanceSource` producing plausible readings
- [ ] Distance bands: near under 1 m, medium 1–3 m, far beyond 3 m
- [ ] Risk table covering every class and band
- [ ] Hysteresis so the level does not flicker at boundaries
- [ ] Low, medium and high mapped to different speech and vibration

All of this is pure logic, so it is testable without any hardware.

### Day 11 — Hardware, or buffer (4.5 h)

**If the sensor arrived:**
- [ ] ESP32 flashed, reading the ultrasonic sensor
- [ ] Readings broadcast over BLE
- [ ] `BleDistanceSource` implemented in Flutter
- [ ] Disconnection announced, vision-only mode continues

**If it did not:** use this day to absorb overruns from earlier days. There
will be some. Keep the mock and document the hardware as designed, built in
software, and awaiting components.

### Day 12 — Testing (4.5 h)

- [ ] Unit tests for the risk rules, every class and band
- [ ] 20–30 logged trials across a room, a corridor and an outdoor path
- [ ] Each trial records what was said and what was actually there
- [ ] Latency: object appearing to speech starting
- [ ] Battery drain over 30 minutes
- [ ] SOS delivery time
- [ ] Inference time on the demonstration phone

Record straight into a spreadsheet as you go. Reconstructing this afterwards
from memory is painful and the numbers end up vague.

The original plan said 30–50 trials. 20–30 is enough to show a pattern and
fits the time.

### Days 13–14 — Write-up and delivery (9 h)

- [ ] Release APK built and installed cleanly on a fresh device
- [ ] Demo video recorded
- [ ] Chapter 4: implementation and testing, using the logged results
- [ ] Chapter 5: conclusions, limitations, future work
- [ ] README setup steps verified from scratch
- [ ] All dataset sources cited in APA 7th edition
- [ ] Repository tidy: issues closed, milestones completed

---

## If you fall behind

Cut in this order. Each line goes before touching anything above it.

1. Caregiver map view — the alert list alone proves the feature
2. Real BLE sensor — the mock demonstrates identical logic
3. Battery measurement — state it as untested
4. Trials down to 15 — enough for a pattern
5. Settings screen — hard-code sensible defaults

**Never cut:** obstacle detection with speech, the confidence threshold, the
accessibility pass, or the write-up. Those four are what the project is
assessed on.

---

## Known risks

| Risk | Likelihood | What to do |
|---|---|---|
| Firebase setup overruns | Medium | Hard-code a test pairing, return on day 9 |
| `tflite_flutter` build fails | Medium | Two-hour cap, then ask for help |
| Hardware arrives late | High | Mock is already the plan |
| Campus photos take longer than expected | Medium | 60 per class is workable; prioritise wall and background |
| Something unforeseen | Certain | Day 11 is the buffer |

---

## Daily habit

End every working day with a commit and a push. Issues closed as you go, not
in a batch at the end.

Your lecturer asked for evidence of continuous development rather than
last-minute work. Fourteen days of real commits is that evidence, and it costs
nothing extra if you are committing as you work anyway.
