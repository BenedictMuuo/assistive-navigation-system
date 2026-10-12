import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/speech_service.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import 'detection_screen.dart';
import 'settings_screen.dart';
import 'sos_screen.dart';

/// The visually impaired user's home: start navigation, or call for help.
class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key, required this.profile, required this.auth});

  final UserProfile profile;
  final AuthService auth;

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  final SpeechService _speech = SpeechService();

  @override
  void initState() {
    super.initState();
    _speech.init();
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  String get _firstName {
    final name = widget.profile.name.trim();
    return name.isEmpty ? 'there' : name.split(' ').first;
  }

  void _startNavigation() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DetectionScreen()),
    );
  }

  Future<void> _sos() async {
    if (!widget.profile.hasCaregiver) {
      const message =
          'No caregiver is set. Add your caregiver\'s email in settings.';
      await _speech.say(message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(message)),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SosScreen(profile: widget.profile)),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          profile: widget.profile,
          auth: widget.auth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caregiver = widget.profile.hasCaregiver
        ? 'Caregiver: ${widget.profile.caregiverEmail}'
        : 'No caregiver set. Add one in Settings.';

    return Scaffold(
      appBar: AppBar(
        title: Text('Hello, $_firstName'),
        backgroundColor: AppColours.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, size: 32),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                caregiver,
                style: TextStyle(
                  fontSize: 18,
                  color: widget.profile.hasCaregiver
                      ? Colors.black87
                      : AppColours.danger,
                ),
              ),
              const SizedBox(height: 24),
              BigButton(
                label: 'Start navigation',
                icon: Icons.visibility,
                height: 120,
                fontSize: 28,
                onPressed: _startNavigation,
              ),
              const Spacer(),
              // Placed at the bottom, apart from navigation, so it is not
              // pressed by accident - and it has a cancel countdown anyway.
              BigButton(
                label: 'SOS',
                semanticLabel: 'SOS. Send an emergency alert to your caregiver',
                icon: Icons.sos,
                colour: AppColours.danger,
                height: 160,
                fontSize: 44,
                onPressed: _sos,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
