import 'package:assistive_nav/services/distance/ble_distance_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BleDistanceSource.parseCentimetres', () {
    test('reads the distance from a normal message', () {
      expect(BleDistanceSource.parseCentimetres('DIST:85;BAND:NEAR'), 85);
      expect(BleDistanceSource.parseCentimetres('DIST:224;BAND:FAR'), 224);
    });

    test('reports nothing in range as -1', () {
      expect(BleDistanceSource.parseCentimetres('DIST:-1;BAND:CLEAR'), -1);
    });

    test('ignores messages without a distance', () {
      expect(BleDistanceSource.parseCentimetres('BAND:NEAR'), isNull);
      expect(BleDistanceSource.parseCentimetres(''), isNull);
      expect(BleDistanceSource.parseCentimetres('hello'), isNull);
    });
  });
}
