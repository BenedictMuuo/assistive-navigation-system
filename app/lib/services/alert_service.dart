import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/sos_alert.dart';
import '../models/user_profile.dart';

/// Sends SOS alerts and lets caregivers watch for them.
///
/// There is no push notification server. The caregiver's app keeps a live
/// connection to Firestore and is told the moment an alert is written.
/// That works while the caregiver app is open or in the background. Waking
/// a fully closed app needs Firebase Cloud Functions, which requires the
/// paid Blaze plan - a documented limitation of this prototype.
class AlertService {
  AlertService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _alerts =>
      _db.collection('alerts');

  /// Writes an SOS alert. Returns its id.
  Future<String> sendSos({
    required UserProfile from,
    Position? position,
  }) async {
    if (!from.hasCaregiver) {
      throw StateError('No caregiver email set.');
    }
    final doc = await _alerts.add({
      'type': 'sos',
      'status': 'open',
      'userId': from.uid,
      'userName': from.name,
      'userEmail': normaliseEmail(from.email),
      'caregiverEmail': normaliseEmail(from.caregiverEmail!),
      if (position != null) ...{
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMetres': position.accuracy,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Live list of alerts addressed to [caregiverEmail], newest first.
  ///
  /// Sorted on the phone rather than in the query. Sorting in Firestore
  /// together with the email filter would need a composite index set up in
  /// the console; at a few dozen alerts, sorting locally costs nothing.
  Stream<List<SosAlert>> alertsFor(String caregiverEmail) {
    return _alerts
        .where('caregiverEmail', isEqualTo: normaliseEmail(caregiverEmail))
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(SosAlert.fromDoc).toList();
      list.sort((a, b) {
        // Alerts still waiting for a server timestamp are the newest.
        final at = a.createdAt ?? DateTime(9999);
        final bt = b.createdAt ?? DateTime(9999);
        return bt.compareTo(at);
      });
      return list;
    });
  }

  Future<void> acknowledge(String alertId) {
    return _alerts.doc(alertId).update({
      'status': 'acknowledged',
      'acknowledgedAt': FieldValue.serverTimestamp(),
    });
  }
}
