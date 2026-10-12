import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'caregiver_home_screen.dart';
import 'sign_in_screen.dart';
import 'user_home_screen.dart';

/// Decides which screen to show: sign-in, the user's home, or the
/// caregiver's alert list. It reacts on its own when someone signs in or
/// out, so no other screen needs to handle navigation for that.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();
  late final Stream<User?> _authStream = _auth.authChanges;

  String? _profileUid;
  Stream<UserProfile?>? _profileStream;

  Stream<UserProfile?> _profileFor(String uid) {
    if (_profileUid != uid || _profileStream == null) {
      _profileUid = uid;
      _profileStream = _auth.profile(uid);
    }
    return _profileStream!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Waiting(message: 'Starting…');
        }

        final user = authSnap.data;
        if (user == null) return SignInScreen(auth: _auth);

        return StreamBuilder<UserProfile?>(
          stream: _profileFor(user.uid),
          builder: (context, profileSnap) {
            if (profileSnap.hasError) {
              return _Waiting(
                message: 'Could not load your account.\n'
                    '${profileSnap.error}',
                onSignOut: _auth.signOut,
              );
            }

            final profile = profileSnap.data;
            if (profile == null) {
              // Straight after registration the profile takes a moment to
              // be written. The stream updates by itself when it is.
              return _Waiting(
                message: 'Setting up your account…',
                onSignOut: _auth.signOut,
              );
            }

            return profile.isCaregiver
                ? CaregiverHomeScreen(profile: profile, auth: _auth)
                : UserHomeScreen(profile: profile, auth: _auth);
          },
        );
      },
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.message, this.onSignOut});

  final String message;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              if (onSignOut != null) ...[
                const SizedBox(height: 24),
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
