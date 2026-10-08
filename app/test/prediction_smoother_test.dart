import 'package:assistive_nav/services/prediction_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PredictionSmoother', () {
    test('stays silent until a label wins 3 of the last 5 frames', () {
      final s = PredictionSmoother();
      expect(s.add('chair', 0.9), isNull);
      expect(s.add('chair', 0.9), isNull);
      expect(s.add('chair', 0.9), 'chair');
    });

    test('ignores frames below the confidence threshold', () {
      final s = PredictionSmoother();
      s.add('chair', 0.9);
      s.add('chair', 0.9);
      // A low-confidence chair does not count towards the three.
      expect(s.add('chair', 0.5), isNull);
      expect(s.add('chair', 0.8), 'chair');
    });

    test('a flickering label is never accepted', () {
      final s = PredictionSmoother();
      final sequence = ['chair', 'table', 'wall', 'door', 'chair', 'table'];
      for (final label in sequence) {
        expect(s.add(label, 0.95), isNull);
      }
    });

    test('old frames fall out of the window', () {
      final s = PredictionSmoother();
      for (var i = 0; i < 3; i++) {
        s.add('stairs', 0.9);
      }
      expect(s.current, 'stairs');

      // Two doors: the window is stairs x3, door x2, so stairs still wins.
      s.add('door', 0.9);
      expect(s.add('door', 0.9), 'stairs');

      // A third door pushes the oldest stairs out: stairs x2, door x3.
      expect(s.add('door', 0.9), 'door');
    });

    test('reset clears everything', () {
      final s = PredictionSmoother();
      for (var i = 0; i < 3; i++) {
        s.add('wall', 0.9);
      }
      s.reset();
      expect(s.current, isNull);
    });

    test('a confidence exactly at the threshold counts', () {
      final s = PredictionSmoother(threshold: 0.7);
      s.add('bag', 0.7);
      s.add('bag', 0.7);
      expect(s.add('bag', 0.7), 'bag');
    });
  });
}
