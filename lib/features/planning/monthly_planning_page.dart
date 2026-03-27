import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/monthly_plan_item.dart';
import 'services/monthly_planning_service.dart';

class MonthlyPlanningPage extends StatefulWidget {
  const MonthlyPlanningPage({super.key});

  @override
  State<MonthlyPlanningPage> createState() => _MonthlyPlanningPageState();
}

class _MonthlyPlanningPageState extends State<MonthlyPlanningPage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _brandDark = Color(0xFF1B1830);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _softBrand = Color(0xFFEEE9FF);
  static const Color _surfaceSoft = Color(0xFFF6F6FA);
  static const Color _warningBg = Color(0xFFFFF3DF);
  static const Color _warningColor = Color(0xFFD9921A);
  static const Color _dangerColor = Color(0xFFE14C4C);

  final MonthlyPlanningService _planningService = MonthlyPlanningService();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  PlanningMonthData? _monthData;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String _auditorFilterPath = 'all';

  TextStyle _inter({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _loadMonth({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final data = await _planningService.loadMonth(_selectedMonth);
      if (!mounted) return;
      setState(() {
        _monthData = PlanningMonthData(
          monthKey: data.monthKey,
          companyRef: data.companyRef,
          items: _sortItems(data.items),
          clients: data.clients,
          auditors: data.auditors,
        );
        _loadError = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error is StateError
            ? error.message.toString()
            : 'Não foi possível carregar o planejamento mensal.';
        _isLoading = false;
      });
    }
  }

  Future<void> _changeMonth() async {
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MonthPickerSheet(initialMonth: _selectedMonth),
    );

    if (result == null || !mounted) return;
    final normalized = DateTime(result.year, result.month);
    if (_isSameMonth(normalized, _selectedMonth)) return;

    setState(() {
      _selectedMonth = normalized;
      _auditorFilterPath = 'all';
    });
    await _loadMonth();
  }

  Future<void> _changeAuditorFilter() async {
    final data = _monthData;
    if (data == null) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AuditorFilterSheet(
        auditors: data.auditors,
        selectedPath: _auditorFilterPath,
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _auditorFilterPath = result;
    });
  }

  Future<void> _addManualItem() async {
    final data = _monthData;
    if (data == null || _isSaving) return;

    final selectedClient = await showModalBottomSheet<PlanningClientOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PlanningClientPickerSheet(clients: data.clients),
    );

    if (selectedClient == null || !mounted) return;

    final existing = data.items.cast<MonthlyPlanItem?>().firstWhere(
          (item) => item?.id == selectedClient.id,
          orElse: () => null,
        );

    final updatedItem = (existing ??
            MonthlyPlanItem(
              id: selectedClient.id,
              clientRef: selectedClient.ref,
              clientName: selectedClient.name,
              auditorRef: selectedClient.auditorRef,
              auditorName: selectedClient.auditorName,
              auditRecurrence: selectedClient.auditRecurrence,
              lastAuditDate: selectedClient.lastAuditDate,
              monthKey: data.monthKey,
              included: true,
              isExtra: true,
              source: 'manual',
              companyRef: data.companyRef,
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
            ))
        .copyWith(
          included: true,
          isExtra: true,
          source: 'manual',
          status: existing?.isCancelled == true ? 'planned' : (existing?.status ?? 'planned'),
          sentAt: existing?.isCancelled == true ? null : existing?.sentAt,
          cancelledAt: null,
          agendaStatus: existing?.isCancelled == true
              ? 'pending'
              : (existing?.agendaStatus ?? 'pending'),
          proposedDate: existing?.isCancelled == true ? null : existing?.proposedDate,
          confirmedDate: existing?.isCancelled == true ? null : existing?.confirmedDate,
          rejectedDates: existing?.isCancelled == true
              ? const []
              : existing?.rejectedDates,
          unavailableAt: existing?.isCancelled == true ? null : existing?.unavailableAt,
          auditorRef: existing?.auditorRef ?? selectedClient.auditorRef,
          auditorName: existing?.auditorName ?? selectedClient.auditorName,
          auditRecurrence: selectedClient.auditRecurrence,
          lastAuditDate: selectedClient.lastAuditDate,
        );

    await _persistSingleItem(updatedItem);
  }

  Future<void> _editAuditor(MonthlyPlanItem item) async {
    final data = _monthData;
    if (data == null || _isSaving || !item.isPlanned) return;

    final selectedAuditor = await showModalBottomSheet<PlanningAuditorOption>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PlanningAuditorPickerSheet(
        auditors: data.auditors,
        selectedRef: item.auditorRef,
      ),
    );

    if (selectedAuditor == null || !mounted) return;

    await _persistSingleItem(
      item.copyWith(
        auditorRef: selectedAuditor.ref,
        auditorName: selectedAuditor.label,
      ),
    );
  }

  Future<void> _toggleIncluded(MonthlyPlanItem item, bool value) async {
    if (!item.isPlanned) return;
    await _persistSingleItem(item.copyWith(included: value));
  }

  Future<void> _toggleSelectAll(bool value) async {
    final data = _monthData;
    final user = FirebaseAuth.instance.currentUser;
    if (data == null || user == null || _isSaving) return;

    final eligibleIds = _visibleItems(data)
        .where((item) => item.isPlanned)
        .map((item) => item.id)
        .toSet();
    final updatedItems = data.items
        .map(
          (item) => eligibleIds.contains(item.id)
              ? item.copyWith(included: value)
              : item,
        )
        .toList(growable: false);

    await _persistMultipleItems(updatedItems, uid: user.uid);
  }

  Future<void> _sendItem(MonthlyPlanItem item) async {
    if (!item.isPlanned || !item.included) return;
    await _persistSingleItem(
      item.copyWith(
        status: 'sent',
        sentAt: DateTime.now(),
        cancelledAt: null,
        agendaStatus: 'pending',
        proposedDate: null,
        confirmedDate: null,
        unavailableAt: null,
      ),
    );
  }

  Future<void> _sendSelectedVisible() async {
    final data = _monthData;
    final user = FirebaseAuth.instance.currentUser;
    if (data == null || user == null || _isSaving) return;

    final eligibleIds = _visibleItems(data)
        .where((item) => item.isPlanned && item.included)
        .map((item) => item.id)
        .toSet();
    if (eligibleIds.isEmpty) return;

    final now = DateTime.now();
    final updatedItems = data.items
        .map(
          (item) => eligibleIds.contains(item.id)
              ? item.copyWith(
                  status: 'sent',
                  sentAt: now,
                  cancelledAt: null,
                  agendaStatus: 'pending',
                  proposedDate: null,
                  confirmedDate: null,
                  unavailableAt: null,
                )
              : item,
        )
        .toList(growable: false);

    await _persistMultipleItems(updatedItems, uid: user.uid);
  }

  Future<void> _confirmCancel(MonthlyPlanItem item) async {
    if ((!item.isPlanned && !item.isSent) || _isSaving) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CancelPlanningSheet(),
    );

    if (confirmed != true || !mounted) return;

    await _persistSingleItem(
      item.copyWith(
        status: 'cancelled',
        cancelledAt: DateTime.now(),
        included: false,
        agendaStatus: 'pending',
        proposedDate: null,
        confirmedDate: null,
        rejectedDates: const [],
        unavailableAt: null,
      ),
    );
  }

  Future<void> _persistSingleItem(MonthlyPlanItem updatedItem) async {
    final data = _monthData;
    final user = FirebaseAuth.instance.currentUser;
    if (data == null || user == null || _isSaving) return;

    final updatedItems = [
      for (final item in data.items)
        if (item.id == updatedItem.id) updatedItem else item,
      if (data.items.every((item) => item.id != updatedItem.id)) updatedItem,
    ];

    await _persistMultipleItems(updatedItems, uid: user.uid);
  }

  Future<void> _persistMultipleItems(
    List<MonthlyPlanItem> updatedItems, {
    required String uid,
  }) async {
    final data = _monthData;
    if (data == null) return;

    final previous = data;
    final nextData = PlanningMonthData(
      monthKey: data.monthKey,
      companyRef: data.companyRef,
      items: _sortItems(updatedItems),
      clients: data.clients,
      auditors: data.auditors,
    );

    setState(() {
      _isSaving = true;
      _monthData = nextData;
    });

    try {
      await _planningService.saveItems(
        monthKey: data.monthKey,
        items: nextData.items,
        uid: uid,
      );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _monthData = previous;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar esta alteração.'),
        ),
      );
    }
  }

  List<MonthlyPlanItem> _visibleItems(PlanningMonthData data) {
    return data.items.where((item) {
      if (_auditorFilterPath == 'all') return true;
      return item.auditorRef?.path == _auditorFilterPath;
    }).toList(growable: false);
  }

  List<MonthlyPlanItem> _sortItems(List<MonthlyPlanItem> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final statusDiff = _statusPriority(a.status).compareTo(_statusPriority(b.status));
      if (statusDiff != 0) return statusDiff;
      return a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase());
    });
    return sorted;
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

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  String _formatShortDate(DateTime? date) {
    if (date == null) return 'Sem auditoria anterior';
    const months = <String>['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year.toString().substring(2);
    return '$day ${months[date.month - 1]} $year';
  }

  String _auditorFilterLabel(PlanningMonthData data) {
    if (_auditorFilterPath == 'all') return 'Todos os auditores';
    for (final auditor in data.auditors) {
      if (auditor.ref.path == _auditorFilterPath) return auditor.label;
    }
    return 'Todos os auditores';
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: SizedBox(
        height: 60,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: const Offset(-6, 0),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.chevron_left,
                    size: 28,
                    color: _brandColor,
                  ),
                ),
              ),
            ),
            Center(
              child: Image.asset(
                'assets/logo-escura.png',
                height: 24,
                fit: BoxFit.contain,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  IconButton(
                    onPressed: _isLoading || _isSaving ? null : _changeMonth,
                    style: IconButton.styleFrom(
                      backgroundColor: _softBrand,
                      foregroundColor: _brandColor,
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isLoading || _isSaving ? null : _addManualItem,
                    style: IconButton.styleFrom(
                      backgroundColor: _softBrand,
                      foregroundColor: _brandColor,
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.add_circle, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildIntro(PlanningMonthData data) {
    final visibleItems = _visibleItems(data);
    final filterLabel = _auditorFilterLabel(data);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Planejamento mensal',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _inter(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _brandColor,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Revise as auditorias do mês, ajuste o auditor responsável e confirme o planejamento.',
              style: _inter(
                fontSize: 13,
                height: 1.55,
                color: _mutedColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _softBrand,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${visibleItems.length}',
                      style: _inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _brandColor,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _auditorFilterPath == 'all'
                          ? 'auditorias'
                          : 'auditorias de $filterLabel',
                      style: _inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _brandColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isLoading || _isSaving ? null : _changeAuditorFilter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _surfaceSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Color(0xFF9A9EAE)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            filterLabel,
                            overflow: TextOverflow.ellipsis,
                            style: _inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF34384A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more, size: 16, color: Color(0xFF9A9EAE)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final data = _monthData;
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _brandColor),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: _inter(fontSize: 14, height: 1.6, color: _mutedColor),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadMonth,
                child: Text(
                  'Tentar novamente',
                  style: _inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _brandColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (data == null) return const SizedBox.shrink();

    final visibleItems = _visibleItems(data);
    final eligibleVisibleItems = visibleItems.where((item) => item.isPlanned).toList(growable: false);
    final allSelected = eligibleVisibleItems.isNotEmpty && eligibleVisibleItems.every((item) => item.included);
    final canSendAll = visibleItems.any((item) => item.isPlanned && item.included);

    return RefreshIndicator(
      color: _brandColor,
      onRefresh: () => _loadMonth(showLoader: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  _buildIntro(data),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: allSelected,
                          activeColor: _brandColor,
                          side: const BorderSide(color: Color(0xFFC7C9D6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          onChanged: _isSaving || eligibleVisibleItems.isEmpty
                              ? null
                              : (value) => _toggleSelectAll(value ?? false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selecionar todas as auditorias',
                          style: _inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _mutedColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSaving || !canSendAll ? null : _sendSelectedVisible,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandColor,
                    disabledBackgroundColor: const Color(0xFFDFE0EA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.near_me, size: 16),
                  label: Text(
                    'Enviar',
                    style: _inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          if (visibleItems.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F171A24),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Text(
                  'Nenhuma auditoria encontrada para o filtro atual.',
                  style: _inter(fontSize: 14, height: 1.6, color: _mutedColor),
                ),
              ),
            )
          else
            ...visibleItems.map(
              (item) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: _PlanningItemCard(
                  item: item,
                  brandColor: _brandColor,
                  brandDark: _brandDark,
                  mutedColor: _mutedColor,
                  softBrand: _softBrand,
                  warningBg: _warningBg,
                  warningColor: _warningColor,
                  dangerColor: _dangerColor,
                  isBusy: _isSaving,
                  onIncludedChanged: item.isPlanned ? (value) => _toggleIncluded(item, value) : null,
                  onSend: item.isPlanned && item.included ? () => _sendItem(item) : null,
                  onCancel: (item.isPlanned || item.isSent) ? () => _confirmCancel(item) : null,
                  onEditAuditor: item.isPlanned ? () => _editAuditor(item) : null,
                  formatLastAuditDate: _formatShortDate,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bgColor,
        body: _buildBody(),
      ),
    );
  }
}

class _PlanningItemCard extends StatelessWidget {
  const _PlanningItemCard({
    required this.item,
    required this.brandColor,
    required this.brandDark,
    required this.mutedColor,
    required this.softBrand,
    required this.warningBg,
    required this.warningColor,
    required this.dangerColor,
    required this.isBusy,
    required this.onIncludedChanged,
    required this.onSend,
    required this.onCancel,
    required this.onEditAuditor,
    required this.formatLastAuditDate,
  });

  final MonthlyPlanItem item;
  final Color brandColor;
  final Color brandDark;
  final Color mutedColor;
  final Color softBrand;
  final Color warningBg;
  final Color warningColor;
  final Color dangerColor;
  final bool isBusy;
  final ValueChanged<bool>? onIncludedChanged;
  final VoidCallback? onSend;
  final VoidCallback? onCancel;
  final VoidCallback? onEditAuditor;
  final String Function(DateTime?) formatLastAuditDate;

  TextStyle _inter({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
  @override
  Widget build(BuildContext context) {
    final recurrenceLabel = (item.auditRecurrence == null || item.auditRecurrence!.isEmpty)
        ? 'Sem recorrência'
        : item.auditRecurrence!;
    final auditorLabel = (item.auditorName == null || item.auditorName!.isEmpty)
        ? 'Não definido'
        : item.auditorName!;

    final bool checkboxValue = item.isSent ? true : item.included;
    final bool checkboxEnabled = item.isPlanned && !isBusy;
    final bool cardMuted = item.isCancelled;

    return Opacity(
      opacity: cardMuted ? 0.65 : (!item.included && item.isPlanned ? 0.78 : 1),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F171A24),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: checkboxValue,
                  tristate: item.isCancelled,
                  activeColor: item.isSent ? const Color(0xFFD8CEF9) : brandColor,
                  side: BorderSide(
                    color: item.isCancelled ? const Color(0xFFD7DAE5) : const Color(0xFFC7C9D6),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  onChanged: checkboxEnabled ? (value) => onIncludedChanged?.call(value ?? false) : null,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 58),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.clientName,
                          style: _inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: brandDark,
                            letterSpacing: -0.4,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 3),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PlanningBadge(
                                label: recurrenceLabel,
                                backgroundColor: const Color(0xFFF0F1F6),
                                textColor: mutedColor,
                              ),
                              if (item.isExtra) ...[
                                const SizedBox(width: 6),
                                _PlanningBadge(
                                  label: 'Extra',
                                  backgroundColor: warningBg,
                                  textColor: warningColor,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ],
                              if (item.isSent) ...[
                                const SizedBox(width: 6),
                                _PlanningBadge(
                                  label: 'Enviada',
                                  backgroundColor: softBrand,
                                  textColor: brandColor,
                                ),
                              ],
                              if (item.isCancelled) ...[
                                const SizedBox(width: 6),
                                _PlanningBadge(
                                  label: 'Cancelada',
                                  backgroundColor: const Color(0xFFF0F1F6),
                                  textColor: mutedColor,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Última auditoria: ${formatLastAuditDate(item.lastAuditDate)}',
                          style: _inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: mutedColor,
                            height: 1.18,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: _inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: mutedColor,
                                    height: 1.18,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Auditor: '),
                                    TextSpan(
                                      text: auditorLabel,
                                      style: _inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF34384A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: onEditAuditor,
                              visualDensity: VisualDensity.compact,
                              splashRadius: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              icon: Icon(Icons.edit, size: 18, color: onEditAuditor == null ? const Color(0xFFDFE0EA) : brandColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -1,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F6FA),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: onSend,
                            visualDensity: VisualDensity.compact,
                            splashRadius: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            icon: Icon(Icons.near_me, size: 18, color: onSend == null ? const Color(0xFFDFE0EA) : brandColor),
                          ),
                          const SizedBox(width: 1),
                          IconButton(
                            onPressed: onCancel,
                            visualDensity: VisualDensity.compact,
                            splashRadius: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            icon: Icon(Icons.block, size: 18, color: onCancel == null ? const Color(0xFFDFE0EA) : dangerColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanningBadge extends StatelessWidget {
  const _PlanningBadge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.fontWeight = FontWeight.w600,
    this.letterSpacing,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final FontWeight fontWeight;
  final double? letterSpacing;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            softWrap: false,
            overflow: TextOverflow.visible,
            textWidthBasis: TextWidthBasis.longestLine,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: fontWeight,
              color: textColor,
              letterSpacing: letterSpacing,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthPickerSheet extends StatelessWidget {
  const _MonthPickerSheet({required this.initialMonth});

  final DateTime initialMonth;

  String _formatMonthLabel(DateTime date) {
    const months = <String>[
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    final months = <DateTime>[
      currentMonth,
      DateTime(currentMonth.year, currentMonth.month + 1),
    ];

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
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Selecionar mês', style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF1B1830), letterSpacing: -0.4)),
                          SizedBox(height: 8),
                          Text('Escolha o período que deseja planejar.', style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.6, color: Color(0xFF72778A))),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFF6F6FA), foregroundColor: const Color(0xFF9A9EAE), minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: months.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final month = months[index];
                      final selected = month.year == initialMonth.year && month.month == initialMonth.month;
                      return Material(
                        color: selected ? const Color(0xFFEEE9FF) : const Color(0xFFF6F6FA),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(month),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _formatMonthLabel(month),
                                    style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: selected ? const Color(0xFF7357D8) : const Color(0xFF34384A)),
                                  ),
                                ),
                                if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF7357D8)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
class _PlanningClientPickerSheet extends StatefulWidget {
  const _PlanningClientPickerSheet({required this.clients});

  final List<PlanningClientOption> clients;

  @override
  State<_PlanningClientPickerSheet> createState() => _PlanningClientPickerSheetState();
}

class _PlanningClientPickerSheetState extends State<_PlanningClientPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.clients.where((client) {
      if (query.isEmpty) return true;
      return client.name.toLowerCase().contains(query);
    }).toList(growable: false);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: Color(0x1F171A24), blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Adicionar auditoria', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A9EAE), letterSpacing: 1.1)),
                          SizedBox(height: 8),
                          Text('Selecionar cliente', style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF1B1830), letterSpacing: -0.4)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFF6F6FA), foregroundColor: const Color(0xFF9A9EAE), minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: const Color(0xFFF6F6FA), borderRadius: BorderRadius.circular(18)),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Buscar cliente...',
                      prefixIcon: Icon(Icons.search, color: Color(0xFF9A9EAE)),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Nenhum cliente encontrado.', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: Color(0xFF72778A))),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final client = filtered[index];
                            return Material(
                              color: const Color(0xFFFCFCFE),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.of(context).pop(client),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(client.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF72778A))),
                                      ),
                                      const Icon(Icons.chevron_right, size: 18, color: Color(0xFF7357D8)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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

class _PlanningAuditorPickerSheet extends StatelessWidget {
  const _PlanningAuditorPickerSheet({required this.auditors, required this.selectedRef});

  final List<PlanningAuditorOption> auditors;
  final DocumentReference? selectedRef;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: Color(0x1F171A24), blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Selecionar auditor', style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF1B1830), letterSpacing: -0.4)),
                          SizedBox(height: 8),
                          Text('A alteração vale apenas para esta ocorrência do mês.', style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.6, color: Color(0xFF72778A))),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFF6F6FA), foregroundColor: const Color(0xFF9A9EAE), minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: auditors.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final auditor = auditors[index];
                      final selected = selectedRef != null && auditor.ref.path == selectedRef!.path;
                      return Material(
                        color: selected ? const Color(0xFFEEE9FF) : const Color(0xFFF6F6FA),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(auditor),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(auditor.label, style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: selected ? const Color(0xFF7357D8) : const Color(0xFF34384A))),
                                ),
                                if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF7357D8)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

class _AuditorFilterSheet extends StatelessWidget {
  const _AuditorFilterSheet({required this.auditors, required this.selectedPath});

  final List<PlanningAuditorOption> auditors;
  final String selectedPath;

  @override
  Widget build(BuildContext context) {
    final options = [
      const _SimpleOption(value: 'all', label: 'Todos os auditores'),
      ...auditors.map((auditor) => _SimpleOption(value: auditor.ref.path, label: auditor.label)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: Color(0x1F171A24), blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Filtrar por auditor', style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF1B1830), letterSpacing: -0.4)),
                          SizedBox(height: 8),
                          Text('Filtra pela auditora atribuída no item mensal.', style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.6, color: Color(0xFF72778A))),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFF6F6FA), foregroundColor: const Color(0xFF9A9EAE), minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final selected = option.value == selectedPath;
                      return Material(
                        color: selected ? const Color(0xFFEEE9FF) : const Color(0xFFF6F6FA),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(option.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(option.label, style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: selected ? const Color(0xFF7357D8) : const Color(0xFF34384A))),
                                ),
                                if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF7357D8)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

class _CancelPlanningSheet extends StatelessWidget {
  const _CancelPlanningSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: Color(0x1F171A24), blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cancelar auditoria', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A9EAE), letterSpacing: 1.1)),
                          SizedBox(height: 8),
                          Text('Confirmação', style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF1B1830), letterSpacing: -0.4)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFF6F6FA), foregroundColor: const Color(0xFF9A9EAE), minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Essa auditoria sairá do planejamento mensal. Você tem certeza disso?',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.6, color: Color(0xFF72778A)),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Não', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: Color(0xFF72778A))),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7357D8), foregroundColor: Colors.white),
                      child: const Text('Sim', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleOption {
  const _SimpleOption({required this.value, required this.label});

  final String value;
  final String label;
}
