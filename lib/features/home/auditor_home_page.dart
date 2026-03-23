import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audits/audits_page.dart';
import '../audits/pages/audit_fill_page.dart';
import '../audits/pages/new_audit_page.dart';
import '../audits/services/audit_creation_service.dart';
import '../auth/login_page.dart';
import '../planning/auditor_agenda_page.dart';
import '../planning/models/monthly_plan_item.dart';
import '../planning/services/monthly_planning_service.dart';

class AuditorHomePage extends StatefulWidget {
  const AuditorHomePage({super.key});

  @override
  State<AuditorHomePage> createState() => _AuditorHomePageState();
}

class _AuditorHomePageState extends State<AuditorHomePage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _softBrand = Color(0xFFEEE9FF);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MonthlyPlanningService _planningService = MonthlyPlanningService();
  final AuditCreationService _auditCreationService = AuditCreationService();
  bool _isSigningOut = false;
  String? _startingEntryId;
  Future<_AuditorHomeData>? _homeFuture;

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

  String? _extractFirstName(User user, Map<String, dynamic>? userData) {
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

  Future<_AuditorHomeData> _loadHomeData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuária não autenticada.');
    }

    Map<String, dynamic>? userData;
    try {
      final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
      userData = userSnapshot.data();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }
      // Keep the auditor home usable even when users/{uid} is blocked by
      // Firestore rules. In that case we fall back to Firebase Auth data.
      userData = null;
    }

    final firstName = _extractFirstName(user, userData);
    final today = DateTime.now();
    final startDate = DateTime(today.year, today.month, today.day);
    final endDate = startDate.add(const Duration(days: 6));
    final weekEntries = await _planningService.loadAuditorConfirmedAgendaWeek(
      startDate: startDate,
      endDate: endDate,
    );

    return _AuditorHomeData(
      firstName: firstName,
      weekEntries: weekEntries,
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
    setState(() => _isSigningOut = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    await _reloadHome();
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
        body: FutureBuilder<_AuditorHomeData>(
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
                    'Não foi possível carregar a home da auditora.',
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
                                        onPressed: _isSigningOut ? null : _handleLogout,
                                        style: IconButton.styleFrom(
                                          backgroundColor: _softBrand,
                                          foregroundColor: _brandColor,
                                          minimumSize: const Size(32, 32),
                                          padding: EdgeInsets.zero,
                                        ),
                                        icon: _isSigningOut
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(Icons.logout, size: 18),
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
                                    constraints: const BoxConstraints(maxWidth: 320),
                                    child: Text(
                                      'Acompanhe sua agenda, inicie auditorias e navegue pelos acessos principais.',
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
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                              Expanded(
                                child: _AuditorMiniActionCard(
                                  icon: Icons.calendar_month_outlined,
                                  title: 'Agenda mensal',
                                  description:
                                      'Consulte o que já foi enviado para você.',
                                  onTap: () => _openPage(const AuditorAgendaPage()),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _AuditorMiniActionCard(
                                  icon: Icons.assignment_outlined,
                                  title: 'Minhas auditorias',
                                  description:
                                      'Acesse suas auditorias em andamento.',
                                  onTap: () => _openPage(const AuditsPage()),
                                ),
                              ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _AuditorPrimaryActionCard(
                            icon: Icons.add_circle,
                            title: 'Nova auditoria',
                            description:
                                'Inicie uma nova auditoria escolhendo cliente e data.',
                            onTap: () => _openPage(const NewAuditPage()),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Agenda da semana',
                            style: _inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF9A9EAE),
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (groupedEntries.isEmpty)
                            const _AuditorEmptyAgendaCard(
                              message:
                                  'Nenhuma auditoria confirmada para os próximos dias.',
                            )
                          else
                            ...groupedEntries.entries.map(
                              (group) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4, bottom: 8),
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
                                        child: _AuditorWeekAgendaCard(
                                          entry: entry,
                                          isStarting: _startingEntryId == entry.item.id,
                                          onTap: () => _startAuditFromEntry(entry),
                                        ),
                                      ),
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
          },
        ),
      ),
    );
  }
}

class _AuditorHomeData {
  const _AuditorHomeData({
    required this.firstName,
    required this.weekEntries,
  });

  final String? firstName;
  final List<ConfirmedAgendaEntry> weekEntries;
}

class _AuditorMiniActionCard extends StatelessWidget {
  const _AuditorMiniActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          color: Color(0xFF171A24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEEE9FF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: const Color(0xFF7357D8),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
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
    );
  }
}

class _AuditorPrimaryActionCard extends StatelessWidget {
  const _AuditorPrimaryActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF7357D8),
        borderRadius: BorderRadius.circular(22),
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
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.84),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditorWeekAgendaCard extends StatelessWidget {
  const _AuditorWeekAgendaCard({
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: isStarting ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEEE9FF),
                    shape: BoxShape.circle,
                  ),
                  child: isStarting
                      ? const Padding(
                          padding: EdgeInsets.all(10),
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
                          size: 22,
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

class _AuditorEmptyAgendaCard extends StatelessWidget {
  const _AuditorEmptyAgendaCard({required this.message});

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
