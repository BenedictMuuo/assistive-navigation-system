import 'package:flutter_tts/flutter_tts.dart';

import 'announcement_policy.dart';

/// Speaks announcements aloud, following [AnnouncementPolicy].
class SpeechService {
  SpeechService({AnnouncementPolicy? policy, double rate = 0.5})
      : policy = policy ?? AnnouncementPolicy(),
        _rate = rate;

  final AnnouncementPolicy policy;
  final FlutterTts _tts = FlutterTts();

  double _rate;
  bool _speaking = false;
  bool _ready = false;

  bool get isSpeaking => _speaking;

  /// Speech rate, 0.0 to 1.0. 0.5 is normal speed on Android.
  double get rate => _rate;

  Future<void> init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_rate);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((_) => _speaking = false);

    _ready = true;
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.1, 1.0);
    await _tts.setSpeechRate(_rate);
  }

  /// Call once per frame with the smoother's steady label.
  /// Returns the phrase spoken, or null if nothing was said.
  Future<String?> update(String? steadyLabel) async {
    if (!_ready) return null;

    final decision = policy.next(
      steadyLabel,
      DateTime.now(),
      speaking: _speaking,
    );

    switch (decision.action) {
      case AnnounceAction.none:
        return null;
      case AnnounceAction.interrupt:
        await _tts.stop();
        _speaking = true;
        await _tts.speak(decision.phrase!);
        return decision.phrase;
      case AnnounceAction.speak:
        _speaking = true;
        await _tts.speak(decision.phrase!);
        return decision.phrase;
    }
  }

  /// Speaks a one-off message, such as "Detection started".
  Future<void> say(String text) async {
    if (!_ready) return;
    await _tts.stop();
    _speaking = true;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    policy.reset();
    await _tts.stop();
    _speaking = false;
  }
}
