import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sos_alert.dart';
import '../models/user_profile.dart';
import '../services/alert_service.dart';
import '../services/auth_service.dart';
import '../services/speech_service.dart';
import '../theme.dart';

/// The caregiver's live list of SOS alerts.
class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({
    super.key,
    required this.profile,
    required this.auth,
  });

  final UserProfile profile;
  final AuthService auth;

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  final AlertService _service = AlertService();
  final SpeechService _speech = SpeechService();

  StreamSubscription<List<SosAlert>>? _sub;
  Timer? _clock;

  List<SosAlert> _alerts = const [];
  final Set<String> _seen = {};
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _speech.init();

    _sub = _service.alertsFor(widget.profile.email).listen(
      _onAlerts,
      onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      },
    );

    // Keeps "3 min ago" labels current.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onAlerts(List<SosAlert> alerts) {
    // The first batch is history. Only alerts that arrive after the
    // screen opens should make the phone buzz.
    final fresh = _loaded
        ? alerts.where((a) => a.isOpen && !_seen.contains(a.id)).toList()
        : <SosAlert>[];

    _seen.addAll(alerts.map((a) => a.id));
    setState(() {
      _alerts = alerts;
      _loaded = true;
      _error = null;
    });

    for (final alert in fresh) {
      _ring(alert);
    }
  }

  Future<void> _ring(SosAlert alert) async {
    HapticFeedback.vibrate();
    SystemSound.play(SystemSoundType.alert);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColours.danger,
          duration: const Duration(seconds: 6),
          content: Text('New SOS from ${alert.userName}',
              style: const TextStyle(fontSize: 18)),
        ),
      );
    }
    await _speech.say('New S O S from ${alert.userName}.');
  }

  Future<void> _openMap(SosAlert alert) async {
    final url = alert.mapsUrl;
    if (url == null) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the map.')),
      );
    }
  }

  Future<void> _acknowledge(SosAlert alert) async {
    try {
      await _service.acknowledge(alert.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the alert: $e')),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS alerts'),
        backgroundColor: AppColours.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: widget.auth.signOut,
            child: const Text('Sign out',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _centred('Could not load alerts.\n\n$_error');
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_alerts.isEmpty) {
      return _centred(
        'No alerts yet.\n\nYou will see SOS alerts here from anyone who '
        'lists ${widget.profile.email} as their caregiver.',
      );
    }

    final now = DateTime.now();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _card(_alerts[i], now),
    );
  }

  Widget _card(SosAlert a, DateTime now) {
    final age = describeAge(a.createdAt, now);
    final where = a.hasLocation
        ? '${a.latitude!.toStringAsFixed(5)}, '
            '${a.longitude!.toStringAsFixed(5)}'
            '${a.accuracyMetres == null ? '' : '  (±${a.accuracyMetres!.round()} m)'}'
        : 'Location not available';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: a.isOpen ? AppColours.danger : Colors.grey.shade400,
          width: a.isOpen ? 3 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sos,
                    color: a.isOpen ? AppColours.danger : Colors.grey,
                    size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('SOS from ${a.userName}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('$age  ·  ${a.isOpen ? 'Needs attention' : 'Handled'}',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(where, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (a.hasLocation)
                  ElevatedButton.icon(
                    onPressed: () => _openMap(a),
                    icon: const Icon(Icons.map),
                    label: const Text('Open map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColours.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(140, 48),
                    ),
                  ),
                if (a.isOpen)
                  OutlinedButton.icon(
                    onPressed: () => _acknowledge(a),
                    icon: const Icon(Icons.check),
                    label: const Text('Mark handled'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(140, 48),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _centred(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
