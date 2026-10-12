/// The two kinds of account in the system.
enum UserRole {
  /// A visually impaired person using the navigation features.
  user,

  /// Someone who receives SOS alerts from a user.
  caregiver,
}

/// Emails are compared in lower case everywhere, so "Mary@Gmail.com" and
/// "mary@gmail.com" are the same caregiver. Firebase Auth stores addresses
/// in lower case, and the security rules compare against that.
String normaliseEmail(String email) => email.trim().toLowerCase();

/// A stored profile, kept at users/{uid} in Firestore.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.caregiverEmail,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;

  /// Only used by [UserRole.user]: who receives this person's SOS alerts.
  final String? caregiverEmail;

  bool get isCaregiver => role == UserRole.caregiver;

  bool get hasCaregiver =>
      caregiverEmail != null && caregiverEmail!.trim().isNotEmpty;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    return UserProfile(
      uid: uid,
      name: (map['name'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      role: map['role'] == 'caregiver' ? UserRole.caregiver : UserRole.user,
      caregiverEmail: map['caregiverEmail'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': normaliseEmail(email),
      'role': role.name,
      if (role == UserRole.user && caregiverEmail != null)
        'caregiverEmail': normaliseEmail(caregiverEmail!),
    };
  }
}
