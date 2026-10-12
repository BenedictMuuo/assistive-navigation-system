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

  Future<void> signOut() => _auth.signOut();

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
