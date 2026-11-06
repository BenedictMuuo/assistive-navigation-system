import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/speech_service.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

/// Caregiver email and sign out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.profile, required this.auth});

  final UserProfile profile;
  final AuthService auth;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _caregiver =
      TextEditingController(text: widget.profile.caregiverEmail ?? '');

  final SpeechService _speech = SpeechService();

  bool _busy = false;
  bool _signingOut = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _speech.init();
  }

  @override
  void dispose() {
    _caregiver.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _save() async {
    final email = normaliseEmail(_caregiver.text);
    if (!email.contains('@')) {
      setState(() {
        _message = 'Enter a valid email address.';
        _messageIsError = true;
      });
      return;
    }
    if (email == normaliseEmail(widget.profile.email)) {
      setState(() {
        _message = 'Your caregiver must be someone else.';
        _messageIsError = true;
      });
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.auth.setCaregiverEmail(widget.profile.uid, email);
      setState(() {
        _message = 'Saved. SOS alerts will go to $email.';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _message = 'Could not save: $e';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    final signedOut = await widget.auth.signOut();
    if (!mounted) return;
    if (signedOut) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _signingOut = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text(AuthService.unsentWarning,
            style: TextStyle(fontSize: 18)),
      ),
    );
    await _speech.say(AuthService.unsentWarningSpoken);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColours.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Caregiver',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Your caregiver receives your SOS alerts. They need their own '
              'account in this app, registered as a caregiver with this email.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _caregiver,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: 'Caregiver email address',
                border: OutlineInputBorder(),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: TextStyle(
                    fontSize: 18,
                    color:
                        _messageIsError ? AppColours.danger : AppColours.active,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            BigButton(
              label: _busy ? 'Saving…' : 'Save caregiver',
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 48),
            const Divider(),
            const SizedBox(height: 16),
            Text('Signed in as ${widget.profile.email}',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            BigButton(
              label: _signingOut ? 'Signing out…' : 'Sign out',
              colour: Colors.black87,
              height: 64,
              fontSize: 20,
              onPressed: _signingOut ? null : _signOut,
            ),
          ],
        ),
      ),
    );
  }
}
