import 'package:cloud_firestore/cloud_firestore.dart';

class ClientScoreHistoryEntry {
  const ClientScoreHistoryEntry({
    required this.auditId,
    required this.scoreFinal,
    required this.status,
    required this.scoredAt,
    required this.scoreVersion,
  });

  final String auditId;
  final double scoreFinal;
  final String status;
  final DateTime? scoredAt;
  final int? scoreVersion;

  factory ClientScoreHistoryEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final scoreValue = data['scoreFinal'];
    final scoreFinal = scoreValue is num ? scoreValue.toDouble() : 0.0;
    return ClientScoreHistoryEntry(
      auditId: (data['auditId'] as String?)?.trim().isNotEmpty == true
          ? (data['auditId'] as String).trim()
          : doc.id,
      scoreFinal: scoreFinal,
      status: (data['status'] as String?) ?? 'unknown',
      scoredAt: (data['scoredAt'] as Timestamp?)?.toDate(),
      scoreVersion: (data['scoreVersion'] as num?)?.toInt(),
    );
  }
}

class ClientScoreHistoryService {
  ClientScoreHistoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<ClientScoreHistoryEntry>> watchByClient(String clientId) {
    return _firestore
        .collection('clients')
        .doc(clientId)
        .collection('score_history')
        .orderBy('scoredAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ClientScoreHistoryEntry.fromDoc(doc))
              .toList(growable: false),
        );
  }
}
