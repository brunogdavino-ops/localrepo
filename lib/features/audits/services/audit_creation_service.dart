import 'package:cloud_firestore/cloud_firestore.dart';

class AuditCreationService {
  static const String _templateId = '5MtglwaR0YtQYthfTGE8';

  final FirebaseFirestore _firestore;

  AuditCreationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<String> createAudit({
    required String uid,
    required DocumentReference clientRef,
    required DateTime chosenDate,
    required bool draft,
  }) async {
    final countersRef = _firestore.collection('counters').doc('audits');
    final auditsRef = _firestore.collection('audits');
    final auditDocRef = auditsRef.doc();
    final auditorRef = _firestore.collection('users').doc(uid);
    final templateRef = _firestore.collection('templates').doc(_templateId);
    final startDate = DateTime(chosenDate.year, chosenDate.month, chosenDate.day);

    await _firestore.runTransaction((transaction) async {
      final counterSnapshot = await transaction.get(countersRef);
      final counterData = counterSnapshot.data();
      final currentNumber = (counterData?['currentNumber'] as num?)?.toInt() ?? 0;
      final nextNumber = currentNumber + 1;

      transaction.set(
        countersRef,
        {'currentNumber': nextNumber},
        SetOptions(merge: true),
      );

      transaction.set(auditDocRef, {
        'auditnumber': nextNumber,
        'auditorRef': auditorRef,
        'clientRef': clientRef,
        'templateRef': templateRef,
        'status': draft ? 'draft' : 'in_progress',
        'startedAt': Timestamp.fromDate(startDate),
        'completedAt': null,
        'score': null,
        'submittedAt': null,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });

    final questionsSnapshot = await _firestore
        .collection('questions')
        .where('templateRef', isEqualTo: templateRef)
        .get();

    const int maxBatchWrites = 450;
    WriteBatch batch = _firestore.batch();
    int writeCount = 0;

    for (final questionDoc in questionsSnapshot.docs) {
      final questionData = questionDoc.data();
      final answerRef = auditDocRef.collection('answers').doc();
      final questionWeight = (questionData['weight'] as num?)?.toDouble() ?? 1;

      batch.set(answerRef, {
        'created_at': FieldValue.serverTimestamp(),
        'notes': '',
        'photoUrl': '',
        'questionRef': questionDoc.reference,
        'value': null,
        'weight': questionWeight,
      });

      writeCount++;
      if (writeCount >= maxBatchWrites) {
        await batch.commit();
        batch = _firestore.batch();
        writeCount = 0;
      }
    }

    if (writeCount > 0) {
      await batch.commit();
    }

    return auditDocRef.id;
  }
}
