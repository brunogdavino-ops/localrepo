import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/monthly_plan_item.dart';
import 'services/monthly_planning_service.dart';

enum PlanningManagementFocusSection {
  validation,
  unscheduled,
  refused,
  confirmed,
}

class PlanningManagementPage extends StatefulWidget {
  const PlanningManagementPage({
    super.key,
    this.initialFocusSection,
  });

  final PlanningManagementFocusSection? initialFocusSection;

  @override
  State<PlanningManagementPage> createState() => _PlanningManagementPageState();
}

enum _ManagementFilter { total, confirmed, rejected, progress, pending }

class _PlanningManagementPageState extends State<PlanningManagementPage> {
  static const Color _bg = Color(0xFFF7F7FB);
  static const Color _brand = Color(0xFF7357D8);
  static const Color _muted = Color(0xFF72778A);

  final MonthlyPlanningService _service = MonthlyPlanningService();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  PlanningManagementMonthData? _monthData;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String _auditorFilterPath = 'all';
  _ManagementFilter _statusFilter = _ManagementFilter.total;
  PlanningManagementFocusSection? _focusSection;

  @override
  void initState() {
    super.initState();
    _focusSection = widget.initialFocusSection;
    _loadMonth();
  }

  Future<void> _loadMonth({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final data = await _service.loadManagementMonth(_selectedMonth);
      if (!mounted) return;
      setState(() {
        _monthData = data;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error is StateError
            ? error.message.toString()
            : 'Nao foi possivel carregar a gestao das auditorias.';
      });
    }
  }

  List<PlanningManagementItem> _auditorScopedItems(PlanningManagementMonthData data) {
    final items = data.items.where((entry) => !entry.item.isCancelled);
    if (_auditorFilterPath == 'all') {
      return items.toList(growable: false);
    }
    return items
        .where((entry) => entry.item.auditorRef?.path == _auditorFilterPath)
        .toList(growable: false);
  }

  List<PlanningManagementItem> _visibleItems(PlanningManagementMonthData data) {
    return _auditorScopedItems(data)
        .where((entry) => _matchesFocus(entry.item))
        .where((entry) => _matchesFilter(entry.item, _statusFilter))
        .toList(growable: false);
  }

  bool _matchesFocus(MonthlyPlanItem item) {
    switch (_focusSection) {
      case PlanningManagementFocusSection.validation:
        return item.isPendingConfirmation;
      case PlanningManagementFocusSection.unscheduled:
        return !item.isPendingConfirmation &&
            !item.isConfirmedAgenda &&
            !item.isAdminRejectedAgenda &&
            !item.isUnavailableAgenda;
      case PlanningManagementFocusSection.refused:
        return item.isAdminRejectedAgenda || item.isUnavailableAgenda;
      case PlanningManagementFocusSection.confirmed:
        return item.isConfirmedAgenda;
      case null:
        return true;
    }
  }

  int _countFor(_ManagementFilter filter, PlanningManagementMonthData data) {
    return _auditorScopedItems(data)
        .where((entry) => _matchesFilter(entry.item, filter))
        .length;
  }

  bool _matchesFilter(MonthlyPlanItem item, _ManagementFilter filter) {
    switch (filter) {
      case _ManagementFilter.total:
        return true;
      case _ManagementFilter.confirmed:
        return item.isConfirmedAgenda;
      case _ManagementFilter.rejected:
        return item.isUnavailableAgenda;
      case _ManagementFilter.progress:
        return item.isPendingConfirmation;
      case _ManagementFilter.pending:
        return item.isPendingAgenda || item.isAdminRejectedAgenda;
    }
  }

