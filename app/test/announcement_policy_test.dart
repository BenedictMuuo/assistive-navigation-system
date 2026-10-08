import 'package:assistive_nav/services/announcement_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 10, 8, 12);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  group('AnnouncementPolicy', () {
    test('a clear path is silent', () {
      final p = AnnouncementPolicy();
      final a = p.next('background', at(0), speaking: false);
      expect(a.action, AnnounceAction.none);
    });

    test('an unsure model is silent', () {
      final p = AnnouncementPolicy();
      expect(p.next(null, at(0), speaking: false).action, AnnounceAction.none);
    });

    test('a new obstacle is announced once', () {
      final p = AnnouncementPolicy();
      final first = p.next('chair', at(0), speaking: false);
      expect(first.action, AnnounceAction.speak);
      expect(first.phrase, 'Chair ahead');

      // Still in view a minute later: not repeated.
      expect(p.next('chair', at(60), speaking: false).action,
          AnnounceAction.none);
    });

    test('a different obstacle is announced', () {
      final p = AnnouncementPolicy();
      p.next('chair', at(0), speaking: false);
      final next = p.next('door', at(2), speaking: false);
      expect(next.action, AnnounceAction.speak);
      expect(next.phrase, 'Door ahead');
    });

    test('an obstacle that returns after a clear path is announced again', () {
      final p = AnnouncementPolicy();
      p.next('chair', at(0), speaking: false);
      p.next('background', at(2), speaking: false);
      expect(p.next('chair', at(4), speaking: false).action,
          AnnounceAction.speak);
    });

    test('a brief unsure moment does not cause a repeat', () {
      final p = AnnouncementPolicy();
      p.next('chair', at(0), speaking: false);
      p.next(null, at(1), speaking: false);
      expect(p.next('chair', at(2), speaking: false).action,
          AnnounceAction.none);
    });

    test('ordinary obstacles never talk over current speech', () {
      final p = AnnouncementPolicy();
      p.next('chair', at(0), speaking: false);
      expect(p.next('door', at(1), speaking: true).action,
          AnnounceAction.none);
      // Once speech has finished, the door is announced.
      expect(p.next('door', at(2), speaking: false).action,
          AnnounceAction.speak);
    });

    test('stairs interrupt current speech', () {
      final p = AnnouncementPolicy();
      p.next('chair', at(0), speaking: false);
      final a = p.next('stairs', at(1), speaking: true);
      expect(a.action, AnnounceAction.interrupt);
      expect(a.phrase, 'Stairs ahead. Caution.');
    });

    test('stairs repeat while they stay in view, but not too often', () {
      final p = AnnouncementPolicy(urgentRepeat: const Duration(seconds: 5));
      expect(p.next('stairs', at(0), speaking: false).action,
          AnnounceAction.speak);
      expect(p.next('stairs', at(3), speaking: false).action,
          AnnounceAction.none);
      expect(p.next('stairs', at(5), speaking: false).action,
          AnnounceAction.speak);
    });

    test('reset forgets the last obstacle', () {
      final p = AnnouncementPolicy();
      p.next('wall', at(0), speaking: false);
      p.reset();
      expect(p.next('wall', at(1), speaking: false).action,
          AnnounceAction.speak);
    });
  });
}
