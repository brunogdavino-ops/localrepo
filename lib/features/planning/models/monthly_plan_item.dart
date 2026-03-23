import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyPlanItem {
  static const Object _unset = Object();
  final String id;
  final DocumentReference clientRef;
  final String clientName;
  final DocumentReference? auditorRef;
  final String? auditorName;
  final String? auditRecurrence;
  final DateTime? lastAuditDate;
  final String monthKey;
  final bool included;
  final bool isExtra;
  final String source;
  final DocumentReference companyRef;
  final String status;
  final DateTime? sentAt;
  final DateTime? cancelledAt;
  final String agendaStatus;
  final DateTime? proposedDate;
  final DateTime? confirmedDate;
  final List<DateTime> rejectedDates;
  final DateTime? unavailableAt;
  final DocumentReference? previousAuditorRef;
  final String? previousAuditorName;

  const MonthlyPlanItem({
    required this.id,
    required this.clientRef,
    required this.clientName,
    required this.auditorRef,
    required this.auditorName,
    required this.auditRecurrence,
    required this.lastAuditDate,
    required this.monthKey,
    required this.included,
    required this.isExtra,
    required this.source,
    required this.companyRef,
    required this.status,
    required this.sentAt,
    required this.cancelledAt,
    required this.agendaStatus,
    required this.proposedDate,
    required this.confirmedDate,
    required this.rejectedDates,
    required this.unavailableAt,
    required this.previousAuditorRef,
    required this.previousAuditorName,
  });

  factory MonthlyPlanItem.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return MonthlyPlanItem(
      id: doc.id,
      clientRef: data['clientRef'] as DocumentReference,
      clientName: ((data['clientName'] as String?) ?? 'Cliente sem nome').trim(),
      auditorRef: data['auditorRef'] as DocumentReference?,
      auditorName: (data['auditorName'] as String?)?.trim(),
      auditRecurrence: (data['auditrecurrence'] as String?)?.trim(),
      lastAuditDate: (data['lastAuditDate'] as Timestamp?)?.toDate(),
      monthKey: ((data['monthKey'] as String?) ?? '').trim(),
      included: data['included'] == true,
      isExtra: data['isExtra'] == true,
      source: ((data['source'] as String?) ?? 'auto').trim(),
      companyRef: data['companyRef'] as DocumentReference,
      status: ((data['status'] as String?) ?? 'planned').trim(),
      sentAt: (data['sentAt'] as Timestamp?)?.toDate(),
      cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
      agendaStatus: ((data['agendaStatus'] as String?) ?? 'pending').trim(),
      proposedDate: (data['proposedDate'] as Timestamp?)?.toDate(),
      confirmedDate: (data['confirmedDate'] as Timestamp?)?.toDate(),
      rejectedDates: ((data['rejectedDates'] as List<dynamic>?) ?? const [])
          .whereType<Timestamp>()
          .map((timestamp) => timestamp.toDate())
          .toList(growable: false),
      unavailableAt: (data['unavailableAt'] as Timestamp?)?.toDate(),
      previousAuditorRef: data['previousAuditorRef'] as DocumentReference?,
      previousAuditorName: (data['previousAuditorName'] as String?)?.trim(),
    );
  }

  MonthlyPlanItem copyWith({
    DocumentReference? clientRef,
    String? clientName,
    Object? auditorRef = _unset,
    Object? auditorName = _unset,
    String? auditRecurrence,
    Object? lastAuditDate = _unset,
    String? monthKey,
    bool? included,
    bool? isExtra,
    String? source,
    DocumentReference? companyRef,
    String? status,
    Object? sentAt = _unset,
    Object? cancelledAt = _unset,
    String? agendaStatus,
    Object? proposedDate = _unset,
    Object? confirmedDate = _unset,
    List<DateTime>? rejectedDates,
    Object? unavailableAt = _unset,
    Object? previousAuditorRef = _unset,
    Object? previousAuditorName = _unset,
  }) {
    return MonthlyPlanItem(
      id: id,
      clientRef: clientRef ?? this.clientRef,
      clientName: clientName ?? this.clientName,
      auditorRef: auditorRef == _unset
          ? this.auditorRef
          : auditorRef as DocumentReference?,
      auditorName:
          auditorName == _unset ? this.auditorName : auditorName as String?,
      auditRecurrence: auditRecurrence ?? this.auditRecurrence,
      lastAuditDate: lastAuditDate == _unset
          ? this.lastAuditDate
          : lastAuditDate as DateTime?,
      monthKey: monthKey ?? this.monthKey,
      included: included ?? this.included,
      isExtra: isExtra ?? this.isExtra,
      source: source ?? this.source,
      companyRef: companyRef ?? this.companyRef,
      status: status ?? this.status,
      sentAt: sentAt == _unset ? this.sentAt : sentAt as DateTime?,
      cancelledAt: cancelledAt == _unset
          ? this.cancelledAt
          : cancelledAt as DateTime?,
      agendaStatus: agendaStatus ?? this.agendaStatus,
      proposedDate: proposedDate == _unset
          ? this.proposedDate
          : proposedDate as DateTime?,
      confirmedDate: confirmedDate == _unset
          ? this.confirmedDate
          : confirmedDate as DateTime?,
      rejectedDates: rejectedDates ?? this.rejectedDates,
      unavailableAt: unavailableAt == _unset
          ? this.unavailableAt
          : unavailableAt as DateTime?,
      previousAuditorRef: previousAuditorRef == _unset
          ? this.previousAuditorRef
          : previousAuditorRef as DocumentReference?,
      previousAuditorName: previousAuditorName == _unset
          ? this.previousAuditorName
          : previousAuditorName as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientRef': clientRef,
      'clientName': clientName,
      'auditorRef': auditorRef,
      'auditorName': auditorName,
      'auditrecurrence': auditRecurrence,
      'lastAuditDate': lastAuditDate == null ? null : Timestamp.fromDate(lastAuditDate!),
      'monthKey': monthKey,
      'included': included,
      'isExtra': isExtra,
      'source': source,
      'companyRef': companyRef,
      'status': status,
      'sentAt': sentAt == null ? null : Timestamp.fromDate(sentAt!),
      'cancelledAt':
          cancelledAt == null ? null : Timestamp.fromDate(cancelledAt!),
      'agendaStatus': agendaStatus,
      'proposedDate':
          proposedDate == null ? null : Timestamp.fromDate(proposedDate!),
      'confirmedDate':
          confirmedDate == null ? null : Timestamp.fromDate(confirmedDate!),
      'rejectedDates':
          rejectedDates.map((date) => Timestamp.fromDate(date)).toList(),
      'unavailableAt':
          unavailableAt == null ? null : Timestamp.fromDate(unavailableAt!),
      'previousAuditorRef': previousAuditorRef,
      'previousAuditorName': previousAuditorName,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  bool get isSent => status == 'sent';
  bool get isCancelled => status == 'cancelled';
  bool get isPlanned => status == 'planned';
  bool get isPendingAgenda => agendaStatus == 'pending';
  bool get isRejectedAgenda =>
      agendaStatus == 'admin_rejected' || agendaStatus == 'rejected';
  bool get isAdminRejectedAgenda => agendaStatus == 'admin_rejected';
  bool get isPendingConfirmation => agendaStatus == 'pending_confirmation';
  bool get isConfirmedAgenda => agendaStatus == 'confirmed';
  bool get isUnavailableAgenda =>
      agendaStatus == 'auditor_unavailable' || agendaStatus == 'unavailable';
}

class PlanningClientOption {
  final String id;
  final DocumentReference ref;
  final String name;
  final DocumentReference? auditorRef;
  final String? auditorName;
  final String? auditRecurrence;
  final DateTime? lastAuditDate;

  const PlanningClientOption({
    required this.id,
    required this.ref,
    required this.name,
    required this.auditorRef,
    required this.auditorName,
    required this.auditRecurrence,
    required this.lastAuditDate,
  });
}

class PlanningAuditorOption {
  final DocumentReference ref;
  final String label;

  const PlanningAuditorOption({
    required this.ref,
    required this.label,
  });
}

class PlanningMonthData {
  final String monthKey;
  final DocumentReference companyRef;
  final List<MonthlyPlanItem> items;
  final List<PlanningClientOption> clients;
  final List<PlanningAuditorOption> auditors;

  const PlanningMonthData({
    required this.monthKey,
    required this.companyRef,
    required this.items,
    required this.clients,
    required this.auditors,
  });
}

class AuditorAgendaItem {
  final MonthlyPlanItem item;
  final String clientAddress;
  final String clientContactName;
  final String clientContactEmail;

  const AuditorAgendaItem({
    required this.item,
    required this.clientAddress,
    required this.clientContactName,
    required this.clientContactEmail,
  });
}

class AuditorAgendaMonthData {
  final String monthKey;
  final List<AuditorAgendaItem> items;

  const AuditorAgendaMonthData({
    required this.monthKey,
    required this.items,
  });
}

class PlanningClientContact {
  final String name;
  final String email;

  const PlanningClientContact({
    required this.name,
    required this.email,
  });
}

class PlanningManagementItem {
  final MonthlyPlanItem item;
  final String clientAddress;
  final PlanningClientContact? primaryContact;

  const PlanningManagementItem({
    required this.item,
    required this.clientAddress,
    required this.primaryContact,
  });
}

class PlanningManagementMonthData {
  final String monthKey;
  final List<PlanningManagementItem> items;
  final List<PlanningAuditorOption> auditors;

  const PlanningManagementMonthData({
    required this.monthKey,
    required this.items,
    required this.auditors,
  });
}

class ConfirmedAgendaEntry {
  final MonthlyPlanItem item;
  final String clientAddress;

  const ConfirmedAgendaEntry({
    required this.item,
    required this.clientAddress,
  });
}

class ConfirmedAgendaData {
  final List<ConfirmedAgendaEntry> items;
  final List<PlanningAuditorOption> auditors;

  const ConfirmedAgendaData({
    required this.items,
    required this.auditors,
  });
}
