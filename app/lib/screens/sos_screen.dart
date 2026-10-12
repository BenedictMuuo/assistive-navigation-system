import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_profile.dart';
import '../services/alert_service.dart';
import '../services/location_service.dart';
import '../services/speech_service.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

enum _Phase { countdown, sending, sent, queued, failed }

/// Counts down, then sends an SOS with the user's location.
///
/// The countdown exists because the user cannot see the screen and may
/// press SOS by accident. During it, the whole screen is one large cancel
/// button - no aiming needed. If nothing happens, the alert goes out on
/// its own, so a user who is hurt or panicking does not need to do
/// anything more.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key, required this.profile, this.seconds = 5});

  final UserProfile profile;
  final int seconds;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final SpeechService _speech = SpeechService();
  final AlertService _alerts = AlertService();
  final LocationService _location = LocationService();

  Timer? _timer;
  late int _remaining = widget.seconds;
  _Phase _phase = _Phase.countdown;
  String _detail = '';

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    HapticFeedback.heavyImpact();
    await _speech.init();
    await _speech.say(
      'Sending S O S in ${widget.seconds} seconds. '
      'Tap anywhere to cancel.',
    );
    if (!mounted || _phase != _Phase.countdown) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        _send();
      } else {
        HapticFeedback.mediumImpact();
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _cancel() async {
    if (_phase != _Phase.countdown) return;
    _timer?.cancel();
    _phase = _Phase.failed; // stops _begin from starting the timer late
    await _speech.say('S O S cancelled.');
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _send() async {
    setState(() => _phase = _Phase.sending);
    await _speech.say('Sending S O S.');

    final position = await _location.currentPosition();
    final where = position == null
        ? ' Your location could not be found, but your caregiver has been '
            'told you need help.'
        : '';

    try {
      await _alerts
          .sendSos(from: widget.profile, position: position)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _phase = _Phase.sent;
        _detail = position == null
            ? 'Sent without location.'
            : 'Sent with your location.';
      });
      HapticFeedback.heavyImpact();
      await _speech.say('S O S sent to your caregiver.$where');
    } on TimeoutException {
      // Firestore keeps the write and sends it as soon as the phone is
      // back online, so the alert is not lost.
      if (!mounted) return;
      setState(() {
        _phase = _Phase.queued;
        _detail = 'No connection. The alert will send automatically '
            'as soon as the phone is back online.';
      });
      await _speech.say(
        'No internet connection. The S O S will send automatically '
        'when the phone reconnects.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _detail = '$e';
      });
      await _speech.say('S O S could not be sent. Tap try again.');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.countdown) {
      return Semantics(
        button: true,
        label: 'Sending S O S in $_remaining seconds. Double tap to cancel.',
        onTap: _cancel,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _cancel,
          child: Scaffold(
            backgroundColor: AppColours.danger,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Sending SOS in',
                        style: TextStyle(color: Colors.white, fontSize: 32)),
                    Text('$_remaining',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 140,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    const Text('TAP ANYWHERE TO CANCEL',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final (title, colour) = switch (_phase) {
      _Phase.sending => ('Sending SOS…', AppColours.primary),
      _Phase.sent => ('SOS sent', AppColours.active),
      _Phase.queued => ('Waiting for connection', AppColours.primary),
      _ => ('SOS not sent', AppColours.danger),
    };

    return Scaffold(
      backgroundColor: colour,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_phase == _Phase.sending)
                const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              Text(_detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20)),
              const SizedBox(height: 40),
              if (_phase == _Phase.failed)
                BigButton(
                  label: 'Try again',
                  colour: Colors.black87,
                  onPressed: _send,
                ),
              if (_phase != _Phase.sending) ...[
                const SizedBox(height: 16),
                BigButton(
                  label: 'Done',
                  colour: Colors.black87,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
