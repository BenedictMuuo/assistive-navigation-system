import 'package:cloud_firestore/cloud_firestore.dart';

/// One SOS alert, kept at alerts/{id} in Firestore.
class SosAlert {
  const SosAlert({
    required this.id,
    required this.userId,
    required this.userName,
    required this.caregiverEmail,
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracyMetres,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String caregiverEmail;

  /// "open" until the caregiver marks it handled, then "acknowledged".
  final String status;

  /// Null when the phone could not get a location. The alert is still sent:
  /// an SOS without a location is far better than no SOS at all.
  final double? latitude;
  final double? longitude;
  final double? accuracyMetres;

  /// Null for a moment after sending, until the server stamps it.
  final DateTime? createdAt;

  bool get isOpen => status == 'open';
  bool get hasLocation => latitude != null && longitude != null;

  /// A link that opens the location in Google Maps.
  String? get mapsUrl => hasLocation ? mapsUrlFor(latitude!, longitude!) : null;

  static String mapsUrlFor(double lat, double lng) =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  factory SosAlert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final ts = d['createdAt'];
    return SosAlert(
      id: doc.id,
      userId: (d['userId'] as String?) ?? '',
      userName: (d['userName'] as String?) ?? 'Unknown user',
      caregiverEmail: (d['caregiverEmail'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'open',
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      accuracyMetres: (d['accuracyMetres'] as num?)?.toDouble(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// "just now", "3 min ago", "2 h ago", or a date for older alerts.
String describeAge(DateTime? time, DateTime now) {
  if (time == null) return 'just now';
  final diff = now.difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '${time.day} ${months[time.month - 1]}, $hh:$mm';
}
