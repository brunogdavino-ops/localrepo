import 'package:cloud_firestore/cloud_firestore.dart';

import 'active_template_service.dart';

class AuditCreationService {
  final FirebaseFirestore _firestore;
  final ActiveTemplateService _activeTemplateService;

  AuditCreationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _activeTemplateService = ActiveTemplateService(
          firestore: firestore ?? FirebaseFirestore.instance,
        );

  Future<String> createAudit({
    required String uid,
    required DocumentReference clientRef,
    required DateTime chosenDate,
    required bool draft,
  }) async {
    final templateRef = await _activeTemplateService.resolveActiveTemplateRef();
    final countersRef = _firestore.collection('counters').doc('audits');
    final auditsRef = _firestore.collection('audits');
    final auditDocRef = auditsRef.doc();
    final auditorRef = _firestore.collection('users').doc(uid);
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

  Future<String> createOrReuseAudit({
    required String uid,
    required DocumentReference clientRef,
    required DateTime chosenDate,
    required bool draft,
  }) async {
    final auditorRef = _firestore.collection('users').doc(uid);
    final startDate = DateTime(chosenDate.year, chosenDate.month, chosenDate.day);
    final existingSnapshot = await _firestore
        .collection('audits')
        .where('auditorRef', isEqualTo: auditorRef)
        .where('clientRef', isEqualTo: clientRef)
        .where('startedAt', isEqualTo: Timestamp.fromDate(startDate))
        .limit(1)
        .get();

    if (existingSnapshot.docs.isNotEmpty) {
      return existingSnapshot.docs.first.id;
    }

    return createAudit(
      uid: uid,
      clientRef: clientRef,
      chosenDate: startDate,
      draft: draft,
    );
  }
}
