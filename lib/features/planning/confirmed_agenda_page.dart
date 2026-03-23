import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/monthly_plan_item.dart';
import 'services/monthly_planning_service.dart';

class ConfirmedAgendaPage extends StatefulWidget {
  const ConfirmedAgendaPage({super.key});

  @override
  State<ConfirmedAgendaPage> createState() => _ConfirmedAgendaPageState();
}

class _ConfirmedAgendaPageState extends State<ConfirmedAgendaPage> {
  static const Color _bg = Color(0xFFF7F7FB);
  static const Color _brand = Color(0xFF7357D8);
  static const Color _muted = Color(0xFF72778A);

  final MonthlyPlanningService _service = MonthlyPlanningService();

  late DateTime _startDate;
  late DateTime _endDate;
  ConfirmedAgendaData? _agendaData;
  bool _isLoading = true;
  String? _loadError;
  bool _actionsOpen = false;
  Set<String> _selectedAuditorPaths = <String>{};

  @override
  void initState() {
    super.initState();
    final today = _normalize(DateTime.now());
    _startDate = today;
    _endDate = today.add(const Duration(days: 6));
    _loadAgenda();
  }

  Future<void> _loadAgenda({bool resetAuditors = false}) async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await _service.loadConfirmedAgenda(
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      final availablePaths = data.items
          .map((entry) => entry.item.auditorRef?.path)
          .whereType<String>()
          .toSet();
      setState(() {
        _agendaData = data;
        _isLoading = false;
        if (resetAuditors || _selectedAuditorPaths.isEmpty) {
          _selectedAuditorPaths = availablePaths;
        } else {
          _selectedAuditorPaths = _selectedAuditorPaths.intersection(availablePaths);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error is StateError
            ? error.message.toString()
            : 'Nao foi possivel carregar a agenda de auditorias.';
        _isLoading = false;
      });
    }
  }

  DateTime _normalize(DateTime value) => DateTime(value.year, value.month, value.day);

