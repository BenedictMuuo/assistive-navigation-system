import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../services/classifier.dart';
import '../services/image_converter.dart';
import '../services/prediction_smoother.dart';
import '../services/speech_service.dart';

/// Live camera view that classifies what is in front of the user.
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  /// Minimum gap between classified frames. 400 ms is about 2.5 frames a
  /// second - plenty for walking pace, and it keeps the phone cool and the
  /// battery alive. Classifying every frame would gain nothing.
  static const Duration _frameGap = Duration(milliseconds: 400);

  final Classifier _classifier = Classifier();
  final PredictionSmoother _smoother = PredictionSmoother();
  final SpeechService _speech = SpeechService();

  CameraController? _camera;
  String? _error;
  bool _running = false;
  bool _busy = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  Prediction? _latest; // raw, this frame
  String? _steady; // smoothed, what the user is told

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    try {
      await _classifier.load();
      await _speech.init();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera found on this device.');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggle() async {
    final camera = _camera;
    if (camera == null) return;

    if (_running) {
      await camera.stopImageStream();
      _smoother.reset();
      await _speech.stop();
      setState(() {
        _running = false;
        _latest = null;
        _steady = null;
      });
      // Pressing a button should never be silent for someone who cannot
      // see the screen change.
      await _speech.say('Detection stopped');
    } else {
      await _speech.say('Detection started');
      await camera.startImageStream(_onFrame);
      setState(() => _running = true);
    }
  }

  void _onFrame(CameraImage image) {
    // Drop frames while one is still being processed, or if it is too soon.
    final now = DateTime.now();
    if (_busy || now.difference(_lastFrame) < _frameGap) return;
    _busy = true;
    _lastFrame = now;

    try {
      final rotation = _camera?.description.sensorOrientation ?? 90;
      final input = ImageConverter.toModelInput(image, rotation);
      final prediction = _classifier.classify(input);
      final steady = _smoother.add(prediction.label, prediction.confidence);

      // Speech decides for itself whether this is worth saying.
      unawaited(_speech.update(steady));

      if (mounted) {
        setState(() {
          _latest = prediction;
          _steady = steady;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    final camera = _camera;
    if (camera != null) {
      if (camera.value.isStreamingImages) camera.stopImageStream();
      camera.dispose();
    }
    _speech.stop();
    _classifier.close();
    super.dispose();
  }

  /// What the user is told, in plain words.
  String get _message {
    if (!_running) return 'Detection off';
    final steady = _steady;
    if (steady == null) return 'Checking…';
    if (steady == 'background') return 'Path clear';
    return '${steady[0].toUpperCase()}${steady.substring(1)} ahead';
  }

  Color get _panelColour {
    if (!_running) return Colors.black87;
    final steady = _steady;
    if (steady == null) return Colors.black87;
    if (steady == 'background') return AppColours.active;
    if (steady == 'stairs') return AppColours.danger;
    return AppColours.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Obstacle detection'),
        backgroundColor: AppColours.primary,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Something went wrong:\n\n$error',
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return Center(
        child: Semantics(
          label: 'Loading camera and model',
          child: const CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final latest = _latest;

    return Column(
      children: [
        Expanded(
          child: ExcludeSemantics(
            // The preview is visual only; a screen reader gains nothing
            // from it and should go straight to the result below.
            child: Center(child: CameraPreview(camera)),
          ),
        ),

        // Result panel. The app speaks results itself, so this is not a
        // live region - otherwise TalkBack users would hear every result
        // twice. TalkBack can still read it when the user touches it.
        Semantics(
          label: _message,
          excludeSemantics: true,
          child: Container(
            width: double.infinity,
            color: _panelColour,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: [
                Text(
                  _message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (latest != null) ...[
                  const SizedBox(height: 8),
                  // Raw output, for development and testing only.
                  Text(
                    'raw: ${latest.label} '
                    '${(latest.confidence * 100).toStringAsFixed(0)}%  ·  '
                    '${latest.inferenceMs} ms',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Start and stop. Large target, well above the 48dp minimum.
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 72,
            child: Semantics(
              button: true,
              label: _running ? 'Stop detection' : 'Start detection',
              excludeSemantics: true,
              child: ElevatedButton(
                onPressed: _toggle,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _running ? AppColours.danger : AppColours.active,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: Text(_running ? 'STOP' : 'START'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
