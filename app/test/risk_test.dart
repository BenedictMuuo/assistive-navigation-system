import 'package:assistive_nav/services/risk/risk_alert_policy.dart';
import 'package:assistive_nav/services/risk/risk_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DistanceBander', () {
    test('first reading sets the band directly', () {
      expect(DistanceBander().update(0.5), DistanceBand.near);
      expect(DistanceBander().update(2.0), DistanceBand.medium);
      expect(DistanceBander().update(4.0), DistanceBand.far);
    });

    test('no reading means unknown', () {
      final b = DistanceBander()..update(2.0);
      expect(b.update(null), DistanceBand.unknown);
    });

    test('wobble around the 1 m boundary does not flip the band', () {
      final b = DistanceBander()..update(1.5); // medium
      for (final m in [1.05, 0.95, 1.02, 0.90, 0.97, 1.10]) {
        expect(b.update(m), DistanceBand.medium, reason: '$m m');
      }
    });

    test('must cross the boundary by the margin to become near', () {
      final b = DistanceBander()..update(1.5);
      expect(b.update(0.86), DistanceBand.medium);
      expect(b.update(0.84), DistanceBand.near);
    });

    test('must cross back by the margin to leave near', () {
      final b = DistanceBander()..update(0.5); // near
      expect(b.update(1.10), DistanceBand.near);
      expect(b.update(1.16), DistanceBand.medium);
    });

    test('same hysteresis at the 3 m boundary', () {
      final b = DistanceBander()..update(2.0); // medium
      expect(b.update(3.10), DistanceBand.medium);
      expect(b.update(3.16), DistanceBand.far);
      expect(b.update(2.90), DistanceBand.far);
      expect(b.update(2.84), DistanceBand.medium);
    });

    test('a large jump skips a band', () {
      final b = DistanceBander()..update(4.0); // far
      expect(b.update(0.5), DistanceBand.near);
      expect(b.update(4.0), DistanceBand.far);
    });

    test('after reconnecting there is no stale history', () {
      final b = DistanceBander()..update(0.5);
      b.update(null);
      expect(b.update(1.05), DistanceBand.medium);
    });
  });

  group('RiskTable', () {
    test('stairs are high risk near and at medium distance', () {
      expect(RiskTable.assess('stairs', DistanceBand.near), RiskLevel.high);
      expect(RiskTable.assess('stairs', DistanceBand.medium), RiskLevel.high);
      expect(RiskTable.assess('stairs', DistanceBand.far), RiskLevel.medium);
    });

    test('a chair matters only when close', () {
      expect(RiskTable.assess('chair', DistanceBand.near), RiskLevel.high);
      expect(RiskTable.assess('chair', DistanceBand.medium), RiskLevel.medium);
      expect(RiskTable.assess('chair', DistanceBand.far), RiskLevel.low);
    });

    test('a clear path is always low', () {
      for (final band in DistanceBand.values) {
        expect(RiskTable.assess('background', band), RiskLevel.low);
      }
    });

    test('camera-only mode: stairs high, everything else medium', () {
      expect(RiskTable.assess('stairs', DistanceBand.unknown), RiskLevel.high);
      expect(RiskTable.assess('chair', DistanceBand.unknown), RiskLevel.medium);
    });

    test('an unknown class is treated with caution', () {
      expect(RiskTable.assess('bicycle', DistanceBand.far), RiskLevel.medium);
    });

    test('every model class has a row', () {
      const classes = [
        'background', 'bag', 'chair', 'door',
        'person', 'stairs', 'table', 'wall',
      ];
      for (final c in classes) {
        expect(RiskTable.table.containsKey(c), isTrue, reason: c);
      }
    });
  });

  group('RiskAlertPolicy', () {
    final t0 = DateTime(2026, 10, 12, 12);
    DateTime at(int s) => t0.add(Duration(seconds: s));

    test('low risk is completely silent', () {
      final p = RiskAlertPolicy();
      expect(p.next('chair', RiskLevel.low, at(0), speaking: false).isSilent,
          isTrue);
    });

    test('medium risk vibrates once and does not speak', () {
      final p = RiskAlertPolicy();
      final a = p.next('chair', RiskLevel.medium, at(0), speaking: false);
      expect(a.haptic, Haptic.short);
      expect(a.phrase, isNull);
      expect(p.next('chair', RiskLevel.medium, at(10), speaking: false)
          .isSilent, isTrue);
    });

    test('rising to high vibrates strongly and speaks', () {
      final p = RiskAlertPolicy();
      p.next('chair', RiskLevel.medium, at(0), speaking: false);
      final a = p.next('chair', RiskLevel.high, at(2), speaking: true);
      expect(a.haptic, Haptic.strong);
      expect(a.phrase, 'Chair, close.');
      expect(a.interrupt, isTrue);
    });

    test('high risk repeats vibration only, after the repeat gap', () {
      final p = RiskAlertPolicy(highRepeat: const Duration(seconds: 5));
      p.next('wall', RiskLevel.high, at(0), speaking: false);
      expect(p.next('wall', RiskLevel.high, at(3), speaking: false).isSilent,
          isTrue);
      final again = p.next('wall', RiskLevel.high, at(5), speaking: false);
      expect(again.haptic, Haptic.strong);
      expect(again.phrase, isNull);
    });

    test('stairs repeat the spoken warning too', () {
      final p = RiskAlertPolicy(highRepeat: const Duration(seconds: 5));
      p.next('stairs', RiskLevel.high, at(0), speaking: false);
      final again = p.next('stairs', RiskLevel.high, at(6), speaking: false);
      expect(again.phrase, 'Stairs ahead. Caution.');
    });

    test('falling risk is silent, and rising again warns again', () {
      final p = RiskAlertPolicy();
      p.next('chair', RiskLevel.high, at(0), speaking: false);
      expect(p.next('chair', RiskLevel.medium, at(1), speaking: false)
          .isSilent, isTrue);
      expect(p.next('chair', RiskLevel.high, at(2), speaking: false).phrase,
          'Chair, close.');
    });

    test('a new object is announced at its own level', () {
      final p = RiskAlertPolicy();
      p.next('chair', RiskLevel.high, at(0), speaking: false);
      final a = p.next('door', RiskLevel.medium, at(1), speaking: false);
      expect(a.haptic, Haptic.short);
    });

    test('an unsure frame changes nothing', () {
      final p = RiskAlertPolicy();
      p.next('chair', RiskLevel.medium, at(0), speaking: false);
      p.next(null, RiskLevel.low, at(1), speaking: false);
      expect(p.next('chair', RiskLevel.medium, at(2), speaking: false)
          .isSilent, isTrue);
    });
  });
}
