/// Where distance readings come from.
///
/// The app depends only on this interface, never on a particular sensor.
/// Today the readings come from [MockDistanceSource]; when the ESP32
/// ultrasonic unit is available, a Bluetooth implementation slots in here
/// and nothing else in the app changes.
///
/// The system must already keep working if the sensor disconnects mid-walk.
/// "No sensor at all" is simply the permanent case of that: readings stop,
/// and the app falls back to camera-only operation.
abstract class DistanceSource {
  /// Shown to the user, e.g. "Simulated sensor" or "ESP32 ultrasonic".
  String get name;

  /// Distance to the nearest obstacle ahead, in metres. A null reading
  /// means the source has disconnected and nothing is known.
  Stream<double?> get readings;

  bool get isConnected;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}
