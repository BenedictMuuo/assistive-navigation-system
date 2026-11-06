import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

/// Sign-in, registration and profile storage.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> get authChanges => _auth.authStateChanges();

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) =>
      _db.collection('users').doc(uid);

  /// Live profile for [uid]. Emits null until the document exists, which
  /// happens for a moment straight after registration.
  Stream<UserProfile?> profile(String uid) {
    return _profileRef(uid).snapshots().map((snap) {
      final data = snap.data();
      return data == null ? null : UserProfile.fromMap(uid, data);
    });
  }

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: normaliseEmail(email),
      password: password,
    );
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: normaliseEmail(email),
      password: password,
    );
    final uid = cred.user!.uid;
    final profile = UserProfile(
      uid: uid,
      name: name.trim(),
      email: normaliseEmail(email),
      role: role,
    );
    await _profileRef(uid).set({
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setCaregiverEmail(String uid, String email) async {
    await _profileRef(uid).update({'caregiverEmail': normaliseEmail(email)});
  }

  /// Signs out, but never while something is still waiting to be sent.
  ///
  /// An SOS sent with no internet waits on the phone and is uploaded when
  /// the connection returns, under the account that is signed in at that
  /// moment. If the user signed out first, the upload would run as the next
  /// account, the security rules would reject it, and the alert would be
  /// lost. So this first waits up to [wait] for everything to be sent.
  ///
  /// Returns true if signed out. Returns false, and stays signed in, if
  /// something is still waiting, which means the phone is offline.
  Future<bool> signOut({Duration wait = const Duration(seconds: 5)}) async {
    try {
      await _db.waitForPendingWrites().timeout(wait);
    } on TimeoutException {
      return false;
    }
    await _auth.signOut();
    return true;
  }

  /// Shown when [signOut] refuses.
  static const String unsentWarning =
      'An SOS or another change is still waiting to be sent. '
      'Stay signed in until the phone is back online, then try again.';

  /// The same message for text-to-speech, which reads "SOS" as a word.
  static const String unsentWarningSpoken =
      'An S O S or another change is still waiting to be sent. '
      'Stay signed in until the phone is back online, then try again.';

  /// Turns Firebase's error codes into something a person can act on.
  static String explain(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'That email address is not valid.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Email or password is incorrect.';
        case 'email-already-in-use':
          return 'An account with that email already exists. Sign in instead.';
        case 'weak-password':
          return 'Password is too weak. Use at least 6 characters.';
        case 'network-request-failed':
          return 'No internet connection. Check your network and try again.';
        case 'too-many-requests':
          return 'Too many attempts. Wait a minute and try again.';
      }
      return error.message ?? 'Sign-in failed (${error.code}).';
    }
    return 'Something went wrong: $error';
  }
}