  Future<void> _persist(MonthlyPlanItem updatedItem) async {
    final data = _monthData;
    final user = FirebaseAuth.instance.currentUser;
    if (data == null || user == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _service.saveAgendaItem(
        monthKey: data.monthKey,
        item: updatedItem,
        uid: user.uid,
      );
      await _loadMonth(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel salvar esta alteracao.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
  }

  Future<void> _approve(PlanningManagementItem entry) async {
    final proposed = entry.item.proposedDate;
    if (proposed == null) return;
    await _persist(entry.item.copyWith(
      agendaStatus: 'confirmed',
      confirmedDate: proposed,
    ));
  }

  Future<void> _reject(PlanningManagementItem entry) async {
    final proposed = entry.item.proposedDate;
    if (proposed == null) return;
    await _persist(entry.item.copyWith(
      agendaStatus: 'admin_rejected',
      proposedDate: null,
      confirmedDate: null,
      rejectedDates: [...entry.item.rejectedDates, proposed],
    ));
  }

  Future<void> _swapAuditor(PlanningManagementItem entry) async {
    final data = _monthData;
    if (data == null) return;
    final selected = await showModalBottomSheet<PlanningAuditorOption>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AuditorPickerSheet(
        auditors: data.auditors,
        selectedRef: entry.item.auditorRef,
      ),
    );
    if (selected == null) return;
    final currentPath = entry.item.auditorRef?.path;
    if (selected.ref.path == currentPath) return;
    await _persist(entry.item.copyWith(
      previousAuditorRef: entry.item.auditorRef,
      previousAuditorName: entry.item.auditorName,
      auditorRef: selected.ref,
      auditorName: selected.label,
      proposedDate: null,
      confirmedDate: null,
      sentAt: null,
      status: 'planned',
      agendaStatus: 'unavailable',
    ));
  }

  Future<void> _resend(PlanningManagementItem entry) async {
    await _persist(entry.item.copyWith(
      status: 'sent',
      sentAt: DateTime.now(),
      agendaStatus: 'pending',
      proposedDate: null,
      confirmedDate: null,
      unavailableAt: null,
    ));
  }

  Future<void> _openClientSummary(PlanningManagementItem entry) async {
    final contactName = (entry.primaryContact?.name ?? '').trim();
    final contactEmail = (entry.primaryContact?.email ?? '').trim();
    final message = 'Boa tarde${contactName.isEmpty ? '' : ', $contactName'}!\n\n'
        'A próxima auditoria com ${entry.item.clientName}, no endereço ${entry.clientAddress}, '
        'está prevista para o dia ${entry.item.proposedDate == null ? 'a confirmar' : _formatLongDate(entry.item.proposedDate!)}.\n\n'
        'Podemos seguir com esse agendamento?';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MessageSheet(
        headerLabel: 'RESUMO PARA VALIDAÇÃO',
        clientName: entry.item.clientName,
        sections: [
          _MessageSection(
            label: 'AUDITOR RESPONSÁVEL',
            value: entry.item.auditorName ?? 'Não informada',
          ),
          _MessageSection(
            label: 'ENDEREÇO',
            value: entry.clientAddress,
          ),
          _MessageSection(
            label: 'CONTATO',
            value: contactName.isEmpty ? 'Responsável não informado' : contactName,
            secondaryLabel: 'E-MAIL',
            secondaryValue: contactEmail.isEmpty ? 'E-mail não informado' : contactEmail,
            copyValue: contactEmail,
            copyFeedbackLabel: 'E-mail copiado',
          ),
        ],
        message: message,
        editableMessage: true,
        messageLabel: 'TEXTO PARA E-MAIL',
        copyMessageLabel: 'Mensagem copiada',
        highlightText: entry.item.proposedDate == null
            ? null
            : _formatLongDate(entry.item.proposedDate!),
      ),
    );
  }

