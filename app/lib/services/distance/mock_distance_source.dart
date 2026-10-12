import 'dart:async';
import 'dart:math';

import 'distance_source.dart';

/// A stand-in for the ultrasonic sensor, used until the hardware arrives
/// and for demonstrations.
///
/// The distance is set by hand with a slider. Readings arrive five times a
/// second with a few centimetres of random wobble, as a real ultrasonic
/// sensor's would. The wobble matters: it is what the hysteresis in the
/// risk rules exists to absorb, so the simulation exercises it honestly.
class MockDistanceSource implements DistanceSource {
  MockDistanceSource({
    double initialMetres = 2.5,
    this.noiseMetres = 0.03,
    this.interval = const Duration(milliseconds: 200),
    Random? random,
  })  : _target = initialMetres,
        _random = random ?? Random();

  static const double minMetres = 0.2;
  static const double maxMetres = 5.0;

  final double noiseMetres;
  final Duration interval;
  final Random _random;

  final StreamController<double?> _controller =
      StreamController<double?>.broadcast();

  double _target;
  bool _connected = true;
  Timer? _timer;

  @override
  String get name => 'Simulated sensor';

  @override
  Stream<double?> get readings => _controller.stream;

  @override
  bool get isConnected => _connected;

  /// The distance the slider is set to.
  double get target => _target;

  void setDistance(double metres) {
    _target = metres.clamp(minMetres, maxMetres).toDouble();
  }

  /// Simulates the sensor dropping out, or coming back.
  void setConnected(bool connected) {
    _connected = connected;
    if (!connected && !_controller.isClosed) _controller.add(null);
  }

  @override
  Future<void> start() async {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      if (!_connected || _controller.isClosed) return;
      final wobble = (_random.nextDouble() * 2 - 1) * noiseMetres;
      _controller.add(max(0.05, _target + wobble));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
