import 'package:cloud_firestore/cloud_firestore.dart';

class AuditModel {
  final String id;
  final int? auditNumber;
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final dynamic score;
  final double? scoreFinal;
  final Map<String, double> scoreByCategory;
  final DateTime? scoredAt;
  final int? scoreVersion;
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
    required this.scoreFinal,
    required this.scoreByCategory,
    required this.scoredAt,
    required this.scoreVersion,
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
    return AuditModel.fromData(
      id: doc.id,
      data: data,
      auditorRef: data['auditorRef'] as DocumentReference,
      clientRef: data['clientRef'] as DocumentReference,
      templateRef: data['templateRef'] as DocumentReference,
    );
  }

  factory AuditModel.fromData({
    required String id,
    required Map<String, dynamic> data,
    required DocumentReference auditorRef,
    required DocumentReference clientRef,
    required DocumentReference templateRef,
  }) {
    final rawScoreByCategory = data['scoreByCategory'];
    final scoreByCategory = <String, double>{};
    if (rawScoreByCategory is Map) {
      rawScoreByCategory.forEach((key, value) {
        final parsed = _toDouble(value);
        if (key is String && parsed != null) {
          scoreByCategory[key] = parsed;
        }
      });
    }

    final scoreFinal =
        _toDouble(data['scoreFinal']) ?? _toDouble(data['score']);

    return AuditModel(
      id: id,
      auditNumber: data['auditnumber'] as int?,
      status: data['status'],
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      score: data['score'],
      scoreFinal: scoreFinal,
      scoreByCategory: scoreByCategory,
      scoredAt: (data['scoredAt'] as Timestamp?)?.toDate(),
      scoreVersion: (data['scoreVersion'] as num?)?.toInt(),
      auditorRef: auditorRef,
      clientRef: clientRef,
      templateRef: templateRef,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }
}