  Future<void> _openAuditorSummary(PlanningManagementItem entry) async {
    final message = entry.item.isAdminRejectedAgenda
        ? 'Olá, ${entry.item.auditorName ?? 'auditora'}! Tudo bem?\n'
            'A data proposta para ${entry.item.clientName} foi recusada.\n'
            'Consegue me enviar uma nova sugestão lá no app?'
        : 'Olá, ${entry.item.auditorName ?? 'auditora'}! Tudo bem?\n'
            'Ainda estou aguardando sua sugestão de data para ${entry.item.clientName}.\n'
            'Consegue me enviar a proposta lá no app?';
    final detail = entry.item.isAdminRejectedAgenda
        ? (entry.item.rejectedDates.isEmpty
            ? 'Sem datas recusadas'
            : entry.item.rejectedDates.map(_formatDate).join(', '))
        : (entry.item.lastAuditDate == null
            ? 'Sem auditoria anterior'
            : _formatLongDate(entry.item.lastAuditDate!));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MessageSheet(
        headerLabel: 'RESUMO PARA AUDITORA',
        clientName: entry.item.clientName,
        sections: [
          _MessageSection(
            label: 'AUDITOR RESPONSÁVEL',
            value: entry.item.auditorName ?? 'Não informada',
          ),
          _MessageSection(
            label: 'ENDEREÇO',
            value: entry.clientAddress,
          ),
          _MessageSection(
            label: entry.item.isAdminRejectedAgenda
                ? 'DATAS RECUSADAS'
                : 'ÚLTIMA AUDITORIA',
            value: detail,
          ),
        ],
        message: message,
        editableMessage: true,
        messageLabel: 'TEXTO PARA WHATSAPP',
        copyMessageLabel: 'Mensagem copiada',
      ),
    );
  }

  Future<void> _openConfirmedSummary(PlanningManagementItem entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MessageSheet(
        headerLabel: 'RESUMO DA AUDITORIA CONFIRMADA',
        clientName: entry.item.clientName,
        sections: [
          _MessageSection(
            label: 'ENDEREÇO',
            value: entry.clientAddress,
          ),
          _MessageSection(
            label: 'AUDITOR RESPONSÁVEL',
            value: entry.item.auditorName ?? 'Não informada',
          ),
        ],
        message: '',
        showMessageBlock: false,
      ),
    );
  }

  Future<void> _pickMonth() async {
    final nowMonth = DateTime(DateTime.now().year, DateTime.now().month);
    final nextMonth = DateTime(nowMonth.year, nowMonth.month + 1);
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _OptionSheet<DateTime>(
        title: 'Selecionar periodo',
        options: [
          _Option(value: nowMonth, label: _formatMonthLabel(nowMonth)),
          _Option(value: nextMonth, label: _formatMonthLabel(nextMonth)),
        ],
      ),
    );
    if (result == null || _sameMonth(result, _selectedMonth)) return;
    setState(() {
      _selectedMonth = result;
      _statusFilter = _ManagementFilter.total;
      _auditorFilterPath = 'all';
    });
    await _loadMonth();
  }

  Future<void> _pickAuditor() async {
    final data = _monthData;
    if (data == null) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _OptionSheet<String>(
        title: 'Filtrar por auditora',
        options: [
          const _Option(value: 'all', label: 'Todos os auditores'),
          ...data.auditors.map((a) => _Option(value: a.ref.path, label: a.label)),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _auditorFilterPath = result);
  }

  bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  String _formatMonthLabel(DateTime date) {
    const months = ['Janeiro', 'Fevereiro', 'Marco', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatDate(DateTime date) {
    const months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year.toString().substring(2)}';
  }

  String _formatLongDate(DateTime date) {
    const months = ['janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
    return '${date.day} de ${months[date.month - 1]} de ${date.year}';
  }

  String _auditorFilterLabel(PlanningManagementMonthData data) {
    if (_auditorFilterPath == 'all') return 'Todos os auditores';
    for (final auditor in data.auditors) {
      if (auditor.ref.path == _auditorFilterPath) return auditor.label;
    }
    return 'Todos os auditores';
  }

  List<_ManagementSectionGroup> _groupVisibleItems(
    PlanningManagementMonthData data,
  ) {
    final items = _visibleItems(data);
    if (_statusFilter == _ManagementFilter.pending) {
      return <_ManagementSectionGroup>[
        _ManagementSectionGroup(
          title: 'Auditorias não agendadas',
          items: items
              .where(
                (entry) =>
                    entry.item.isPendingAgenda || entry.item.isAdminRejectedAgenda,
              )
              .toList(growable: false),
        ),
      ].where((section) => section.items.isNotEmpty).toList(growable: false);
    }

    return <_ManagementSectionGroup>[
      _ManagementSectionGroup(
        title: 'Auditorias em validação',
        items: items.where((entry) => entry.item.isPendingConfirmation).toList(growable: false),
      ),
      _ManagementSectionGroup(
        title: 'Auditorias não agendadas',
        items: items
            .where((entry) =>
                !entry.item.isPendingConfirmation &&
                !entry.item.isConfirmedAgenda &&
                !entry.item.isAdminRejectedAgenda &&
                !entry.item.isUnavailableAgenda)
            .toList(growable: false),
      ),
      _ManagementSectionGroup(
        title: 'Auditorias recusadas pelo cliente',
        items: items.where((entry) => entry.item.isAdminRejectedAgenda).toList(growable: false),
      ),
      _ManagementSectionGroup(
        title: 'Auditorias recusadas pelo auditor',
        items: items.where((entry) => entry.item.isUnavailableAgenda).toList(growable: false),
      ),
      _ManagementSectionGroup(
        title: 'Auditorias confirmadas',
        items: items.where((entry) => entry.item.isConfirmedAgenda).toList(growable: false),
      ),
    ].where((section) => section.items.isNotEmpty).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final data = _monthData;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _brand))
            : _loadError != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!, textAlign: TextAlign.center)))
                : RefreshIndicator(
                    onRefresh: () => _loadMonth(showLoader: false),
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        Container(
                          color: Colors.white,
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 60,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: IconButton(
                                            onPressed: () => Navigator.of(context).pop(),
                                            icon: const Icon(Icons.chevron_left, color: _brand, size: 28),
                                          ),
                                        ),
                                        Center(child: Image.asset('assets/logo-escura.png', height: 24)),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: _pickMonth,
                                            iconAlignment: IconAlignment.end,
                                            icon: const Icon(Icons.expand_more),
                                            label: Text(_formatMonthLabel(_selectedMonth)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Gestao das Auditorias',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                            color: _brand,
                                            letterSpacing: -0.8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Acompanhe os retornos das auditoras, valide datas, resolva pendencias e ajuste responsaveis quando necessario.',
                                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.6, color: _muted),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFCFCFE),
                                      borderRadius: BorderRadius.circular(22),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x0F171A24),
                                          blurRadius: 28,
                                          offset: Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      runAlignment: WrapAlignment.center,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _CountChip(label: 'Total', count: _countFor(_ManagementFilter.total, data!), active: _statusFilter == _ManagementFilter.total, color: _brand, onTap: () => setState(() { _statusFilter = _ManagementFilter.total; _focusSection = null; })),
                                        _CountChip(label: 'Confirmadas', count: _countFor(_ManagementFilter.confirmed, data), active: _statusFilter == _ManagementFilter.confirmed, color: const Color(0xFF22A861), onTap: () => setState(() { _statusFilter = _ManagementFilter.confirmed; _focusSection = null; })),
                                        _CountChip(label: 'Recusadas', count: _countFor(_ManagementFilter.rejected, data), active: _statusFilter == _ManagementFilter.rejected, color: const Color(0xFFE14C4C), onTap: () => setState(() { _statusFilter = _ManagementFilter.rejected; _focusSection = null; })),
                                        _CountChip(label: 'Em andamento', count: _countFor(_ManagementFilter.progress, data), active: _statusFilter == _ManagementFilter.progress, color: const Color(0xFF4A7AE8), onTap: () => setState(() { _statusFilter = _ManagementFilter.progress; _focusSection = null; })),
                                        _CountChip(label: 'Nao agendadas', count: _countFor(_ManagementFilter.pending, data), active: _statusFilter == _ManagementFilter.pending, color: const Color(0xFFD9921A), onTap: () => setState(() { _statusFilter = _ManagementFilter.pending; _focusSection = null; })),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: _pickAuditor,
                                    icon: const Icon(Icons.person_search_outlined, size: 18),
                                    label: Text(_auditorFilterLabel(data)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_groupVisibleItems(data).isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
                            child: _EmptyCard(message: 'Nenhuma auditoria encontrada para este recorte.'),
                          )
                        else
                          ..._groupVisibleItems(data).expand(
                            (section) => <Widget>[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                                child: Text(
                                  section.title,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF9A9EAE),
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                              ...section.items.map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                                  child: _ManagementCard(
                                    entry: entry,
                                    formatDate: _formatDate,
                                    onAuditorInfo: () => entry.item.isPendingConfirmation
                                        ? _openClientSummary(entry)
                                        : entry.item.isConfirmedAgenda
                                            ? _openConfirmedSummary(entry)
                                            : _openAuditorSummary(entry),
                                    onApprove: entry.item.isPendingConfirmation
                                        ? () => _approve(entry)
                                        : null,
                                    onReject: entry.item.isPendingConfirmation
                                        ? () => _reject(entry)
                                        : null,
                                    onSwap: entry.item.isUnavailableAgenda
                                        ? () => _swapAuditor(entry)
                                        : null,
                                    onResend: entry.item.isUnavailableAgenda
                                        ? () => _resend(entry)
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEEE9FF) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFFE2D9FF) : const Color(0xFFE5E7F0),
        ),
        boxShadow: active
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A171A24),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: active ? const Color(0xFF7357D8) : const Color(0xFF72778A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManagementCard extends StatelessWidget {
  const _ManagementCard({
    required this.entry,
    required this.formatDate,
    this.onAuditorInfo,
    this.onApprove,
    this.onReject,
    this.onSwap,
    this.onResend,
  });

  final PlanningManagementItem entry;
  final String Function(DateTime) formatDate;
  final VoidCallback? onAuditorInfo;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onSwap;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final colors = _CardStatusPalette.fromItem(item);
    final primary = _primaryText(item);
    final secondary = _secondaryText(item);
    final isValidationCard =
        onApprove != null || onReject != null;
    final isUnavailableCard = onSwap != null || onResend != null;
    final canResendAfterSwap =
        item.previousAuditorRef != null &&
        item.auditorRef != null &&
        item.previousAuditorRef!.path != item.auditorRef!.path;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x0F171A24), blurRadius: 28, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.clientName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B1830),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            colors.label,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF72778A),
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          colors.icon,
                          size: 12,
                          color: colors.foreground,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (onAuditorInfo != null)
                    _RoundIconButton(
                      icon: Icons.info_outline,
                      color: const Color(0xFF72778A),
                      background: const Color(0xFFF6F6FA),
                      onTap: onAuditorInfo!,
                    ),
                  if (isValidationCard) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onApprove != null)
                          _RoundIconButton(
                            icon: Icons.check_circle,
                            color: const Color(0xFF22A861),
                            background: const Color(0xFFE8F7EF),
                            onTap: onApprove!,
                          ),
                        if (onReject != null) ...[
                          const SizedBox(width: 8),
                          _RoundIconButton(
                            icon: Icons.cancel,
                            color: const Color(0xFFE14C4C),
                            background: const Color(0xFFFDECEC),
                            onTap: onReject!,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (primary != null)
            Text(
              primary,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                height: 1.5,
                fontWeight: item.isConfirmedAgenda
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: const Color(0xFF72778A),
              ),
            ),
          if (secondary != null && isUnavailableCard) ...[
            const SizedBox(height: 6),
            Text(
              secondary,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF72778A),
              ),
            ),
          ],
          if (isUnavailableCard) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: Text(
                entry.clientAddress,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF72778A),
                ),
              ),
            ),
          ],
          if (isUnavailableCard) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Auditora atual: ',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        height: 1.5,
                        color: Color(0xFF72778A),
                      ),
                      children: [
                        TextSpan(
                          text: item.auditorName ?? 'Não informada',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF34384A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onSwap != null)
                  _CompactIconAction(
                    icon: Icons.edit_outlined,
                    color: const Color(0xFF7357D8),
                    onTap: onSwap!,
                  ),
                if (onResend != null)
                  _CompactIconAction(
                    icon: Icons.near_me_outlined,
                    color: !canResendAfterSwap
                        ? const Color(0xFFC7C9D6)
                        : const Color(0xFF7357D8),
                    onTap: canResendAfterSwap ? onResend! : null,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String? _primaryText(MonthlyPlanItem item) {
    if (item.isPendingConfirmation) {
      return item.proposedDate == null
          ? 'Data proposta pendente'
          : 'Data proposta: ${formatDate(item.proposedDate!)}';
    }
    if (item.isConfirmedAgenda) {
      return item.confirmedDate == null
          ? 'Data confirmada'
          : 'Confirmada para ${formatDate(item.confirmedDate!)}';
    }
    if (item.isUnavailableAgenda) {
      return null;
    }
    if (item.isAdminRejectedAgenda) {
      if (item.rejectedDates.isEmpty) return null;
      return 'Data recusada: ${formatDate(item.rejectedDates.last)}';
    }
    return null;
  }

  String? _secondaryText(MonthlyPlanItem item) {
    if (item.isUnavailableAgenda) {
      return null;
    }
    return null;
  }
}

class _CardStatusPalette {
  const _CardStatusPalette({
    required this.label,
    required this.icon,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color foreground;

  factory _CardStatusPalette.fromItem(MonthlyPlanItem item) {
    if (item.isPendingConfirmation) {
      return const _CardStatusPalette(
        label: 'Em validação',
        icon: Icons.access_time_rounded,
        foreground: Color(0xFF4A7AE8),
      );
    }
    if (item.isConfirmedAgenda) {
      return const _CardStatusPalette(
        label: 'Confirmada',
        icon: Icons.check_circle_rounded,
        foreground: Color(0xFF22A861),
      );
    }
    if (item.isUnavailableAgenda) {
      return const _CardStatusPalette(
        label: 'Recusada pela auditora',
        icon: Icons.event_busy,
        foreground: Color(0xFFE14C4C),
      );
    }
    if (item.isAdminRejectedAgenda) {
      return const _CardStatusPalette(
        label: 'Recusada pelo cliente',
        icon: Icons.cancel_outlined,
        foreground: Color(0xFFB45479),
      );
    }
    return const _CardStatusPalette(
      label: 'Não agendada',
      icon: Icons.event_available_outlined,
      foreground: Color(0xFFD9921A),
    );
  }
}

class _ManagementSectionGroup {
  const _ManagementSectionGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<PlanningManagementItem> items;
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _CompactIconAction extends StatelessWidget {
  const _CompactIconAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
      icon: Icon(icon, size: 18, color: color),
    );
  }
}

class _MessageSection {
  const _MessageSection({
    required this.label,
    required this.value,
    this.secondaryLabel,
    this.secondaryValue,
    this.copyValue,
    this.copyFeedbackLabel,
  });

  final String label;
  final String value;
  final String? secondaryLabel;
  final String? secondaryValue;
  final String? copyValue;
  final String? copyFeedbackLabel;
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x0F171A24), blurRadius: 28, offset: Offset(0, 10)),
        ],
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          height: 1.6,
          color: Color(0xFF72778A),
        ),
      ),
    );
  }
}

