import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'distance_source.dart';

/// Distance readings from the ESP32 wearable unit over Bluetooth Low Energy.
///
/// The ESP32 (firmware/wearable_distance) advertises as "AssistNav-Wearable"
/// and notifies a text message about four times a second, for example
/// "DIST:85;BAND:NEAR". Only the DIST value is used here; the app works out
/// its own bands with hysteresis in [DistanceBander].
///
/// Losing the sensor is normal, not an error. If the link drops, or no
/// reading arrives for [staleAfter], the source reports null so the app
/// falls back to camera-only warnings. It then keeps trying to reconnect
/// every [retryDelay] until [stop] is called.
class BleDistanceSource implements DistanceSource {
  BleDistanceSource({
    this.staleAfter = const Duration(seconds: 2),
    this.retryDelay = const Duration(seconds: 3),
    this.scanTime = const Duration(seconds: 10),
  });

  static const String deviceName = 'AssistNav-Wearable';
  static final Guid serviceUuid = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid distanceUuid =
      Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

  /// The ESP32 sends "DIST:-1" when no echo comes back, which means nothing
  /// is in range. That is reported as this distance (the far band), so a
  /// clear path is not mistaken for a lost sensor.
  static const double clearMetres = 4.0;

  /// A single missed echo is common with soft or angled objects. Only this
  /// many misses in a row count as a clear path; fewer are ignored, and the
  /// last real distance stands.
  static const int missesBeforeClear = 3;

  final Duration staleAfter;
  final Duration retryDelay;
  final Duration scanTime;

  /// What the source is doing, for the screen: "Searching for sensor",
  /// "Connected", and so on.
  final ValueNotifier<String> status = ValueNotifier('Not started');

  final StreamController<double?> _controller =
      StreamController<double?>.broadcast();

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _valueSub;
  Timer? _watchdog;
  Timer? _retry;

  bool _running = false;
  bool _disposed = false;
  bool _connecting = false;
  bool _connected = false;
  bool _stale = false;
  int _misses = 0;
  DateTime? _lastReading;

  @override
  String get name => 'ESP32 ultrasonic';

  @override
  Stream<double?> get readings => _controller.stream;

  @override
  bool get isConnected => _connected && !_stale;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _watchdog = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _checkStale(),
    );
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running || _connecting || _connected) return;
    _connecting = true;
    try {
      if (!await FlutterBluePlus.isSupported) {
        _setStatus('Bluetooth not supported on this phone');
        return; // nothing to retry
      }

      // Ask Android to switch Bluetooth on. The user can still refuse.
      if (defaultTargetPlatform == TargetPlatform.android &&
          FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        _setStatus('Turning on Bluetooth');
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {
          // Refused or not possible. Waiting below will time out and retry.
        }
      }
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 10));
      if (!_running) return;

      _setStatus('Searching for sensor');
      final device = await _scan();
      if (!_running) return;
      if (device == null) {
        _scheduleRetry('Sensor not found');
        return;
      }

      _setStatus('Connecting');
      await device.connect(
        license: License.nonprofit, // student project at a university
        timeout: const Duration(seconds: 10),
      );
      _device = device;
      if (!_running) {
        // Stopped while connecting: let go again straight away.
        await _releaseDevice();
        return;
      }

      // Services must be rediscovered after every connection.
      final services = await device.discoverServices();
      final service = services.firstWhere((s) => s.uuid == serviceUuid);
      final characteristic =
          service.characteristics.firstWhere((c) => c.uuid == distanceUuid);

      await _valueSub?.cancel();
      _valueSub = characteristic.onValueReceived.listen(_onValue);
      await characteristic.setNotifyValue(true);

      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) _onLost();
      });

      if (!_running) {
        await _releaseDevice();
        return;
      }
      _connected = true;
      _stale = false;
      _misses = 0;
      _lastReading = DateTime.now();
      _setStatus('Connected');
    } catch (_) {
      await _releaseDevice();
      _scheduleRetry('Could not connect');
    } finally {
      _connecting = false;
    }
  }

  /// Scans for the wearable by its service ID or its name, whichever
  /// arrives first. Returns null if nothing is found within [scanTime].
  Future<BluetoothDevice?> _scan() async {
    final found = Completer<BluetoothDevice?>();
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final named = r.advertisementData.advName == deviceName ||
            r.device.platformName == deviceName;
        final offers = r.advertisementData.serviceUuids.contains(serviceUuid);
        if ((named || offers) && !found.isCompleted) {
          found.complete(r.device);
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [serviceUuid],
        withNames: [deviceName],
        timeout: scanTime,
      );
      return await found.future.timeout(scanTime, onTimeout: () => null);
    } finally {
      await sub.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  /// Reads the distance in centimetres from a message such as
  /// "DIST:85;BAND:NEAR". Returns -1 for "nothing in range" and null if the
  /// message has no distance in it.
  static int? parseCentimetres(String message) {
    final match = RegExp(r'DIST:(-?\d+)').firstMatch(message);
    if (match == null) return null;
    final cm = int.parse(match.group(1)!);
    return cm < 0 ? -1 : cm;
  }

  void _onValue(List<int> bytes) {
    final cm = parseCentimetres(utf8.decode(bytes, allowMalformed: true));
    if (cm == null) return;

    _lastReading = DateTime.now();
    final wasStale = _stale;
    _stale = false;
    if (wasStale) _setStatus('Connected');

    if (cm < 0) {
      _misses++;
      if (_misses >= missesBeforeClear) _emit(clearMetres);
      return;
    }
    _misses = 0;
    _emit(cm / 100.0);
  }

  /// Connected, but readings have stopped: treat it like a disconnection.
  void _checkStale() {
    final last = _lastReading;
    if (!_connected || _stale || last == null) return;
    if (DateTime.now().difference(last) > staleAfter) {
      _stale = true;
      _setStatus('No readings from sensor');
      _emit(null);
    }
  }

  void _onLost() {
    final wasLive = _connected && !_stale;
    _connected = false;
    _stale = false;
    _valueSub?.cancel();
    _valueSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    _device = null;
    if (wasLive) _emit(null);
    _scheduleRetry('Sensor disconnected');
  }

  void _scheduleRetry(String reason) {
    if (!_running) return;
    _setStatus('$reason. Trying again…');
    _retry?.cancel();
    _retry = Timer(retryDelay, () => unawaited(_connect()));
  }

  Future<void> _releaseDevice() async {
    await _valueSub?.cancel();
    _valueSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  void _emit(double? metres) {
    if (!_controller.isClosed) _controller.add(metres);
  }

  void _setStatus(String text) {
    if (!_disposed) status.value = text;
  }

  @override
  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _retry = null;
    _watchdog?.cancel();
    _watchdog = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _releaseDevice();
    _connected = false;
    _stale = false;
    _setStatus('Stopped');
  }

  @override
  Future<void> dispose() async {
    await stop();
    _disposed = true;
    await _controller.close();
    status.dispose();
  }
}
