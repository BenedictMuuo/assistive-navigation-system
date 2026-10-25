import 'package:flutter/services.dart';

import 'risk/risk_alert_policy.dart';

/// Plays the vibration patterns used for risk alerts.
///
/// Uses Flutter's built-in haptic feedback rather than a vibration plugin,
/// so it adds no Android build dependencies. The trade-off: Android only
/// vibrates if the phone's own "touch feedback" setting is on. Emulators
/// do not vibrate at all, so test this part on a real phone.
class Haptics {
  static Future<void> play(Haptic pattern) async {
    switch (pattern) {
      case Haptic.none:
        return;
      case Haptic.short:
        await HapticFeedback.mediumImpact();
      case Haptic.strong:
        for (var i = 0; i < 3; i++) {
          await HapticFeedback.heavyImpact();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
    }
  }
}
