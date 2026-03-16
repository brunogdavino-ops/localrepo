import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audits/audits_page.dart';
import '../audits/pages/new_audit_page.dart';
import '../auth/login_page.dart';
import '../clients/clients_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _brandDark = Color(0xFF171A24);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _softBrand = Color(0xFFEEE9FF);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSigningOut = false;

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

  Future<String?> _loadFirstName(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    return _extractFirstName(snapshot.data(), FirebaseAuth.instance.currentUser!);
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

  void _openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
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
        body: FutureBuilder<String?>(
          future: _loadFirstName(user.uid),
          builder: (context, snapshot) {
            final firstName = snapshot.data?.trim();
            final title = (firstName == null || firstName.isEmpty)
                ? '$greeting!'
                : '$greeting, $firstName!';

            return SingleChildScrollView(
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
                          Container(
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
                          Container(
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
                                    'Gerencie auditorias e clientes a partir dos acessos abaixo.',
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
                      children: [
                        _HomeActionCard(
                          backgroundColor: _brandColor,
                          titleColor: Colors.white,
                          descriptionColor: Colors.white.withValues(alpha: 0.82),
                          iconBackgroundColor: Colors.white.withValues(alpha: 0.16),
                          iconColor: Colors.white,
                          icon: Icons.add_circle,
                          title: 'Nova auditoria',
                          description:
                              'Inicie uma nova auditoria e siga o fluxo de avaliação.',
                          onTap: () => _openPage(const NewAuditPage()),
                        ),
                        const SizedBox(height: 16),
                        _HomeActionCard(
                          backgroundColor: Colors.white,
                          titleColor: _brandDark,
                          descriptionColor: _mutedColor,
                          iconBackgroundColor: _softBrand,
                          iconColor: _brandColor,
                          icon: Icons.calendar_month,
                          title: 'Minhas auditorias',
                          description:
                              'Acompanhe auditorias em andamento ou revise auditorias já realizadas.',
                          onTap: () => _openPage(const AuditsPage()),
                        ),
                        const SizedBox(height: 16),
                        _HomeActionCard(
                          backgroundColor: Colors.white,
                          titleColor: _brandDark,
                          descriptionColor: _mutedColor,
                          iconBackgroundColor: _softBrand,
                          iconColor: _brandColor,
                          icon: Icons.person,
                          title: 'Clientes',
                          description:
                              'Visualize os clientes cadastrados ou adicione novos à plataforma.',
                          onTap: () => _openPage(const ClientsPage()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  final Color backgroundColor;
  final Color titleColor;
  final Color descriptionColor;
  final Color iconBackgroundColor;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _HomeActionCard({
    required this.backgroundColor,
    required this.titleColor,
    required this.descriptionColor,
    required this.iconBackgroundColor,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBackgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 16),
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
                        ).copyWith(color: titleColor),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          height: 1.5,
                        ).copyWith(color: descriptionColor),
                      ),
                    ],
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
