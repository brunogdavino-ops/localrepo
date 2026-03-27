import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/monthly_plan_item.dart';

class MonthlyPlanningService {
  MonthlyPlanningService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<DocumentReference> loadCurrentUserCompanyRef() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
    final userData = userSnapshot.data();
    final companyRef = userData?['companyref'] as DocumentReference?;
    if (companyRef == null) {
      throw StateError('Empresa do usuário não encontrada.');
    }
    return companyRef;
  }

  Future<PlanningMonthData> loadMonth(DateTime monthDate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
    final userData = userSnapshot.data();
    final companyRef = userData?['companyref'] as DocumentReference?;
    if (companyRef == null) {
      throw StateError('Empresa do usuário não encontrada.');
    }

    final clientsSnapshot = await _firestore
        .collection('clients')
        .where('companyref', isEqualTo: companyRef)
        .get();
    final usersSnapshot = await _firestore.collection('users').get();

    final auditors = usersSnapshot.docs
        .map(
          (doc) => PlanningAuditorOption(
            ref: doc.reference,
            label: _auditorLabelFromData(doc.data(), 'Usuário ${doc.id}'),
          ),
        )
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final latestAuditDatesByClientId = <String, DateTime?>{};
    for (final doc in clientsSnapshot.docs) {
      latestAuditDatesByClientId[doc.id] = await _loadLatestAuditDate(
        doc.reference,
      );
    }

    final clients = clientsSnapshot.docs
        .map((doc) {
          final data = doc.data();
          final auditorRef = data['auditorRef'] as DocumentReference?;
          final importedLastAuditDate = (data['lastAuditDate'] as Timestamp?)?.toDate();
          return PlanningClientOption(
            id: doc.id,
            ref: doc.reference,
            name: ((data['name'] as String?) ?? 'Cliente sem nome').trim(),
            auditorRef: auditorRef,
            auditorName: _resolveAuditorName(auditorRef, auditors),
            auditRecurrence: (data['auditrecurrence'] as String?)?.trim(),
            lastAuditDate: latestAuditDatesByClientId[doc.id] ?? importedLastAuditDate,
          );
        })
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final clientsById = <String, PlanningClientOption>{
      for (final client in clients) client.id: client,
    };

    final monthKey = formatMonthKey(monthDate);
    final savedItemsSnapshot = await _firestore
        .collection('monthly_plans')
        .doc(monthKey)
        .collection('items')
        .where('companyRef', isEqualTo: companyRef)
        .get();

    final savedItemsById = <String, MonthlyPlanItem>{
      for (final doc in savedItemsSnapshot.docs) doc.id: MonthlyPlanItem.fromDocument(doc),
    };

    final autoItemsById = <String, MonthlyPlanItem>{};
    for (final client in clients) {
      final lastAuditDate = client.lastAuditDate;
      final recurrence = client.auditRecurrence;
      if (lastAuditDate == null || recurrence == null || recurrence.isEmpty) {
        continue;
      }

      final nextDate = _nextOccurrenceDate(lastAuditDate, recurrence);
      if (!_isSameMonth(nextDate, monthDate)) {
        continue;
      }

      autoItemsById[client.id] = MonthlyPlanItem(
        id: client.id,
        clientRef: client.ref,
        clientName: client.name,
        auditorRef: client.auditorRef,
        auditorName: client.auditorName,
        auditRecurrence: recurrence,
        lastAuditDate: lastAuditDate,
        monthKey: monthKey,
        included: true,
        isExtra: false,
        source: 'auto',
        companyRef: companyRef,
        status: 'planned',
        sentAt: null,
        cancelledAt: null,
        agendaStatus: 'pending',
        proposedDate: null,
        confirmedDate: null,
        rejectedDates: const [],
        unavailableAt: null,
        previousAuditorRef: null,
        previousAuditorName: null,
      );
    }

    final combined = <String, MonthlyPlanItem>{...autoItemsById};
    for (final entry in savedItemsById.entries) {
      final saved = entry.value;
      final auto = combined[entry.key];
      if (auto != null) {
        combined[entry.key] = auto.copyWith(
          auditorRef: saved.auditorRef,
          auditorName: saved.auditorName,
          included: saved.included,
          isExtra: saved.isExtra,
          source: saved.source,
          status: saved.status,
          sentAt: saved.sentAt,
          cancelledAt: saved.cancelledAt,
          agendaStatus: saved.agendaStatus,
          proposedDate: saved.proposedDate,
          confirmedDate: saved.confirmedDate,
          rejectedDates: saved.rejectedDates,
          unavailableAt: saved.unavailableAt,
          previousAuditorRef: saved.previousAuditorRef,
          previousAuditorName: saved.previousAuditorName,
        );
        continue;
      }

      if (saved.source != 'manual') {
        continue;
      }

      final client = clientsById[entry.key];
      combined[entry.key] = saved.copyWith(
        clientRef: client?.ref,
        clientName: client?.name ?? saved.clientName,
        auditRecurrence: client?.auditRecurrence ?? saved.auditRecurrence,
        lastAuditDate: client?.lastAuditDate ?? saved.lastAuditDate,
      );
    }

    final items = combined.values.toList()
      ..sort((a, b) {
        final statusDiff = _statusPriority(a.status).compareTo(
          _statusPriority(b.status),
        );
        if (statusDiff != 0) {
          return statusDiff;
        }
        return a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase());
      });

    return PlanningMonthData(
      monthKey: monthKey,
      companyRef: companyRef,
      items: items,
      clients: clients,
      auditors: auditors,
    );
  }

  Future<void> saveItem({
    required String monthKey,
    required MonthlyPlanItem item,
    required String uid,
  }) async {
    final monthRef = _firestore.collection('monthly_plans').doc(monthKey);
    await monthRef.set({
      'monthKey': monthKey,
      'updated_at': FieldValue.serverTimestamp(),
      'updatedBy': _firestore.collection('users').doc(uid),
    }, SetOptions(merge: true));
    await monthRef.collection('items').doc(item.id).set(
          item.toFirestore(),
          SetOptions(merge: true),
        );
  }

  Future<void> saveItems({
    required String monthKey,
    required List<MonthlyPlanItem> items,
    required String uid,
  }) async {
    final monthRef = _firestore.collection('monthly_plans').doc(monthKey);
    await monthRef.set({
      'monthKey': monthKey,
      'updated_at': FieldValue.serverTimestamp(),
      'updatedBy': _firestore.collection('users').doc(uid),
    }, SetOptions(merge: true));

    final batch = _firestore.batch();
    for (final item in items) {
      batch.set(
        monthRef.collection('items').doc(item.id),
        item.toFirestore(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<AuditorAgendaMonthData> loadAuditorAgendaMonth(DateTime monthDate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final monthKey = formatMonthKey(monthDate);
    final auditorRef = _firestore.collection('users').doc(user.uid);
    final snapshot = await _firestore
        .collection('monthly_plans')
        .doc(monthKey)
        .collection('items')
        .where('status', isEqualTo: 'sent')
        .where('auditorRef', isEqualTo: auditorRef)
        .get();

    final items = <AuditorAgendaItem>[];
    for (final doc in snapshot.docs) {
      final item = MonthlyPlanItem.fromDocument(doc);
      if (item.isUnavailableAgenda) {
        continue;
      }
      final clientSnapshot = await item.clientRef.get();
      final clientData = clientSnapshot.data() as Map<String, dynamic>?;
      final address = ((clientData?['address'] as String?) ?? '').trim();
      items.add(
        AuditorAgendaItem(
          item: item,
          clientAddress: address.isEmpty ? 'Endereço não informado' : address,
          clientContactName: _primaryContactName(clientData),
          clientContactEmail: _primaryContactEmail(clientData),
        ),
      );
    }

    items.sort((a, b) {
      final groupDiff = _agendaGroupPriority(a.item).compareTo(
        _agendaGroupPriority(b.item),
      );
      if (groupDiff != 0) return groupDiff;

      final dateA = a.item.confirmedDate ?? a.item.proposedDate;
      final dateB = b.item.confirmedDate ?? b.item.proposedDate;
      if (dateA != null && dateB != null) {
        final dateDiff = dateA.compareTo(dateB);
        if (dateDiff != 0) return dateDiff;
      } else if (dateA != null) {
        return -1;
      } else if (dateB != null) {
        return 1;
      }

      return a.item.clientName.toLowerCase().compareTo(
            b.item.clientName.toLowerCase(),
          );
    });

    return AuditorAgendaMonthData(monthKey: monthKey, items: items);
  }

  Future<void> saveAgendaItem({
    required String monthKey,
    required MonthlyPlanItem item,
    required String uid,
  }) async {
    final monthRef = _firestore.collection('monthly_plans').doc(monthKey);
    await monthRef.set({
      'monthKey': monthKey,
      'updated_at': FieldValue.serverTimestamp(),
      'updatedBy': _firestore.collection('users').doc(uid),
    }, SetOptions(merge: true));
    await monthRef.collection('items').doc(item.id).set(
          item.toFirestore(),
          SetOptions(merge: true),
        );
  }

  Future<PlanningManagementMonthData> loadManagementMonth(DateTime monthDate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
    final userData = userSnapshot.data();
    final companyRef = userData?['companyref'] as DocumentReference?;
    if (companyRef == null) {
      throw StateError('Empresa do usuário não encontrada.');
    }

    final monthKey = formatMonthKey(monthDate);
    final itemsSnapshot = await _firestore
        .collection('monthly_plans')
        .doc(monthKey)
        .collection('items')
        .where('companyRef', isEqualTo: companyRef)
        .where('status', whereIn: const ['planned', 'sent'])
        .get();
    final usersSnapshot = await _firestore.collection('users').get();

    final auditors = usersSnapshot.docs
        .map(
          (doc) => PlanningAuditorOption(
            ref: doc.reference,
            label: _auditorLabelFromData(doc.data(), 'Usuário ${doc.id}'),
          ),
        )
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final items = <PlanningManagementItem>[];
    for (final doc in itemsSnapshot.docs) {
      final item = MonthlyPlanItem.fromDocument(doc);
      final clientSnapshot = await item.clientRef.get();
      final clientData = clientSnapshot.data() as Map<String, dynamic>?;
      final address = ((clientData?['address'] as String?) ?? '').trim();
      items.add(
        PlanningManagementItem(
          item: item.copyWith(
            auditorName: _resolveAuditorName(item.auditorRef, auditors) ?? item.auditorName,
            previousAuditorName:
                _resolveAuditorName(item.previousAuditorRef, auditors) ??
                item.previousAuditorName,
          ),
          clientAddress: address.isEmpty ? 'Endereço não informado' : address,
          primaryContact: _primaryContact(clientData),
        ),
      );
    }

    items.sort((a, b) {
      final agendaDiff = _managementPriority(a.item).compareTo(
        _managementPriority(b.item),
      );
      if (agendaDiff != 0) return agendaDiff;
      return a.item.clientName.toLowerCase().compareTo(
            b.item.clientName.toLowerCase(),
          );
    });

    return PlanningManagementMonthData(
      monthKey: monthKey,
      items: items,
      auditors: auditors,
    );
  }

  Future<ConfirmedAgendaData> loadConfirmedAgenda({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
    final userData = userSnapshot.data();
    final companyRef = userData?['companyref'] as DocumentReference?;
    if (companyRef == null) {
      throw StateError('Empresa do usuário não encontrada.');
    }

    final usersSnapshot = await _firestore.collection('users').get();
    final auditors = usersSnapshot.docs
        .map(
          (doc) => PlanningAuditorOption(
            ref: doc.reference,
            label: _auditorLabelFromData(doc.data(), 'Usuário ${doc.id}'),
          ),
        )
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final monthKeys = <String>{
      for (DateTime cursor = DateTime(startDate.year, startDate.month);
          !cursor.isAfter(DateTime(endDate.year, endDate.month));
          cursor = DateTime(cursor.year, cursor.month + 1))
        formatMonthKey(cursor),
    };

    final entries = <ConfirmedAgendaEntry>[];
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    for (final monthKey in monthKeys) {
      final snapshot = await _firestore
          .collection('monthly_plans')
          .doc(monthKey)
          .collection('items')
          .where('companyRef', isEqualTo: companyRef)
          .where('agendaStatus', isEqualTo: 'confirmed')
          .get();

      for (final doc in snapshot.docs) {
        final item = MonthlyPlanItem.fromDocument(doc);
        if (item.isCancelled || item.confirmedDate == null) {
          continue;
        }
        final confirmedDate = item.confirmedDate!;
        if (confirmedDate.isBefore(normalizedStart) || confirmedDate.isAfter(normalizedEnd)) {
          continue;
        }

        final clientSnapshot = await item.clientRef.get();
        final clientData = clientSnapshot.data() as Map<String, dynamic>?;
        final address = ((clientData?['address'] as String?) ?? '').trim();
        entries.add(
          ConfirmedAgendaEntry(
            item: item.copyWith(
              auditorName: _resolveAuditorName(item.auditorRef, auditors) ?? item.auditorName,
            ),
            clientAddress: address.isEmpty ? 'Endereço não informado' : address,
          ),
        );
      }
    }

    entries.sort((a, b) {
      final dateDiff = a.item.confirmedDate!.compareTo(b.item.confirmedDate!);
      if (dateDiff != 0) return dateDiff;
      final auditorA = (a.item.auditorName ?? '').toLowerCase();
      final auditorB = (b.item.auditorName ?? '').toLowerCase();
      final auditorDiff = auditorA.compareTo(auditorB);
      if (auditorDiff != 0) return auditorDiff;
      return a.item.clientName.toLowerCase().compareTo(b.item.clientName.toLowerCase());
    });

    return ConfirmedAgendaData(items: entries, auditors: auditors);
  }

  Future<List<ConfirmedAgendaEntry>> loadAuditorConfirmedAgendaWeek({
    required DateTime startDate,
    required DateTime endDate,
    DocumentReference? companyRef,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final auditorRef = _firestore.collection('users').doc(user.uid);
    final monthKeys = <String>{
      for (DateTime cursor = DateTime(startDate.year, startDate.month);
          !cursor.isAfter(DateTime(endDate.year, endDate.month));
          cursor = DateTime(cursor.year, cursor.month + 1))
        formatMonthKey(cursor),
    };

    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    final entries = <ConfirmedAgendaEntry>[];

    for (final monthKey in monthKeys) {
      Query<Map<String, dynamic>> query = _firestore
          .collection('monthly_plans')
          .doc(monthKey)
          .collection('items')
          .where('status', isEqualTo: 'sent')
          .where('agendaStatus', isEqualTo: 'confirmed')
          .where('auditorRef', isEqualTo: auditorRef);
      if (companyRef != null) {
        query = query.where('companyRef', isEqualTo: companyRef);
      }
      final snapshot = await query.get();

      for (final doc in snapshot.docs) {
        final item = MonthlyPlanItem.fromDocument(doc);
        if (item.isCancelled || item.confirmedDate == null) {
          continue;
        }

        final confirmedDate = item.confirmedDate!;
        if (confirmedDate.isBefore(normalizedStart) ||
            confirmedDate.isAfter(normalizedEnd)) {
          continue;
        }

        final clientSnapshot = await item.clientRef.get();
        final clientData = clientSnapshot.data() as Map<String, dynamic>?;
        final address = ((clientData?['address'] as String?) ?? '').trim();
        entries.add(
          ConfirmedAgendaEntry(
            item: item,
            clientAddress: address.isEmpty ? 'Endereço não informado' : address,
          ),
        );
      }
    }

    entries.sort((a, b) {
      final dateDiff = a.item.confirmedDate!.compareTo(b.item.confirmedDate!);
      if (dateDiff != 0) return dateDiff;
      return a.item.clientName.toLowerCase().compareTo(
            b.item.clientName.toLowerCase(),
          );
    });

    return entries;
  }

  Future<int> countOverdueConfirmedOccurrences({
    required DateTime referenceDate,
    DocumentReference? companyRef,
    int overdueLagDays = 3,
  }) async {
    final entries = await loadOverdueConfirmedAgendaEntries(
      referenceDate: referenceDate,
      companyRef: companyRef,
      overdueLagDays: overdueLagDays,
    );
    return entries.length;
  }

  Future<List<ConfirmedAgendaEntry>> loadOverdueConfirmedAgendaEntries({
    required DateTime referenceDate,
    DocumentReference? companyRef,
    DocumentReference? auditorRef,
    int overdueLagDays = 3,
  }) async {
    final threshold = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    ).subtract(Duration(days: overdueLagDays));
    final auditDatesCache = <String, List<DateTime>>{};
    final entries = <ConfirmedAgendaEntry>[];

    if (auditorRef != null) {
      final monthKeys = <String>{
        formatMonthKey(DateTime(referenceDate.year, referenceDate.month)),
        formatMonthKey(DateTime(referenceDate.year, referenceDate.month - 1)),
      };

      for (final monthKey in monthKeys) {
        Query<Map<String, dynamic>> monthQuery = _firestore
            .collection('monthly_plans')
            .doc(monthKey)
            .collection('items')
            .where('status', isEqualTo: 'sent')
            .where('agendaStatus', isEqualTo: 'confirmed')
            .where('auditorRef', isEqualTo: auditorRef);
        if (companyRef != null) {
          monthQuery = monthQuery.where('companyRef', isEqualTo: companyRef);
        }

        QuerySnapshot<Map<String, dynamic>> monthSnapshot;
        try {
          monthSnapshot = await monthQuery.get();
        } catch (error) {
          throw StateError(
            'Falha ao consultar items confirmados em atraso no mês $monthKey: $error',
          );
        }

        for (final itemDoc in monthSnapshot.docs) {
          final item = MonthlyPlanItem.fromDocument(itemDoc);
          final confirmedDate = item.confirmedDate;
          if (item.isCancelled || confirmedDate == null) {
            continue;
          }
          if (!confirmedDate.isBefore(threshold)) {
            continue;
          }

          final clientPath = item.clientRef.path;
          if (!auditDatesCache.containsKey(clientPath)) {
            try {
              auditDatesCache[clientPath] = await _loadAuditStartedDates(
                item.clientRef,
                auditorRef: auditorRef,
              );
            } catch (error) {
              throw StateError(
                'Falha ao consultar audits iniciadas para ${item.clientName} (${item.clientRef.path}): $error',
              );
            }
          }
          final startedDates = auditDatesCache[clientPath]!;

          final hasAuditAfterConfirmation = startedDates.any(
            (startedAt) => !startedAt.isBefore(confirmedDate),
          );
          if (!hasAuditAfterConfirmation) {
            DocumentSnapshot<Object?> clientSnapshot;
            try {
              clientSnapshot = await item.clientRef.get();
            } catch (error) {
              throw StateError(
                'Falha ao ler clientRef para ${item.clientName} (${item.clientRef.path}): $error',
              );
            }
            final clientData = clientSnapshot.data() as Map<String, dynamic>?;
            final address = ((clientData?['address'] as String?) ?? '').trim();
            entries.add(
              ConfirmedAgendaEntry(
                item: item,
                clientAddress: address.isEmpty ? 'Endereço não informado' : address,
              ),
            );
          }
        }
      }
    } else {
      Query<Map<String, dynamic>> itemsQuery = _firestore
          .collectionGroup('items')
          .where('agendaStatus', isEqualTo: 'confirmed');
      if (companyRef != null) {
        itemsQuery = itemsQuery.where('companyRef', isEqualTo: companyRef);
      }
      QuerySnapshot<Map<String, dynamic>> itemsSnapshot;
      try {
        itemsSnapshot = await itemsQuery.get();
      } catch (error) {
        throw StateError('Falha ao consultar items confirmados em atraso: $error');
      }

      for (final itemDoc in itemsSnapshot.docs) {
        final item = MonthlyPlanItem.fromDocument(itemDoc);
        final confirmedDate = item.confirmedDate;
        if (item.isCancelled || confirmedDate == null) {
          continue;
        }
        if (!confirmedDate.isBefore(threshold)) {
          continue;
        }

        final clientPath = item.clientRef.path;
        if (!auditDatesCache.containsKey(clientPath)) {
          try {
            auditDatesCache[clientPath] = await _loadAuditStartedDates(
              item.clientRef,
            );
          } catch (error) {
            throw StateError(
              'Falha ao consultar audits iniciadas para ${item.clientName} (${item.clientRef.path}): $error',
            );
          }
        }
        final startedDates = auditDatesCache[clientPath]!;

        final hasAuditAfterConfirmation = startedDates.any(
          (startedAt) => !startedAt.isBefore(confirmedDate),
        );
        if (!hasAuditAfterConfirmation) {
          DocumentSnapshot<Object?> clientSnapshot;
          try {
            clientSnapshot = await item.clientRef.get();
          } catch (error) {
            throw StateError(
              'Falha ao ler clientRef para ${item.clientName} (${item.clientRef.path}): $error',
            );
          }
          final clientData = clientSnapshot.data() as Map<String, dynamic>?;
          final address = ((clientData?['address'] as String?) ?? '').trim();
          entries.add(
            ConfirmedAgendaEntry(
              item: item,
              clientAddress: address.isEmpty ? 'Endereço não informado' : address,
            ),
          );
        }
      }
    }

    entries.sort((a, b) {
      final dateA = a.item.confirmedDate ?? DateTime(1900);
      final dateB = b.item.confirmedDate ?? DateTime(1900);
      final dateDiff = dateA.compareTo(dateB);
      if (dateDiff != 0) return dateDiff;
      return a.item.clientName.toLowerCase().compareTo(
            b.item.clientName.toLowerCase(),
          );
    });

    return entries;
  }

  Future<List<DateTime>> _loadAuditStartedDates(
    DocumentReference clientRef, {
    DocumentReference? auditorRef,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('audits')
        .where('clientRef', isEqualTo: clientRef);
    if (auditorRef != null) {
      query = query.where('auditorRef', isEqualTo: auditorRef);
    }
    final snapshot = await query.get();

    final dates = <DateTime>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
      if (startedAt != null) {
        dates.add(startedAt);
      }
    }
    dates.sort();
    return dates;
  }

  Future<DateTime?> _loadLatestAuditDate(DocumentReference clientRef) async {
    final snapshot = await _firestore
        .collection('audits')
        .where('clientRef', isEqualTo: clientRef)
        .get();

    DateTime? latest;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = (data['status'] as String?)?.trim().toLowerCase();
      if (status != 'completed') {
        continue;
      }
      final date = (data['startedAt'] as Timestamp?)?.toDate();
      if (date == null) continue;
      if (latest == null || date.isAfter(latest)) {
        latest = date;
      }
    }
    return latest;
  }

  String _auditorLabelFromData(Map<String, dynamic>? data, String fallback) {
    final candidates = [data?['name'], data?['displayName'], data?['email']];
    for (final candidate in candidates) {
      final value = (candidate as String?)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  PlanningClientContact? _primaryContact(Map<String, dynamic>? clientData) {
    final responsibles = (clientData?['responsibles'] as List<dynamic>?) ?? const [];
    for (final item in responsibles) {
      if (item is! Map) continue;
      final name = ((item['name'] as String?) ?? '').trim();
      final email = ((item['email'] as String?) ?? '').trim();
      if (name.isEmpty && email.isEmpty) continue;
      return PlanningClientContact(name: name, email: email);
    }
    return null;
  }

  String _primaryContactName(Map<String, dynamic>? clientData) {
    final contact = _primaryContact(clientData);
    if (contact == null || contact.name.isEmpty) {
      return 'Responsável não informado';
    }
    return contact.name;
  }

  String _primaryContactEmail(Map<String, dynamic>? clientData) {
    final contact = _primaryContact(clientData);
    if (contact == null || contact.email.isEmpty) {
      return 'E-mail não informado';
    }
    return contact.email;
  }

  String? _resolveAuditorName(
    DocumentReference? auditorRef,
    List<PlanningAuditorOption> auditors,
  ) {
    if (auditorRef == null) return null;
    for (final auditor in auditors) {
      if (auditor.ref.path == auditorRef.path) {
        return auditor.label;
      }
    }
    return null;
  }

  DateTime _nextOccurrenceDate(DateTime lastAuditDate, String recurrence) {
    switch (recurrence) {
      case 'Quinzenal':
        return lastAuditDate.add(const Duration(days: 15));
      case 'Mensal':
        return _addMonths(lastAuditDate, 1);
      case 'Bimensal':
        return _addMonths(lastAuditDate, 2);
      case 'Trimestral':
        return _addMonths(lastAuditDate, 3);
      default:
        return lastAuditDate;
    }
  }

  DateTime _addMonths(DateTime date, int months) {
    final targetMonth = date.month + months;
    final year = date.year + ((targetMonth - 1) ~/ 12);
    final month = ((targetMonth - 1) % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  int _statusPriority(String status) {
    switch (status) {
      case 'planned':
        return 0;
      case 'sent':
        return 1;
      case 'cancelled':
        return 2;
      default:
        return 0;
    }
  }

  int _agendaGroupPriority(MonthlyPlanItem item) {
    if (item.isConfirmedAgenda) return 1;
    return 0;
  }

  int _managementPriority(MonthlyPlanItem item) {
    if (item.isPendingConfirmation) return 0;
    if (item.isUnavailableAgenda) return 1;
    if (item.isPendingAgenda || item.isAdminRejectedAgenda) return 2;
    if (item.isConfirmedAgenda) return 3;
    return 4;
  }
}

String formatMonthKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}
