import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audits/audits_page.dart';
import '../audits/pages/audit_fill_page.dart';
import '../audits/pages/new_audit_page.dart';
import '../audits/services/audit_creation_service.dart';
import '../auth/login_page.dart';
import '../clients/clients_page.dart';
import '../planning/models/monthly_plan_item.dart';
import '../planning/confirmed_agenda_page.dart';
import '../planning/planning_management_page.dart';
import '../planning/monthly_planning_page.dart';
import '../planning/services/monthly_planning_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _AdminPriorityType { approval, unscheduled, refused, overdue }

class _HomePageState extends State<HomePage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _softBrand = Color(0xFFEEE9FF);
  static const Color _overlayColor = Color(0x33171A24);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MonthlyPlanningService _planningService = MonthlyPlanningService();
  final AuditCreationService _auditCreationService = AuditCreationService();

  bool _isSigningOut = false;
  bool _isMenuOpen = false;
  String? _startingEntryId;
  Future<_AdminHomeData>? _homeFuture;

  @override
  void initState() {
    super.initState();
    _homeFuture = _loadHomeData();
  }

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

  String _greetingLabel(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String? _extractFirstName(Map<String, dynamic>? userData, User user) {
    final candidates = [
      userData?['name'],
      userData?['displayName'],
      user.displayName,
      user.email,
    ];

    for (final candidate in candidates) {
      final raw = (candidate as String?)?.trim();
      if (raw == null || raw.isEmpty) continue;
      final normalized = raw.split('@').first.trim();
      final firstName = normalized.split(RegExp(r'\s+')).first.trim();
      if (firstName.isNotEmpty) {
        return firstName;
      }
    }

    return null;
  }

  bool _isUnscheduled(MonthlyPlanItem item) {
    return !item.isPendingConfirmation &&
        !item.isConfirmedAgenda &&
        !item.isAdminRejectedAgenda &&
        !item.isUnavailableAgenda &&
        !item.isCancelled;
  }

  Future<_AdminHomeData> _loadHomeData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    Map<String, dynamic>? userData;
    DocumentReference? companyRef;
    try {
      final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
      userData = userSnapshot.data();
      companyRef = userData?['companyref'] as DocumentReference?;
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }
      // Keep the admin home usable even when users/{uid} is temporarily
      // blocked by Firestore rules. In this fallback we rely on Auth for the
      // greeting and skip company scoping when building the home data.
      userData = null;
      companyRef = null;
    }

    final firstName = _extractFirstName(userData, user);
    final today = DateTime.now();
    final startDate = DateTime(today.year, today.month, today.day);
    final endDate = startDate.add(const Duration(days: 6));
    final currentMonth = DateTime(today.year, today.month);
    final monthKey = formatMonthKey(currentMonth);

    Query<Map<String, dynamic>> monthItemsQuery = _firestore
        .collection('monthly_plans')
        .doc(monthKey)
        .collection('items')
        .where('status', whereIn: const ['planned', 'sent']);
    if (companyRef != null) {
      monthItemsQuery = monthItemsQuery.where('companyRef', isEqualTo: companyRef);
    }
    final monthItemsFuture = monthItemsQuery.get();
    final weekEntriesFuture = _planningService.loadAuditorConfirmedAgendaWeek(
      startDate: startDate,
      endDate: endDate,
      companyRef: companyRef,
    );
    final overdueEntriesFuture = _planningService.loadOverdueConfirmedAgendaEntries(
      referenceDate: startDate,
      companyRef: companyRef,
    );

    QuerySnapshot<Map<String, dynamic>>? monthItemsSnapshot;
    List<ConfirmedAgendaEntry> weekEntries = const [];
    List<ConfirmedAgendaEntry> overdueEntries = const [];

    try {
      monthItemsSnapshot = await monthItemsFuture;
    } catch (error) {
      debugPrint('Home admin: falha ao carregar monthItems: $error');
    }

    try {
      weekEntries = await weekEntriesFuture;
    } catch (error) {
      debugPrint('Home admin: falha ao carregar agenda semanal: $error');
    }

    try {
      overdueEntries = await overdueEntriesFuture;
    } catch (error) {
      debugPrint('Home admin: falha ao carregar auditorias em atraso: $error');
    }

    final monthItems = (monthItemsSnapshot?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        .map(MonthlyPlanItem.fromDocument)
        .where((item) => !item.isCancelled)
        .toList(growable: false);

    final pendingApprovalCount = monthItems
        .where((item) => item.isPendingConfirmation)
        .length;
    final unscheduledCount = monthItems
        .where(_isUnscheduled)
        .length;
    final refusedCount = monthItems
        .where(
          (item) => item.isAdminRejectedAgenda || item.isUnavailableAgenda,
        )
        .length;

    final priorities = <_AdminPriority>[
      if (pendingApprovalCount > 0)
        _AdminPriority(
          type: _AdminPriorityType.approval,
          label: 'Aguardando sua aprovação',
          count: pendingApprovalCount,
        ),
      if (unscheduledCount > 0)
        _AdminPriority(
          type: _AdminPriorityType.unscheduled,
          label: 'Sem agendamento',
          count: unscheduledCount,
        ),
      if (refusedCount > 0)
        _AdminPriority(
          type: _AdminPriorityType.refused,
          label: 'Auditoria recusada',
          count: refusedCount,
        ),
      if (overdueEntries.isNotEmpty)
        _AdminPriority(
          type: _AdminPriorityType.overdue,
          label: 'Auditorias em atraso',
          count: overdueEntries.length,
        ),
    ];

    return _AdminHomeData(
      firstName: firstName,
      priorities: priorities,
      weekEntries: weekEntries,
      overdueEntries: overdueEntries,
    );
  }

  Future<void> _reloadHome() async {
    setState(() {
      _homeFuture = _loadHomeData();
    });
    await _homeFuture;
  }

  Future<void> _handleLogout() async {
    if (_isSigningOut) return;

    setState(() {
      _isSigningOut = true;
    });

    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });
  }

  void _closeMenu() {
    if (!_isMenuOpen) return;
    setState(() {
      _isMenuOpen = false;
    });
  }

  Future<void> _openPage(Widget page) async {
    _closeMenu();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    await _reloadHome();
  }

  Future<void> _openPriority(
    _AdminPriority priority,
    _AdminHomeData data,
  ) async {
    switch (priority.type) {
      case _AdminPriorityType.approval:
        await _openPage(
          const PlanningManagementPage(
            initialFocusSection: PlanningManagementFocusSection.validation,
          ),
        );
        break;
      case _AdminPriorityType.unscheduled:
        await _openPage(
          const PlanningManagementPage(
            initialFocusSection: PlanningManagementFocusSection.unscheduled,
          ),
        );
        break;
      case _AdminPriorityType.refused:
        await _openPage(
          const PlanningManagementPage(
            initialFocusSection: PlanningManagementFocusSection.refused,
          ),
        );
        break;
      case _AdminPriorityType.overdue:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _OverdueAuditsPage(entries: data.overdueEntries),
          ),
        );
        if (!mounted) return;
        await _reloadHome();
        break;
    }
  }

  Future<void> _startAuditFromEntry(ConfirmedAgendaEntry entry) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _startingEntryId == entry.item.id) return;

    setState(() => _startingEntryId = entry.item.id);
    try {
      final auditId = await _auditCreationService.createOrReuseAudit(
        uid: user.uid,
        clientRef: entry.item.clientRef,
        chosenDate: entry.item.confirmedDate!,
        draft: false,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AuditFillPage(auditId: auditId)),
      );
      if (!mounted) return;
      await _reloadHome();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível iniciar esta auditoria.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _startingEntryId = null);
      }
    }
  }

  Map<DateTime, List<ConfirmedAgendaEntry>> _groupWeekEntries(
    List<ConfirmedAgendaEntry> entries,
  ) {
    final grouped = <DateTime, List<ConfirmedAgendaEntry>>{};
    for (final entry in entries) {
      final date = DateTime(
        entry.item.confirmedDate!.year,
        entry.item.confirmedDate!.month,
        entry.item.confirmedDate!.day,
      );
      grouped.putIfAbsent(date, () => <ConfirmedAgendaEntry>[]).add(entry);
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  String _formatHeaderDay(DateTime date) {
    const weekdays = [
      'Domingo',
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
    ];
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    return '${weekdays[date.weekday % 7]}, ${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    final greeting = _greetingLabel(DateTime.now());

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bgColor,
        body: Stack(
          children: [
            FutureBuilder<_AdminHomeData>(
              future: _homeFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: _brandColor),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Não foi possível carregar a home do admin.',
                        textAlign: TextAlign.center,
                        style: _inter(fontSize: 14, color: _mutedColor),
                      ),
                    ),
                  );
                }

                final data = snapshot.data!;
                final title = (data.firstName == null || data.firstName!.isEmpty)
                    ? '$greeting!'
                    : '$greeting, ${data.firstName}!';
                final groupedEntries = _groupWeekEntries(data.weekEntries);

                return RefreshIndicator(
                  onRefresh: _reloadHome,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: double.infinity,
                          color: Colors.white,
                          child: SafeArea(
                            bottom: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: SizedBox(
                                    height: 60,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
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
                                            onPressed: _toggleMenu,
                                            style: IconButton.styleFrom(
                                              backgroundColor: _softBrand,
                                              foregroundColor: _brandColor,
                                              minimumSize: const Size(32, 32),
                                              padding: EdgeInsets.zero,
                                            ),
                                            icon: Icon(
                                              _isMenuOpen ? Icons.close : Icons.menu,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: _inter(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: _brandColor,
                                          letterSpacing: -0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 300),
                                        child: Text(
                                          'Tudo o que precisa da sua atenção, em um só lugar',
                                          style: _inter(
                                            fontSize: 14,
                                            height: 1.6,
                                            color: _mutedColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _PrioritiesCard(
                                priorities: data.priorities,
                                onPriorityTap: (priority) => _openPriority(priority, data),
                              ),
                              const SizedBox(height: 16),
                              _AdminPrimaryActionCard(
                                title: 'Nova auditoria',
                                description:
                                    'Inicie uma nova auditoria e preencha o checklist de avaliação.',
                                onTap: () => _openPage(const NewAuditPage()),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                'Sua agenda da semana',
                                style: _inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF9A9EAE),
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (groupedEntries.isEmpty)
                                const _AdminEmptyAgendaCard(
                                  message:
                                      'Nenhuma auditoria confirmada para os próximos dias.',
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x0F171A24),
                                        blurRadius: 28,
                                        offset: Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: groupedEntries.entries
                                        .map(
                                          (group) => Padding(
                                            padding: const EdgeInsets.only(bottom: 16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                    left: 4,
                                                    bottom: 8,
                                                  ),
                                                  child: Text(
                                                    _formatHeaderDay(group.key),
                                                    style: _inter(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: const Color(0xFF9A9EAE),
                                                      letterSpacing: 1.0,
                                                    ),
                                                  ),
                                                ),
                                                ...group.value.map(
                                                  (entry) => Padding(
                                                    padding: const EdgeInsets.only(bottom: 12),
                                                    child: _AdminWeekAgendaCard(
                                                      entry: entry,
                                                      isStarting:
                                                          _startingEntryId ==
                                                              entry.item.id,
                                                      onTap: () =>
                                                          _startAuditFromEntry(
                                                        entry,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            IgnorePointer(
              ignoring: !_isMenuOpen,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _isMenuOpen ? 1 : 0,
                child: GestureDetector(
                  onTap: _closeMenu,
                  child: Container(color: _overlayColor),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              right: _isMenuOpen ? 0 : -306,
              child: _HomeSideMenu(
                isSigningOut: _isSigningOut,
                onClose: _closeMenu,
                onTapGestao: () => _openPage(const PlanningManagementPage()),
                onTapPlanejamentoMensal: () => _openPage(const MonthlyPlanningPage()),
                onTapClientes: () => _openPage(const ClientsPage()),
                onTapAuditorias: () => _openPage(const AuditsPage()),
                onTapAgenda: () => _openPage(const ConfirmedAgendaPage()),
                onTapLogout: () async {
                  _closeMenu();
                  await _handleLogout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminHomeData {
  const _AdminHomeData({
    required this.firstName,
    required this.priorities,
    required this.weekEntries,
    required this.overdueEntries,
  });

  final String? firstName;
  final List<_AdminPriority> priorities;
  final List<ConfirmedAgendaEntry> weekEntries;
  final List<ConfirmedAgendaEntry> overdueEntries;
}

class _AdminPriority {
  const _AdminPriority({
    required this.type,
    required this.label,
    required this.count,
  });

  final _AdminPriorityType type;
  final String label;
  final int count;
}

class _PrioritiesCard extends StatelessWidget {
  const _PrioritiesCard({
    required this.priorities,
    required this.onPriorityTap,
  });

  final List<_AdminPriority> priorities;
  final ValueChanged<_AdminPriority> onPriorityTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prioridades de hoje',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: Color(0xFF9A9EAE),
            ),
          ),
          if (priorities.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Está tudo em ordem por aqui',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF72778A),
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFCFCFE),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFEEEEF5)),
              ),
              child: Column(
                children: List.generate(priorities.length, (index) {
                  final priority = priorities[index];
                  return Column(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(index == 0 ? 18 : 0),
                            bottom: Radius.circular(
                              index == priorities.length - 1 ? 18 : 0,
                            ),
                          ),
                          onTap: () => onPriorityTap(priority),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    priority.label,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      color: Color(0xFF72778A),
                                    ),
                                  ),
                                ),
                                Text(
                                  priority.count.toString(),
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF7357D8),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: Color(0xFF9A9EAE),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (index != priorities.length - 1)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(height: 1, color: Color(0xFFEEEEF5)),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminPrimaryActionCard extends StatelessWidget {
  const _AdminPrimaryActionCard({
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF8568E6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A5A3E8E),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.84),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_circle,
                    color: Colors.white,
                    size: 18,
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

class _AdminWeekAgendaCard extends StatelessWidget {
  const _AdminWeekAgendaCard({
    required this.entry,
    required this.isStarting,
    required this.onTap,
  });

  final ConfirmedAgendaEntry entry;
  final bool isStarting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6FA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isStarting ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.item.clientName,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: Color(0xFF1B1830),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.clientAddress,
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
                const SizedBox(width: 12),
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEEE9FF),
                    shape: BoxShape.circle,
                  ),
                  child: isStarting
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF7357D8),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF7357D8),
                          size: 18,
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

class _AdminEmptyAgendaCard extends StatelessWidget {
  const _AdminEmptyAgendaCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
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

class _HomeSideMenu extends StatelessWidget {
  const _HomeSideMenu({
    required this.isSigningOut,
    required this.onClose,
    required this.onTapGestao,
    required this.onTapPlanejamentoMensal,
    required this.onTapClientes,
    required this.onTapAuditorias,
    required this.onTapAgenda,
    required this.onTapLogout,
  });

  final bool isSigningOut;
  final VoidCallback onClose;
  final VoidCallback onTapGestao;
  final VoidCallback onTapPlanejamentoMensal;
  final VoidCallback onTapClientes;
  final VoidCallback onTapAuditorias;
  final VoidCallback onTapAgenda;
  final VoidCallback onTapLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 286,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFEEEEF5))),
        boxShadow: [
          BoxShadow(
            color: Color(0x24171A24),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SafeArea(
              bottom: false,
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Menu',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: Color(0xFF9A9EAE),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Acessos rápidos',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                            color: Color(0xFF1B1830),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
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
            ),
            const SizedBox(height: 24),
            _MenuEntry(
              icon: Icons.calendar_month,
              label: 'Gestão',
              onTap: onTapGestao,
            ),
            const SizedBox(height: 10),
            _MenuEntry(
              icon: Icons.event_note_outlined,
              label: 'Planejamento mensal',
              onTap: onTapPlanejamentoMensal,
            ),
            const SizedBox(height: 10),
            _MenuEntry(
              icon: Icons.groups_outlined,
              label: 'Clientes',
              onTap: onTapClientes,
            ),
            const SizedBox(height: 10),
            _MenuEntry(
              icon: Icons.assignment_outlined,
              label: 'Auditorias',
              onTap: onTapAuditorias,
            ),
            const SizedBox(height: 10),
            _MenuEntry(
              icon: Icons.event_outlined,
              label: 'Agenda',
              onTap: onTapAgenda,
            ),
            const SizedBox(height: 10),
            _MenuEntry(
              icon: Icons.logout,
              label: 'Logout',
              onTap: isSigningOut ? null : onTapLogout,
              trailing: isSigningOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7357D8)),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Colors.white;
    const foregroundColor = Color(0xFF34384A);
    const iconColor = Color(0xFF7357D8);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F171A24),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: foregroundColor,
                    ),
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: const Color(0xFF9A9EAE),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverdueAuditsPage extends StatelessWidget {
  const _OverdueAuditsPage({required this.entries});

  final List<ConfirmedAgendaEntry> entries;

  String _formatDate(DateTime date) {
    const weekdays = [
      'Domingo',
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
    ];
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    return '${weekdays[date.weekday % 7]}, ${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year.toString().substring(2)}';
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
        backgroundColor: const Color(0xFFF7F7FB),
        body: ListView(
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
                                icon: const Icon(
                                  Icons.chevron_left,
                                  color: Color(0xFF7357D8),
                                  size: 28,
                                ),
                              ),
                            ),
                            Center(
                              child: Image.asset(
                                'assets/logo-escura.png',
                                height: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Auditorias em atraso',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7357D8),
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ocorrências confirmadas há mais de 3 dias, sem auditoria iniciada depois da data prevista.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          height: 1.6,
                          color: Color(0xFF72778A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: entries.isEmpty
                  ? Container(
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
                      child: const Text(
                        'Nenhuma auditoria em atraso no momento.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          height: 1.6,
                          color: Color(0xFF72778A),
                        ),
                      ),
                    )
                  : Column(
                      children: entries
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.item.clientName,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF171A24),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      entry.clientAddress,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        height: 1.5,
                                        color: Color(0xFF72778A),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Data confirmada: ${_formatDate(entry.item.confirmedDate!)}',
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF7357D8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
