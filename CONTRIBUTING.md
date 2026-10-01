# Working on this project

How changes get made in this repository.

---

## Commit messages

```
<type>: <short subject, under 50 characters, imperative>

<optional body explaining what changed>

Closes #<issue number>
```

Imperative means `add search filter`, not `added` or `adds`.

### Types

| Type | For |
|------|-----|
| `feat` | New functionality |
| `fix` | Fixing broken behaviour |
| `docs` | README, documentation, model card |
| `style` | CSS, spacing, formatting |
| `refactor` | Tidying code, no behaviour change |
| `chore` | Setup, config, housekeeping |

### Examples

```
feat: add dataset build pipeline
fix: remove augmentation before TFLite export
docs: add model card with evaluation results
chore: set up repository structure
```

### Avoid

```
update
fixed stuff
changes
final version 2
```

Keep the subject under 50 characters. If it needs more explanation, leave a
blank line and write a short body saying **why** the change was made. The code
already shows what changed.

End with `Closes #N` so the issue closes automatically when the branch merges.

---

## Branch names

Same type word, then the issue number, then a short slug:

```
feat/3-tflite-export
fix/11-camera-permission
docs/7-model-card
style/2-colour-palette
```

Start every branch from an up-to-date `main`:

```bash
git checkout main
git pull
git checkout -b feat/3-tflite-export
```

One branch per issue. Nothing is committed directly to `main`.

---

## Issues

Plain imperative titles, no type prefix. Each one attached to a milestone.

```
Build the training dataset
Train and evaluate the CNN
Export the model to TFLite
Write Chapters 4 and 5
```

Every piece of work starts as an issue, so there is always a number for the
branch and the commit to reference.

### Labels

| Label | Meaning |
|-------|---------|
| `model` | CNN, dataset, training |
| `app` | Flutter application |
| `firmware` | ESP32 sensor unit |
| `docs` | Documentation |
| `accessibility` | Screen reader, contrast, touch targets |
| `testing` | Tests and evaluation |

---

## Milestones

Named by phase, matching the delivery plan in `docs/two-week-plan.md`:

```
Phase 1: Model and Dataset
Phase 2: Application Shell
Phase 3: On-Device Detection
Phase 4: Alerts and Risk Logic
Phase 5: Testing and Evaluation
Phase 6: Final Build and Documentation
```

---

## Pull requests

Every branch reaches `main` through a pull request. Never by direct push.

```bash
git push -u origin feat/3-tflite-export
```

Then on GitHub:

1. Click **Compare & pull request**
2. Base branch is `main`
3. Put `Closes #N` in the description, so merging closes the issue
4. Read your own diff in the **Files changed** tab, and comment on anything
   worth noting
5. Merge
6. Delete the branch

Reviewing your own diff before merging is not a formality. It catches
debugging code left behind, files staged by accident, and changes you did not
mean to make.

---

## What never gets committed

- The dataset, or any folder of training images
- `.keras` or `.h5` model files — these go in a GitHub Release
- Firebase configuration files and any API keys
- Build output from Flutter or PlatformIO

The `.gitignore` covers all of these. Before committing, check what is about to
be added:

```bash
git status
```

If something unexpected appears, add it to `.gitignore` rather than committing
it and removing it later. Files are hard to erase from Git history.
