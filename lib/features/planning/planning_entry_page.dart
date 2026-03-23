import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_page.dart';
import 'auditor_agenda_page.dart';
import 'monthly_planning_page.dart';

class PlanningEntryPage extends StatelessWidget {
  const PlanningEntryPage({super.key});

  Future<_PlanningAccessResult> _resolveAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _PlanningAccessResult.unauthenticated();
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!snapshot.exists) {
        return _PlanningAccessResult.denied(
          uid: user.uid,
          message: 'Perfil do usuario nao encontrado em users/{uid}.',
        );
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final role = (data['role'] as String?)?.trim().toLowerCase();

      if (role == 'admin') {
        return _PlanningAccessResult.admin(uid: user.uid, role: role!);
      }
      if (role == 'auditoria') {
        return _PlanningAccessResult.auditoria(uid: user.uid, role: role!);
      }

      return _PlanningAccessResult.denied(
        uid: user.uid,
        role: role,
        message: 'Role sem acesso ao modulo de planejamento.',
      );
    } catch (error) {
      return _PlanningAccessResult.error(
        uid: user.uid,
        message: 'Nao foi possivel carregar o perfil do usuario.',
        details: error.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PlanningAccessResult>(
      future: _resolveAccess(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _PlanningEntryLoadingView();
        }

        final result = snapshot.data;
        if (result == null || result.isUnauthenticated) {
          return const LoginPage();
        }
        if (result.isAdmin) {
          return const MonthlyPlanningPage();
        }
        if (result.isAuditoria) {
          return const AuditorAgendaPage();
        }

        return _PlanningAccessFallbackView(result: result);
      },
    );
  }
}

class _PlanningAccessResult {
  final String state;
  final String? uid;
  final String? role;
  final String? message;
  final String? details;

  const _PlanningAccessResult._({
    required this.state,
    this.uid,
    this.role,
    this.message,
    this.details,
  });

  const _PlanningAccessResult.admin({
    required String uid,
    required String role,
  }) : this._(state: 'admin', uid: uid, role: role);

  const _PlanningAccessResult.auditoria({
    required String uid,
    required String role,
  }) : this._(state: 'auditoria', uid: uid, role: role);

  const _PlanningAccessResult.denied({
    required String uid,
    String? role,
    required String message,
  }) : this._(state: 'denied', uid: uid, role: role, message: message);

  const _PlanningAccessResult.error({
    required String uid,
    required String message,
    String? details,
  }) : this._(state: 'error', uid: uid, message: message, details: details);

  const _PlanningAccessResult.unauthenticated()
    : this._(state: 'unauthenticated');

  bool get isAdmin => state == 'admin';
  bool get isAuditoria => state == 'auditoria';
  bool get isUnauthenticated => state == 'unauthenticated';
}

class _PlanningEntryLoadingView extends StatelessWidget {
  const _PlanningEntryLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F7FB),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF7357D8)),
      ),
    );
  }
}

class _PlanningAccessFallbackView extends StatelessWidget {
  const _PlanningAccessFallbackView({required this.result});

  final _PlanningAccessResult result;

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF7357D8);
    const textColor = Color(0xFF72778A);
    final title = result.state == 'error' ? 'Erro ao carregar acesso' : 'Acesso negado';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
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
                            color: brandColor,
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
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F171A24),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 36,
                      color: brandColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF171A24),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      result.message ?? 'Seu perfil nao possui acesso ao modulo de planejamento.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        height: 1.6,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F6FA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'uid: ${result.uid ?? '-'}\nrole: ${result.role ?? '-'}${result.details == null ? '' : '\ndetalhes: ${result.details}'}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          height: 1.5,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
