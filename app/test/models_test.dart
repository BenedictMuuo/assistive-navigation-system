import 'package:assistive_nav/models/sos_alert.dart';
import 'package:assistive_nav/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normaliseEmail', () {
    test('trims and lower-cases', () {
      expect(normaliseEmail('  Mary.W@Gmail.COM '), 'mary.w@gmail.com');
    });
  });

  group('UserProfile', () {
    test('a user keeps their caregiver email, normalised', () {
      const p = UserProfile(
        uid: 'u1',
        name: 'Ben',
        email: 'Ben@Example.com',
        role: UserRole.user,
        caregiverEmail: ' Mum@Example.com ',
      );
      final map = p.toMap();
      expect(map['role'], 'user');
      expect(map['email'], 'ben@example.com');
      expect(map['caregiverEmail'], 'mum@example.com');
    });

    test('a caregiver never stores a caregiver email of their own', () {
      const p = UserProfile(
        uid: 'c1',
        name: 'Mum',
        email: 'mum@example.com',
        role: UserRole.caregiver,
        caregiverEmail: 'someone@example.com',
      );
      expect(p.toMap().containsKey('caregiverEmail'), isFalse);
    });

    test('round-trips through a Firestore map', () {
      final p = UserProfile.fromMap('u1', {
        'name': 'Ben',
        'email': 'ben@example.com',
        'role': 'user',
        'caregiverEmail': 'mum@example.com',
      });
      expect(p.role, UserRole.user);
      expect(p.hasCaregiver, isTrue);
      expect(p.isCaregiver, isFalse);
    });

    test('an unknown role is treated as a user, never a caregiver', () {
      final p = UserProfile.fromMap('x', {'role': 'admin'});
      expect(p.role, UserRole.user);
    });

    test('a blank caregiver email counts as none', () {
      final p = UserProfile.fromMap('u1', {'role': 'user', 'caregiverEmail': '  '});
      expect(p.hasCaregiver, isFalse);
    });
  });

  group('SosAlert', () {
    test('builds a Google Maps link from coordinates', () {
      expect(
        SosAlert.mapsUrlFor(-1.3094, 36.8122),
        'https://www.google.com/maps/search/?api=1&query=-1.3094,36.8122',
      );
    });
  });

  group('describeAge', () {
    final now = DateTime(2026, 10, 12, 15, 30);

    test('pending server timestamp reads as just now', () {
      expect(describeAge(null, now), 'just now');
    });
    test('seconds', () {
      expect(describeAge(now.subtract(const Duration(seconds: 20)), now),
          'just now');
    });
    test('minutes', () {
      expect(describeAge(now.subtract(const Duration(minutes: 3)), now),
          '3 min ago');
    });
    test('hours', () {
      expect(describeAge(now.subtract(const Duration(hours: 2)), now),
          '2 h ago');
    });
    test('older than a day shows the date', () {
      expect(describeAge(DateTime(2026, 10, 9, 8, 5), now), '9 Oct, 08:05');
    });
  });
}