class _MessageSheet extends StatefulWidget {
  const _MessageSheet({
    required this.headerLabel,
    required this.clientName,
    required this.message,
    this.sections = const <_MessageSection>[],
    this.editableMessage = false,
    this.messageLabel = 'Mensagem',
    this.copyMessageLabel = 'Mensagem copiada',
    this.highlightText,
    this.showMessageBlock = true,
  });

  final String headerLabel;
  final String clientName;
  final List<_MessageSection> sections;
  final String message;
  final bool editableMessage;
  final String messageLabel;
  final String copyMessageLabel;
  final String? highlightText;
  final bool showMessageBlock;

  @override
  State<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends State<_MessageSheet> {
  late final _HighlightedTextController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _HighlightedTextController(
      text: widget.message,
      highlightText: widget.highlightText,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.82;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(color: Color(0x1F171A24), blurRadius: 40, offset: Offset(0, 16)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.headerLabel,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9A9EAE),
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.clientName,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1B1830),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF6F6FA),
                        foregroundColor: const Color(0xFF9A9EAE),
                        minimumSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...widget.sections.map(
                  (section) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F6FA),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: section.secondaryLabel != null &&
                              section.secondaryValue != null
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        section.label,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF9A9EAE),
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        section.value,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 13,
                                          height: 1.5,
                                          color: Color(0xFF72778A),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        section.secondaryLabel!,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF9A9EAE),
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        section.secondaryValue!,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 13,
                                          height: 1.5,
                                          color: Color(0xFF72778A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if ((section.copyValue ?? '').trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: _RoundIconButton(
                                      icon: Icons.content_copy,
                                      color: const Color(0xFF7357D8),
                                      background: Colors.white,
                                      onTap: () => _copy(
                                        context,
                                        section.copyValue!,
                                        section.copyFeedbackLabel ??
                                            'Conteúdo copiado',
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  section.label,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF9A9EAE),
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  section.value,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    height: 1.5,
                                    color: Color(0xFF72778A),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                if (widget.showMessageBlock) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F6FA),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.messageLabel,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF9A9EAE),
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x0F171A24),
                                        blurRadius: 20,
                                        offset: Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _controller,
                                    minLines: 4,
                                    maxLines: widget.editableMessage ? 8 : 4,
                                    readOnly: !widget.editableMessage,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      height: 1.6,
                                      color: Color(0xFF34384A),
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(top: 26),
                            child: _RoundIconButton(
                              icon: Icons.content_copy,
                              color: const Color(0xFF7357D8),
                              background: Colors.white,
                              onTap: () => _copy(
                                context,
                                _controller.text,
                                widget.copyMessageLabel,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HighlightedTextController extends TextEditingController {
  _HighlightedTextController({
    required String text,
    required this.highlightText,
  }) : super(text: text);

  final String? highlightText;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final target = highlightText;
    if (target == null || target.isEmpty || !text.contains(target)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final spans = <InlineSpan>[];
    int start = 0;

    while (true) {
      final matchIndex = text.indexOf(target, start);
      if (matchIndex < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: style));
        }
        break;
      }

      if (matchIndex > start) {
        spans.add(TextSpan(text: text.substring(start, matchIndex), style: style));
      }

      spans.add(
        TextSpan(
          text: target,
          style: style?.copyWith(fontWeight: FontWeight.w700) ??
              const TextStyle(fontWeight: FontWeight.w700),
        ),
      );

      start = matchIndex + target.length;
    }

    return TextSpan(style: style, children: spans);
  }
}

class _Option<T> {
  const _Option({required this.value, required this.label});

  final T value;
  final String label;
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
  });

  final String title;
  final List<_Option<T>> options;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(color: Color(0x1F171A24), blurRadius: 40, offset: Offset(0, 16)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1B1830),
                  ),
                ),
                const SizedBox(height: 16),
                ...options.map(
                  (option) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: const Color(0xFFF6F6FA),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).pop(option.value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  option.label,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF34384A),
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9A9EAE)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditorPickerSheet extends StatelessWidget {
  const _AuditorPickerSheet({
    required this.auditors,
    required this.selectedRef,
  });

  final List<PlanningAuditorOption> auditors;
  final DocumentReference? selectedRef;

  @override
  Widget build(BuildContext context) {
    final options = auditors
        .where((auditor) => auditor.ref.path != selectedRef?.path)
        .map((auditor) => _Option<PlanningAuditorOption>(value: auditor, label: auditor.label))
        .toList(growable: false);
    return _OptionSheet<PlanningAuditorOption>(
      title: 'Trocar auditora',
      options: options,
    );
  }
}
