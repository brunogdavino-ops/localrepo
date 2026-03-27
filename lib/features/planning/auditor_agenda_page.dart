import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/monthly_plan_item.dart';
import 'services/monthly_planning_service.dart';

class AuditorAgendaPage extends StatefulWidget {
  const AuditorAgendaPage({super.key});

  @override
  State<AuditorAgendaPage> createState() => _AuditorAgendaPageState();
}

class _AuditorAgendaPageState extends State<AuditorAgendaPage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _softBrand = Color(0xFFEEE9FF);
  final MonthlyPlanningService _planningService = MonthlyPlanningService();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  AuditorAgendaMonthData? _monthData;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

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
      final data = await _planningService.loadAuditorAgendaMonth(_selectedMonth);
      if (!mounted) return;
      setState(() {
        _monthData = data;
        _loadError = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error is StateError
            ? error.message.toString()
            : 'Não foi possível carregar a sua agenda.';
        _isLoading = false;
      });
    }
  }

  Future<void> _changeMonth() async {
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AgendaMonthPickerSheet(initialMonth: _selectedMonth),
    );

    if (result == null || !mounted) return;
    final normalized = DateTime(result.year, result.month);
    if (_isSameMonth(normalized, _selectedMonth)) return;

    setState(() {
      _selectedMonth = normalized;
    });
    await _loadMonth();
  }

  Future<void> _openCalendarOverview() async {
    final data = _monthData;
    if (data == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AgendaCalendarSheet(
        month: _selectedMonth,
        items: data.items,
        formatMonthLabel: _formatMonthLabel,
      ),
    );
  }

  Future<void> _suggestDate(AuditorAgendaItem agendaItem) async {
    if (_isSaving ||
        agendaItem.item.isConfirmedAgenda ||
        agendaItem.item.isUnavailableAgenda ||
        agendaItem.item.isPendingConfirmation) {
      return;
    }

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SuggestDateSheet(
        month: _selectedMonth,
        item: agendaItem,
        itemsForMonth: _monthData?.items ?? const <AuditorAgendaItem>[],
      ),
    );

    if (result == null || !mounted) return;

    await _persistAgendaItem(
      agendaItem.item.copyWith(
        agendaStatus: 'pending_confirmation',
        proposedDate: _normalizeDate(result),
        confirmedDate: null,
        unavailableAt: null,
      ),
    );
  }

  Future<void> _markUnavailable(AuditorAgendaItem agendaItem) async {
    if (_isSaving ||
        agendaItem.item.isConfirmedAgenda ||
        agendaItem.item.isUnavailableAgenda ||
        agendaItem.item.isPendingConfirmation) {
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _UnavailableConfirmSheet(),
    );

    if (confirmed != true || !mounted) return;

    await _persistAgendaItem(
      agendaItem.item.copyWith(
        agendaStatus: 'auditor_unavailable',
        unavailableAt: DateTime.now(),
        proposedDate: null,
        confirmedDate: null,
      ),
    );
  }

  Future<void> _persistAgendaItem(MonthlyPlanItem updatedItem) async {
    final data = _monthData;
    final user = FirebaseAuth.instance.currentUser;
    if (data == null || user == null || _isSaving) return;

    final previous = data;
    final updatedItems = [
      for (final item in data.items)
        if (item.item.id == updatedItem.id)
          AuditorAgendaItem(
            item: updatedItem,
            clientAddress: item.clientAddress,
            clientContactName: item.clientContactName,
            clientContactEmail: item.clientContactEmail,
          )
        else
          item,
    ];

    setState(() {
      _isSaving = true;
      _monthData = AuditorAgendaMonthData(
        monthKey: data.monthKey,
        items: _sortAgendaItems(updatedItems),
      );
    });

    try {
      await _planningService.saveAgendaItem(
        monthKey: data.monthKey,
        item: updatedItem,
        uid: user.uid,
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
          content: Text('Não foi possível salvar esta alteração na agenda.'),
        ),
      );
    }
  }

  List<AuditorAgendaItem> _sortAgendaItems(List<AuditorAgendaItem> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final groupDiff = _groupPriority(a.item).compareTo(_groupPriority(b.item));
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
      return a.item.clientName.toLowerCase().compareTo(b.item.clientName.toLowerCase());
    });
    return sorted;
  }

  int _groupPriority(MonthlyPlanItem item) {
    if (item.isConfirmedAgenda) return 1;
    return 0;
  }

  DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

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

  String _formatDate(DateTime date) {
    const months = <String>['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year.toString().substring(2);
    return '$day ${months[date.month - 1]} $year';
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
              child: IconButton(
                onPressed: _isLoading || _isSaving ? null : _openCalendarOverview,
                style: IconButton.styleFrom(
                  backgroundColor: _softBrand,
                  foregroundColor: _brandColor,
                  minimumSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.calendar_month, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildIntro(AuditorAgendaMonthData _) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Agenda mensal',
                  style: _inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _brandColor,
                    letterSpacing: -0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _isLoading || _isSaving ? null : _changeMonth,
                style: TextButton.styleFrom(
                  foregroundColor: _mutedColor,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(
                  _formatMonthLabel(_selectedMonth),
                  style: _inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _mutedColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Acompanhe as auditorias do mês, proponha datas e veja o status de cada ocorrência.',
              style: _inter(
                fontSize: 13,
                height: 1.55,
                color: _mutedColor,
              ),
            ),
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
                  style: _inter(fontSize: 14, fontWeight: FontWeight.w600, color: _brandColor),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (data == null) return const SizedBox.shrink();

    final pendingItems = data.items
        .where((item) => !item.item.isConfirmedAgenda)
        .toList(growable: false);
    final confirmedItems = data.items.where((item) => item.item.isConfirmedAgenda).toList(growable: false);

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
            child: Text(
              'Pendentes e em andamento',
              style: _inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9A9EAE),
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (pendingItems.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0F171A24), blurRadius: 28, offset: Offset(0, 10)),
                  ],
                ),
                child: Text(
                  'Nenhuma auditoria aguardando ação neste período.',
                  style: _inter(fontSize: 14, height: 1.6, color: _mutedColor),
                ),
              ),
            )
          else
            ...pendingItems.map(
              (agendaItem) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: _AgendaCard(
                  agendaItem: agendaItem,
                  onSuggestDate: _isSaving ? null : () => _suggestDate(agendaItem),
                  onMarkUnavailable: _isSaving ? null : () => _markUnavailable(agendaItem),
                  formatDate: _formatDate,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Text(
              'Confirmada',
              style: _inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9A9EAE),
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (confirmedItems.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0F171A24), blurRadius: 28, offset: Offset(0, 10)),
                  ],
                ),
                child: Text(
                  'Nenhuma auditoria confirmada neste período.',
                  style: _inter(fontSize: 14, height: 1.6, color: _mutedColor),
                ),
              ),
            )
          else
            ...confirmedItems.map(
              (agendaItem) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: _AgendaCard(
                  agendaItem: agendaItem,
                  onSuggestDate: null,
                  onMarkUnavailable: null,
                  formatDate: _formatDate,
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

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({
    required this.agendaItem,
    required this.onSuggestDate,
    required this.onMarkUnavailable,
    required this.formatDate,
  });

  final AuditorAgendaItem agendaItem;
  final VoidCallback? onSuggestDate;
  final VoidCallback? onMarkUnavailable;
  final String Function(DateTime) formatDate;
  static const Color _brandDark = Color(0xFF1B1830);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _dangerColor = Color(0xFFE14C4C);
  static const Color _successColor = Color(0xFF2D9B57);
  static const Color _warningColor = Color(0xFFC77A00);
  static const Color _infoColor = Color(0xFF4A7AE8);
  static const Color _disabledIconColor = Color(0xFFB6BAC8);
  static const Color _actionDisabledBg = Color(0xFFF6F6FA);
  static const Color _actionConfirmBg = Color(0xFFEEE9FF);
  static const Color _actionCancelBg = Color(0xFFFDECEC);

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
    final item = agendaItem.item;

    late final String statusLabel;
    late final IconData statusIcon;
    late final Color statusColor;
    late final String dateLabel;
    late final bool highlightDate;

    if (item.isRejectedAgenda) {
      statusLabel = 'Data recusada';
      statusIcon = Icons.cancel_outlined;
      statusColor = _dangerColor;
      final rejectedDate =
          item.rejectedDates.isEmpty ? null : item.rejectedDates.last;
      dateLabel = rejectedDate == null
          ? 'Data recusada: pendente'
          : 'Data recusada: ${formatDate(rejectedDate)}';
      highlightDate = false;
    } else if (item.isPendingConfirmation) {
      statusLabel = 'Aguardando confirmação';
      statusIcon = Icons.access_time_rounded;
      statusColor = _infoColor;
      dateLabel = item.proposedDate == null
          ? 'Data proposta: pendente'
          : 'Data proposta: ${formatDate(item.proposedDate!)}';
      highlightDate = false;
    } else if (item.isConfirmedAgenda) {
      statusLabel = 'Confirmada';
      statusIcon = Icons.check_circle_rounded;
      statusColor = _successColor;
      dateLabel = item.confirmedDate == null
          ? 'Confirmada: pendente'
          : 'Confirmada: ${formatDate(item.confirmedDate!)}';
      highlightDate = true;
    } else {
      statusLabel = 'Não agendada';
      statusIcon = Icons.event_available_outlined;
      statusColor = _warningColor;
      dateLabel = item.proposedDate == null
          ? 'Data proposta: pendente'
          : 'Data proposta: ${formatDate(item.proposedDate!)}';
      highlightDate = false;
    }

    final actionsDisabled =
        item.isConfirmedAgenda || item.isPendingConfirmation;
    final suggestEnabled = !actionsDisabled && onSuggestDate != null;
    final unavailableEnabled = !actionsDisabled && onMarkUnavailable != null;

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
                      style: _inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _brandDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            statusLabel,
                            style: _inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: statusColor,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          statusIcon,
                          size: 12,
                          color: statusColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: const Offset(2, 0),
                    child: _AgendaActionButton(
                      icon: Icons.calendar_month_outlined,
                      onTap: suggestEnabled ? onSuggestDate : null,
                      enabledColor: _brandColor,
                      disabledColor: _disabledIconColor,
                      enabledBackgroundColor: _actionConfirmBg,
                      disabledBackgroundColor: _actionDisabledBg,
                    ),
                  ),
                  const SizedBox(width: 1),
                  _AgendaActionButton(
                    icon: Icons.event_busy,
                    onTap: unavailableEnabled ? onMarkUnavailable : null,
                    enabledColor: _dangerColor,
                    disabledColor: _disabledIconColor,
                    enabledBackgroundColor: _actionCancelBg,
                    disabledBackgroundColor: _actionDisabledBg,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  agendaItem.clientAddress,
                  style: _inter(
                    fontSize: 14,
                    color: _mutedColor,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  dateLabel,
                    style: _inter(
                      fontSize: 14,
                      fontWeight:
                          highlightDate ? FontWeight.w700 : FontWeight.w500,
                      color: _mutedColor,
                      height: 1.5,
                    ),
                  ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgendaActionButton extends StatelessWidget {
  const _AgendaActionButton({
    required this.icon,
    required this.onTap,
    required this.enabledColor,
    required this.disabledColor,
    required this.enabledBackgroundColor,
    required this.disabledBackgroundColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color enabledColor;
  final Color disabledColor;
  final Color enabledBackgroundColor;
  final Color disabledBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return IconButton(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: enabledBackgroundColor,
        disabledBackgroundColor: disabledBackgroundColor,
        foregroundColor: enabled ? enabledColor : disabledColor,
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(icon, size: 18),
    );
  }
}

class _SuggestDateSheet extends StatefulWidget {
  const _SuggestDateSheet({
    required this.month,
    required this.item,
    required this.itemsForMonth,
  });

  final DateTime month;
  final AuditorAgendaItem item;
  final List<AuditorAgendaItem> itemsForMonth;

  @override
  State<_SuggestDateSheet> createState() => _SuggestDateSheetState();
}

class _SuggestDateSheetState extends State<_SuggestDateSheet> {
  DateTime? _selectedDate;

  DateTime _normalize(DateTime value) => DateTime(value.year, value.month, value.day);

  String _formatMonthLabel(DateTime date) {
    const months = <String>['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight * 0.82;
    final lastDay = DateTime(widget.month.year, widget.month.month + 1, 0);
    final days = [for (int day = 1; day <= lastDay.day; day++) DateTime(widget.month.year, widget.month.month, day)];

    final rejectedSet = widget.item.item.rejectedDates.map(_normalize).toSet();
    final countsByDay = <DateTime, int>{};
    for (final agendaItem in widget.itemsForMonth) {
      final eventDate = agendaItem.item.confirmedDate ?? agendaItem.item.proposedDate;
      if (eventDate == null) continue;
      final normalized = _normalize(eventDate);
      countsByDay[normalized] = (countsByDay[normalized] ?? 0) + 1;
    }
    final hasMarkedDays = countsByDay.isNotEmpty;

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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sugerir data', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A9EAE), letterSpacing: 1.1)),
                          const SizedBox(height: 8),
                          Text(widget.item.item.clientName, style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF1B1830), letterSpacing: -0.4)),
                          const SizedBox(height: 4),
                          Text(widget.item.clientAddress, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: Color(0xFF72778A))),
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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF6F6FA), borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(_formatMonthLabel(widget.month), style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF34384A))),
                          ),
                          const Icon(Icons.calendar_month, size: 18, color: Color(0xFF9A9EAE)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('D', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                          Text('S', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                          Text('T', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                          Text('Q', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                          Text('Q', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                          Text('S', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                          Text('S', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: days.map((day) {
                          final normalized = _normalize(day);
                          final isBlocked = rejectedSet.contains(normalized);
                          final isSelected = _selectedDate != null && DateUtils.isSameDay(_selectedDate, normalized);
                          final count = countsByDay[normalized] ?? 0;
                          Color bg = Colors.white;
                          Color textColor = const Color(0xFF72778A);
                          if (isBlocked) {
                            bg = const Color(0xFFFDECEC);
                            textColor = const Color(0xFFE14C4C);
                          } else if (isSelected) {
                            bg = const Color(0xFFEEE9FF);
                            textColor = const Color(0xFF7357D8);
                          }

                          return InkWell(
                            onTap: isBlocked ? null : () => setState(() => _selectedDate = normalized),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: 40,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${day.day}', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: textColor)),
                                  if (count > 0) ...[
                                    const SizedBox(height: 2),
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: const BoxDecoration(color: Color(0xFF7357D8), shape: BoxShape.circle),
                                      alignment: Alignment.center,
                                      child: Text('$count', style: const TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      if (widget.item.item.isRejectedAgenda || hasMarkedDays)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (widget.item.item.isRejectedAgenda)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(999)),
                                child: const Text('Recusada', style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Color(0xFFE14C4C))),
                              ),
                            if (hasMarkedDays)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(color: const Color(0xFFECF2FF), borderRadius: BorderRadius.circular(999)),
                                child: const Text('Dias com auditorias já propostas/confirmadas', style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Color(0xFF4A7AE8))),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedDate == null ? null : () => Navigator.of(context).pop(_selectedDate),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7357D8),
                      disabledBackgroundColor: const Color(0xFFDFE0EA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: const Text('Enviar proposta', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
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

class _AgendaCalendarSheet extends StatefulWidget {
  const _AgendaCalendarSheet({
    required this.month,
    required this.items,
    required this.formatMonthLabel,
  });

  final DateTime month;
  final List<AuditorAgendaItem> items;
  final String Function(DateTime) formatMonthLabel;

  @override
  State<_AgendaCalendarSheet> createState() => _AgendaCalendarSheetState();
}

class _AgendaMonthPickerSheet extends StatelessWidget {
  const _AgendaMonthPickerSheet({required this.initialMonth});

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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F171A24),
              blurRadius: 40,
              offset: Offset(0, 16),
            ),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selecionar período',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9A9EAE),
                              letterSpacing: 1.1,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Escolha o mês da agenda',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1B1830),
                              letterSpacing: -0.4,
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
                ...months.map(
                  (month) {
                    final isSelected =
                        month.year == initialMonth.year &&
                        month.month == initialMonth.month;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(month),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFEEE9FF)
                                : const Color(0xFFF6F6FA),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _formatMonthLabel(month),
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? const Color(0xFF7357D8)
                                        : const Color(0xFF34384A),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Color(0xFF7357D8),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgendaCalendarSheetState extends State<_AgendaCalendarSheet> {
  DateTime? _selectedDay;

  DateTime _normalize(DateTime value) => DateTime(value.year, value.month, value.day);

  @override
  void initState() {
    super.initState();
    DateTime? firstEventDate;
    for (final agendaItem in widget.items) {
      final eventDate =
          agendaItem.item.confirmedDate ?? agendaItem.item.proposedDate;
      if (eventDate != null) {
        firstEventDate = eventDate;
        break;
      }
    }
    _selectedDay = firstEventDate != null ? _normalize(firstEventDate) : null;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight * 0.82;
    final lastDay = DateTime(widget.month.year, widget.month.month + 1, 0);
    final days = [for (int day = 1; day <= lastDay.day; day++) DateTime(widget.month.year, widget.month.month, day)];

    final itemsByDay = <DateTime, List<AuditorAgendaItem>>{};
    for (final agendaItem in widget.items) {
      final eventDate = agendaItem.item.confirmedDate ?? agendaItem.item.proposedDate;
      if (eventDate == null) continue;
      final normalized = _normalize(eventDate);
      itemsByDay.putIfAbsent(normalized, () => <AuditorAgendaItem>[]).add(agendaItem);
    }

    final selectedItems = _selectedDay == null ? const <AuditorAgendaItem>[] : (itemsByDay[_selectedDay!] ?? const <AuditorAgendaItem>[]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Color(0x1F171A24), blurRadius: 40, offset: Offset(0, 16))],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
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
                              const Text('Calendário do mês', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A9EAE), letterSpacing: 1.1)),
                              const SizedBox(height: 8),
                              Text(widget.formatMonthLabel(widget.month), style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF1B1830), letterSpacing: -0.4)),
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
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFF6F6FA), borderRadius: BorderRadius.circular(22)),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('D', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                              Text('S', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                              Text('T', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                              Text('Q', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                              Text('Q', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                              Text('S', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                              Text('S', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF9A9EAE))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: days.map((day) {
                              final normalized = _normalize(day);
                              final count = itemsByDay[normalized]?.length ?? 0;
                              final selected = _selectedDay != null && DateUtils.isSameDay(_selectedDay, normalized);
                              return InkWell(
                                onTap: count == 0 ? null : () => setState(() => _selectedDay = normalized),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  width: 44,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: selected || count > 0 ? const Color(0xFFEEE9FF) : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${day.day}', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: count > 0 ? const Color(0xFF7357D8) : const Color(0xFF9A9EAE))),
                                      const Spacer(),
                                      if (count > 0)
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: const BoxDecoration(color: Color(0xFF7357D8), shape: BoxShape.circle),
                                            alignment: Alignment.center,
                                            child: Text('$count', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(growable: false),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedDay != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFFF6F6FA), borderRadius: BorderRadius.circular(18)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedDay == null ? '' : '${_selectedDay!.day.toString().padLeft(2, '0')} ${['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'][_selectedDay!.month - 1]} ${_selectedDay!.year.toString().substring(2)}',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A9EAE), letterSpacing: 1.1),
                            ),
                            const SizedBox(height: 10),
                            ...selectedItems.map(
                              (agendaItem) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(agendaItem.item.clientName, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1B1830))),
                                    const SizedBox(height: 4),
                                    Text(agendaItem.clientAddress, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, height: 1.5, color: Color(0xFF72778A))),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableConfirmSheet extends StatelessWidget {
  const _UnavailableConfirmSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
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
                          Text('Confirmar ação', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A9EAE), letterSpacing: 1.1)),
                          SizedBox(height: 8),
                          Text('Você não poderá realizar esta auditoria?', style: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1B1830), letterSpacing: -0.4)),
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
                  'Confirme para indicar que você não poderá realizar esta auditoria.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.6, color: Color(0xFF72778A)),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: Color(0xFF72778A))),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7357D8), foregroundColor: Colors.white),
                      child: const Text('Confirmar', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
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

