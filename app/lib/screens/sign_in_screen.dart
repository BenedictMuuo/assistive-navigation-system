import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

/// Sign in, or create an account as a user or a caregiver.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registering = false;
  bool _showPassword = false;
  bool _busy = false;
  UserRole _role = UserRole.user;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_registering && _name.text.trim().isEmpty) {
      return 'Enter your name.';
    }
    if (!_email.text.contains('@')) return 'Enter a valid email address.';
    if (_password.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_registering) {
        await widget.auth.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          role: _role,
        );
      } else {
        await widget.auth.signIn(_email.text, _password.text);
      }
      // AuthGate notices the sign-in and swaps the screen by itself.
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_registering ? 'Create account' : 'Sign in'),
        backgroundColor: AppColours.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_registering) ...[
              _field(_name, 'Your name', TextInputType.name),
              const SizedBox(height: 16),
            ],
            _field(_email, 'Email address', TextInputType.emailAddress),
            const SizedBox(height: 16),
            _field(
              _password,
              'Password',
              TextInputType.visiblePassword,
              obscure: !_showPassword,
              // Lets a low-vision user check what they typed.
              suffix: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                  size: 28,
                ),
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            if (_registering) ...[
              const SizedBox(height: 20),
              const Text(
                'I am:',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              RadioListTile<UserRole>(
                value: UserRole.user,
                groupValue: _role,
                onChanged: (r) => setState(() => _role = r!),
                title: const Text('A user, getting navigation help',
                    style: TextStyle(fontSize: 18)),
              ),
              RadioListTile<UserRole>(
                value: UserRole.caregiver,
                groupValue: _role,
                onChanged: (r) => setState(() => _role = r!),
                title: const Text('A caregiver, receiving SOS alerts',
                    style: TextStyle(fontSize: 18)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              // Read out by TalkBack as soon as it appears.
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColours.danger,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            BigButton(
              label: _busy
                  ? 'Please wait…'
                  : (_registering ? 'Create account' : 'Sign in'),
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _registering = !_registering;
                          _error = null;
                        }),
                child: Text(
                  _registering
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    TextInputType type, {
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      ),
    );
  }
}
