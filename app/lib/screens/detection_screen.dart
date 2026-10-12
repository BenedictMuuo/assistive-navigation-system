import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../services/classifier.dart';
import '../services/distance/mock_distance_source.dart';
import '../services/haptics.dart';
import '../services/image_converter.dart';
import '../services/prediction_smoother.dart';
import '../services/risk/risk_alert_policy.dart';
import '../services/risk/risk_rules.dart';
import '../services/speech_service.dart';

/// Live camera view: classifies what is ahead, combines it with distance,
/// and warns the user according to risk.
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

  // Distance and risk. The mock stands in for the ESP32 ultrasonic unit.
  final MockDistanceSource _distance = MockDistanceSource();
  final DistanceBander _bander = DistanceBander();
  final RiskAlertPolicy _riskPolicy = RiskAlertPolicy();
  StreamSubscription<double?>? _distanceSub;
  double? _metres;
  DistanceBand _band = DistanceBand.unknown;
  bool _sensorOn = true;

  CameraController? _camera;
  String? _error;
  bool _running = false;
  bool _busy = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  Prediction? _latest; // raw, this frame
  String? _steady; // smoothed, what the user is told
  RiskLevel? _risk; // null while unsure or in camera-only mode

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    try {
      await _classifier.load();
      await _speech.init();

      _distanceSub = _distance.readings.listen(_onDistance);
      await _distance.start();

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

  void _onDistance(double? metres) {
    final band = _bander.update(metres);
    if (!mounted) return;
    setState(() {
      _metres = metres;
      _band = band;
    });
  }

  Future<void> _toggle() async {
    final camera = _camera;
    if (camera == null) return;

    if (_running) {
      await camera.stopImageStream();
      _smoother.reset();
      _riskPolicy.reset();
      await _speech.stop();
      setState(() {
        _running = false;
        _latest = null;
        _steady = null;
        _risk = null;
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

  /// Simulates the sensor disconnecting and reconnecting, to demonstrate
  /// that the app falls back to camera-only warnings.
  Future<void> _toggleSensor(bool on) async {
    _distance.setConnected(on);
    _riskPolicy.reset();
    _speech.policy.reset();
    setState(() => _sensorOn = on);
    await _speech.say(on
        ? 'Distance sensor connected.'
        : 'Distance sensor disconnected. Using camera only.');
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

      RiskLevel? risk;
      if (_band == DistanceBand.unknown) {
        // No distance: camera-only mode, using the speech rules alone.
        unawaited(_speech.update(steady));
      } else if (steady != null) {
        risk = RiskTable.assess(steady, _band);
        final alert = _riskPolicy.next(
          steady,
          risk,
          now,
          speaking: _speech.isSpeaking,
        );
        unawaited(_deliver(alert));
      }

      if (mounted) {
        setState(() {
          _latest = prediction;
          _steady = steady;
          _risk = risk;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _busy = false;
    }
  }

  Future<void> _deliver(RiskAlert alert) async {
    if (alert.isSilent) return;
    unawaited(Haptics.play(alert.haptic));
    final phrase = alert.phrase;
    if (phrase != null) {
      await _speech.announce(phrase, interrupt: alert.interrupt);
    }
  }

  @override
  void dispose() {
    final camera = _camera;
    if (camera != null) {
      if (camera.value.isStreamingImages) camera.stopImageStream();
      camera.dispose();
    }
    _distanceSub?.cancel();
    _distance.dispose();
    _speech.stop();
    _classifier.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // What the user is shown and told
  // ---------------------------------------------------------------------

  String _name(String label) =>
      '${label[0].toUpperCase()}${label.substring(1)}';

  String get _message {
    if (!_running) return 'Detection off';
    final steady = _steady;
    if (steady == null) return 'Checking…';
    if (steady == 'background') return 'Path clear';
    final metres = _metres;
    if (_band != DistanceBand.unknown && metres != null) {
      return '${_name(steady)} · ${metres.toStringAsFixed(1)} m';
    }
    return '${_name(steady)} ahead';
  }

  String? get _riskText => switch (_risk) {
        RiskLevel.high => 'HIGH RISK',
        RiskLevel.medium => 'MEDIUM RISK',
        RiskLevel.low => 'LOW RISK',
        null => null,
      };

  Color get _panelColour {
    if (!_running || _steady == null) return Colors.black87;
    switch (_risk) {
      case RiskLevel.high:
        return AppColours.danger;
      case RiskLevel.medium:
        return AppColours.caution;
      case RiskLevel.low:
        return AppColours.active;
      case null:
        // Camera-only mode: no distance, so no graded risk.
        if (_steady == 'background') return AppColours.active;
        if (_steady == 'stairs') return AppColours.danger;
        return AppColours.primary;
    }
  }

  /// Black on the yellow caution colour; white on everything else.
  Color get _panelText =>
      _panelColour == AppColours.caution ? Colors.black : Colors.white;

  String get _bandText => switch (_band) {
        DistanceBand.near => 'near',
        DistanceBand.medium => 'medium',
        DistanceBand.far => 'far',
        DistanceBand.unknown => 'no reading',
      };

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
    final riskText = _riskText;

    return Column(
      children: [
        Expanded(
          child: ExcludeSemantics(
            // The preview is visual only; a screen reader gains nothing
            // from it and should go straight to the result below.
            child: Center(child: CameraPreview(camera)),
          ),
        ),

        // Result panel. The app speaks and vibrates for itself, so this is
        // not a live region - otherwise TalkBack users would hear every
        // result twice. TalkBack still reads it when touched.
        Semantics(
          label: riskText == null ? _message : '$_message. $riskText',
          excludeSemantics: true,
          child: Container(
            width: double.infinity,
            color: _panelColour,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              children: [
                Text(
                  _message,
                  style: TextStyle(
                    color: _panelText,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (riskText != null)
                  Text(
                    riskText,
                    style: TextStyle(
                      color: _panelText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                if (latest != null) ...[
                  const SizedBox(height: 4),
                  // Raw output, for development and testing only.
                  Text(
                    'raw: ${latest.label} '
                    '${(latest.confidence * 100).toStringAsFixed(0)}%  ·  '
                    '${latest.inferenceMs} ms',
                    style: TextStyle(
                      color: _panelText.withOpacity(0.75),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        _simulationPanel(),

        // Start and stop. Large target, well above the 48dp minimum.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 72,
            child: Semantics(
              button: true,
              label: _running ? 'Stop detection' : 'Start detection',
              // Without this, excludeSemantics hides the button's tap
              // from TalkBack and a double-tap does nothing.
              onTap: _toggle,
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

  /// Controls for the simulated distance sensor. Clearly labelled as a
  /// simulation, so nobody watching a demo mistakes it for real hardware.
  Widget _simulationPanel() {
    final metres = _metres;
    final reading = _sensorOn && metres != null
        ? '${metres.toStringAsFixed(2)} m ($_bandText)'
        : 'disconnected';

    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Simulated sensor: $reading',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              const Text('Sensor',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              Switch(
                value: _sensorOn,
                onChanged: _toggleSensor,
                activeColor: AppColours.caution,
              ),
            ],
          ),
          Slider(
            value: _distance.target,
            min: MockDistanceSource.minMetres,
            max: MockDistanceSource.maxMetres,
            divisions: 48,
            label: '${_distance.target.toStringAsFixed(1)} m',
            semanticFormatterCallback: (v) =>
                'Simulated distance ${v.toStringAsFixed(1)} metres',
            onChanged: _sensorOn
                ? (v) => setState(() => _distance.setDistance(v))
                : null,
          ),
        ],
      ),
    );
  }
}
