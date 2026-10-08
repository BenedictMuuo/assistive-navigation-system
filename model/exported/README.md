# Exported model

Files the Flutter app loads at runtime.

| File | Purpose |
|------|---------|
| `model_fp16.tflite` | The classifier, float16 quantised |
| `labels.txt` | Class names, in the model's output order |

The app must read class names from `labels.txt` rather than hard-coding them.
If the model is retrained with a different class list, the output order shifts.

The full Keras model is not stored here. It is only needed for further
training and is too large for Git — it is attached to a GitHub Release instead.
