import 'package:cloud_firestore/cloud_firestore.dart';

class AuditModel {
  final String id;
  final int? auditNumber;
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final dynamic score;
  final DocumentReference auditorRef;
  final DocumentReference clientRef;
  final DocumentReference templateRef;

  const AuditModel({
    required this.id,
    required this.auditNumber,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.score,
    required this.auditorRef,
    required this.clientRef,
    required this.templateRef,
  });

  String get formattedCode {
    if (auditNumber == null) return 'ART-\u2014';
    return 'ART-${auditNumber!.toString().padLeft(4, '0')}';
  }

  factory AuditModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AuditModel(
      id: doc.id,
      auditNumber: data['auditnumber'] as int?,
      status: data['status'],
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      score: data['score'],
      auditorRef: data['auditorRef'],
      clientRef: data['clientRef'],
      templateRef: data['templateRef'],
    );
  }
}
