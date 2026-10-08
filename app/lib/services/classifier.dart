import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// One classification of one frame.
class Prediction {
  const Prediction({
    required this.label,
    required this.confidence,
    required this.scores,
    required this.inferenceMs,
  });

  /// The most likely class, e.g. "chair".
  final String label;

  /// Probability of that class, 0 to 1.
  final double confidence;

  /// Probability of every class, in label order.
  final List<double> scores;

  /// How long the model took to run, in milliseconds.
  final int inferenceMs;
}

/// Loads the TFLite model and runs it on prepared images.
class Classifier {
  static const String modelAsset = 'assets/model/model_fp16.tflite';
  static const String labelsAsset = 'assets/model/labels.txt';

  Interpreter? _interpreter;
  List<String> _labels = const [];

  List<String> get labels => _labels;
  bool get isLoaded => _interpreter != null;

  Future<void> load() async {
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(modelAsset, options: options);

    final raw = await rootBundle.loadString(labelsAsset);
    // trim() also strips the \r that Windows line endings leave behind.
    final labels = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    // Fail loudly if the model and the label file disagree. A silent
    // mismatch would make the app name the wrong object every time.
    final outputs = interpreter.getOutputTensor(0).shape.last;
    if (outputs != labels.length) {
      interpreter.close();
      throw StateError(
        'Model has $outputs outputs but labels.txt has ${labels.length} '
        'lines. They must come from the same training run.',
      );
    }

    _interpreter = interpreter;
    _labels = labels;
  }

  /// Runs the model on [input], a flat 224 x 224 x 3 Float32List.
  Prediction classify(Float32List input) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('Classifier.load() must finish before classify().');
    }

    final output = [List<double>.filled(_labels.length, 0)];

    final stopwatch = Stopwatch()..start();
    interpreter.run(input.buffer.asUint8List(), output);
    stopwatch.stop();

    final scores = output[0];
    int best = 0;
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }

    return Prediction(
      label: _labels[best],
      confidence: scores[best],
      scores: List.unmodifiable(scores),
      inferenceMs: stopwatch.elapsedMilliseconds,
    );
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}