  String _formatShort(DateTime date) {
    const months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year.toString().substring(2)}';
  }

  String _formatHeaderDay(DateTime date) {
    const weekdays = ['Domingo', 'Segunda', 'Terca', 'Quarta', 'Quinta', 'Sexta', 'Sabado'];
    const months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    return '${weekdays[date.weekday % 7]}, ${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}';
  }

  String _rangeLabel() => '${_formatShort(_startDate)} - ${_formatShort(_endDate)}';

  List<PlanningAuditorOption> _availableAuditors(ConfirmedAgendaData data) {
    final usedPaths = data.items
        .map((entry) => entry.item.auditorRef?.path)
        .whereType<String>()
        .toSet();
    return data.auditors
        .where((auditor) => usedPaths.contains(auditor.ref.path))
        .toList(growable: false);
  }

  List<ConfirmedAgendaEntry> _visibleEntries(ConfirmedAgendaData data) {
    return data.items.where((entry) {
      final path = entry.item.auditorRef?.path;
      if (path == null) return false;
      return _selectedAuditorPaths.contains(path);
    }).toList(growable: false);
  }

  Map<DateTime, List<ConfirmedAgendaEntry>> _groupedEntries(ConfirmedAgendaData data) {
    final grouped = <DateTime, List<ConfirmedAgendaEntry>>{};
    for (final entry in _visibleEntries(data)) {
      final date = _normalize(entry.item.confirmedDate!);
      grouped.putIfAbsent(date, () => <ConfirmedAgendaEntry>[]).add(entry);
    }
    for (final items in grouped.values) {
      items.sort((a, b) {
        final auditorA = (a.item.auditorName ?? '').toLowerCase();
        final auditorB = (b.item.auditorName ?? '').toLowerCase();
        final auditorDiff = auditorA.compareTo(auditorB);
        if (auditorDiff != 0) return auditorDiff;
        return a.item.clientName.toLowerCase().compareTo(b.item.clientName.toLowerCase());
      });
    }
    return Map.fromEntries(
      grouped.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  Future<void> _openPeriodFilter() async {
    DateTime tempStart = _startDate;
    DateTime tempEnd = _endDate;
    String? rangeError;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> pickDate(bool isStart) async {
            final current = isStart ? tempStart : tempEnd;
            final result = await showDatePicker(
              context: context,
              initialDate: current,
              firstDate: DateTime(2024),
              lastDate: DateTime(2035),
            );
            if (result == null) return;
            final normalized = _normalize(result);
            setModalState(() {
              if (isStart) {
                tempStart = normalized;
                if (tempStart.isAfter(tempEnd)) {
                  tempEnd = tempStart;
                }
              } else {
                tempEnd = normalized;
                if (tempEnd.isBefore(tempStart)) {
                  tempStart = tempEnd;
                }
              }
              final days = tempEnd.difference(tempStart).inDays;
              rangeError = days > 6 ? 'O periodo selecionado pode ter no maximo 7 dias.' : null;
            });
          }

          return _SheetShell(
            title: 'Selecionar periodo',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PickerCard(
                        label: 'Data inicial',
                        value: _formatShort(tempStart),
                        selected: true,
                        onTap: () => pickDate(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PickerCard(
                        label: 'Data final',
                        value: _formatShort(tempEnd),
                        selected: false,
                        onTap: () => pickDate(false),
                      ),
                    ),
                  ],
                ),
                if (rangeError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    rangeError!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE14C4C),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: rangeError == null ? () => Navigator.of(context).pop(true) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (applied != true) return;
    setState(() {
      _startDate = tempStart;
      _endDate = tempEnd;
      _actionsOpen = false;
    });
    await _loadAgenda(resetAuditors: true);
  }

  Future<void> _openAuditorFilter() async {
    final data = _agendaData;
    if (data == null) return;
    final available = _availableAuditors(data);
    final tempSelection = {..._selectedAuditorPaths};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final allSelected = tempSelection.length == available.length && available.isNotEmpty;
          return _SheetShell(
            title: 'Selecionar auditores',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    setModalState(() {
                      if (allSelected) {
                        tempSelection.clear();
                      } else {
                        tempSelection
                          ..clear()
                          ..addAll(available.map((auditor) => auditor.ref.path));
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _CheckMark(checked: allSelected),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Selecionar todos',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...available.map(
                  (auditor) {
                    final checked = tempSelection.contains(auditor.ref.path);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: const Color(0xFFFCFCFE),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setModalState(() {
                              if (checked) {
                                tempSelection.remove(auditor.ref.path);
                              } else {
                                tempSelection.add(auditor.ref.path);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    auditor.label,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                _CheckMark(checked: checked),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(tempSelection),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == null) return;
    setState(() {
      _selectedAuditorPaths = result;
      _actionsOpen = false;
    });
  }

  void _clearFilters() {
    final today = _normalize(DateTime.now());
    setState(() {
      _startDate = today;
      _endDate = today.add(const Duration(days: 6));
      _actionsOpen = false;
    });
    _loadAgenda(resetAuditors: true);
  }

  void _toggleHeaderMenu() {
    setState(() {
      _actionsOpen = !_actionsOpen;
    });
  }

  void _closeHeaderMenu() {
    if (!_actionsOpen || !mounted) return;
    setState(() {
      _actionsOpen = false;
    });
  }

  Widget _buildHeaderActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(right: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFEEE9FF),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        splashRadius: 18,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: const Color(0xFF7357D8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _agendaData;
    final grouped = data == null ? <DateTime, List<ConfirmedAgendaEntry>>{} : _groupedEntries(data);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closeHeaderMenu,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _brand))
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_loadError!, textAlign: TextAlign.center),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadAgenda(resetAuditors: false),
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
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Row(
                                        children: [
                                          Transform.translate(
                                            offset: const Offset(-6, 0),
                                            child: IconButton(
                                              onPressed: () => Navigator.of(context).maybePop(),
                                              icon: const Icon(
                                                Icons.chevron_left,
                                                size: 28,
                                                color: Color(0xFF7357D8),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Center(
                                              child: AnimatedOpacity(
                                                duration: const Duration(milliseconds: 180),
                                                opacity: _actionsOpen ? 0.28 : 1,
                                                child: Image.asset(
                                                  'assets/logo-escura.png',
                                                  height: 24,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                          ),
                                          AnimatedSize(
                                            duration: const Duration(milliseconds: 180),
                                            curve: Curves.easeOutCubic,
                                            alignment: Alignment.centerRight,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                AnimatedSwitcher(
                                                  duration: const Duration(milliseconds: 160),
                                                  switchInCurve: Curves.easeOutCubic,
                                                  switchOutCurve: Curves.easeInCubic,
                                                  transitionBuilder: (child, animation) {
                                                    return FadeTransition(
                                                      opacity: animation,
                                                      child: SizeTransition(
                                                        sizeFactor: animation,
                                                        axis: Axis.horizontal,
                                                        axisAlignment: 1,
                                                        child: child,
                                                      ),
                                                    );
                                                  },
                                                  child: _actionsOpen
                                                      ? Row(
                                                          key: const ValueKey('agenda-header-actions-open'),
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            _buildHeaderActionButton(
                                                              onPressed: () {
                                                                _closeHeaderMenu();
                                                                _openPeriodFilter();
                                                              },
                                                              icon: Icons.tune,
                                                            ),
                                                            _buildHeaderActionButton(
                                                              onPressed: () {
                                                                _closeHeaderMenu();
                                                                _openAuditorFilter();
                                                              },
                                                              icon: Icons.person_search,
                                                            ),
                                                            _buildHeaderActionButton(
                                                              onPressed: () {
                                                                _closeHeaderMenu();
                                                                _clearFilters();
                                                              },
                                                              icon: Icons.close,
                                                            ),
                                                          ],
                                                        )
                                                      : const SizedBox(
                                                          key: ValueKey('agenda-header-actions-closed'),
                                                          width: 0,
                                                        ),
                                                ),
                                                IconButton(
                                                  onPressed: _toggleHeaderMenu,
                                                  icon: Icon(
                                                    _actionsOpen
                                                        ? Icons.more_horiz_rounded
                                                        : Icons.more_vert_rounded,
                                                    color: const Color(0xFF7357D8),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const Text(
                                    'Agenda de auditorias',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: _brand,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Acompanhe as auditorias confirmadas e visualize a agenda por periodo ou auditora.',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      height: 1.6,
                                      color: _muted,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _InfoPill(icon: Icons.calendar_month, label: _rangeLabel()),
                                      _InfoPill(
                                        icon: Icons.person_search,
                                        label: data == null
                                            ? '0 auditoras'
                                            : '${_selectedAuditorPaths.length} auditoras',
                                      ),
                                    ],
                                  ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (grouped.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                              child: _AgendaEmptyState(),
                            )
                          else
                            ...grouped.entries.map(
                              (group) => Padding(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatHeaderDay(group.key),
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF9A9EAE),
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ...group.value.map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: _ConfirmedCard(entry: entry),
                                      ),
                                    ),
                                  ],
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF7357D8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF72778A),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmedCard extends StatelessWidget {
  const _ConfirmedCard({required this.entry});

  final ConfirmedAgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
          Text(
            entry.item.clientName,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1B1830),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Auditor: ${entry.item.auditorName ?? 'Nao informado'}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Color(0xFF72778A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            entry.clientAddress,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF72778A),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaEmptyState extends StatelessWidget {
  const _AgendaEmptyState();

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
      child: const Text(
        'Nenhuma auditoria confirmada encontrada para o periodo e auditoras selecionados.',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          height: 1.6,
          color: Color(0xFF72778A),
        ),
      ),
    );
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
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
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1B1830),
                        ),
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
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEEE9FF) : const Color(0xFFF6F6FA),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
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
                value,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF72778A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: checked ? const Color(0xFFA55AE9) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: checked ? null : Border.all(color: const Color(0xFFD7DAE5)),
      ),
      alignment: Alignment.center,
      child: checked
          ? const Text(
              '✓',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}
