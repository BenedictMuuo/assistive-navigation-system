import 'risk_rules.dart';

enum Haptic {
  none,

  /// One short pulse: something to be aware of.
  short,

  /// Three strong pulses: act now.
  strong,
}

/// What to do in response to one frame.
class RiskAlert {
  const RiskAlert({
    this.haptic = Haptic.none,
    this.phrase,
    this.interrupt = false,
  });

  static const RiskAlert none = RiskAlert();

  final Haptic haptic;

  /// Words to speak, or null for silence.
  final String? phrase;

  /// Cut off speech already playing.
  final bool interrupt;

  bool get isSilent => haptic == Haptic.none && phrase == null;
}

/// Decides how to warn the user, by risk level.
///
/// Blind pedestrians navigate largely by ear, so the hearing channel is
/// kept free unless something is genuinely urgent:
///
///   low    - nothing at all. Silence is the normal state.
///   medium - one short vibration. No speech.
///   high   - strong vibration and a two- or three-word warning, cutting
///            off anything else being said.
///
/// Each warning is given when the risk first appears or rises - not on
/// every frame. While a high risk persists the vibration repeats every
/// [highRepeat]; for stairs, the spoken warning repeats too.
///
/// Holds no audio or vibration code, so every rule can be unit tested.
class RiskAlertPolicy {
  RiskAlertPolicy({
    this.highRepeat = const Duration(seconds: 5),
    this.repeatSpeechFor = const {'stairs'},
  });

  final Duration highRepeat;
  final Set<String> repeatSpeechFor;

  String? _label;
  RiskLevel _level = RiskLevel.low;
  DateTime? _lastHighAt;

  RiskAlert next(
    String? label,
    RiskLevel level,
    DateTime now, {
    required bool speaking,
  }) {
    // Model unsure: say nothing, and keep memory so a brief wobble does
    // not trigger a second warning for the same obstacle.
    if (label == null) return RiskAlert.none;

    final bool newObject = label != _label;
    final bool rose = level.index > _level.index;

    if (!newObject && !rose) {
      // Same object, same or lower risk.
      if (level.index < _level.index) _level = level; // calm down silently
      if (level == RiskLevel.high) return _maybeRepeat(label, now);
      return RiskAlert.none;
    }

    _label = label;
    _level = level;

    switch (level) {
      case RiskLevel.low:
        return RiskAlert.none;
      case RiskLevel.medium:
        return const RiskAlert(haptic: Haptic.short);
      case RiskLevel.high:
        _lastHighAt = now;
        return RiskAlert(
          haptic: Haptic.strong,
          phrase: phraseFor(label),
          interrupt: speaking,
        );
    }
  }

  RiskAlert _maybeRepeat(String label, DateTime now) {
    final last = _lastHighAt;
    if (last != null && now.difference(last) < highRepeat) {
      return RiskAlert.none;
    }
    _lastHighAt = now;
    final speak = repeatSpeechFor.contains(label);
    return RiskAlert(
      haptic: Haptic.strong,
      phrase: speak ? phraseFor(label) : null,
      interrupt: speak,
    );
  }

  void reset() {
    _label = null;
    _level = RiskLevel.low;
    _lastHighAt = null;
  }

  /// Short on purpose: fast to say, fast to understand.
  static String phraseFor(String label) {
    if (label == 'stairs') return 'Stairs ahead. Caution.';
    if (label.isEmpty) return label;
    return '${label[0].toUpperCase()}${label.substring(1)}, close.';
  }
}
