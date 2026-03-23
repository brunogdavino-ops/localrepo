import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/login_page.dart';
import 'auditor_home_page.dart';
import 'home_page.dart';

class _EntryDiagnostics {
  const _EntryDiagnostics({
    required this.role,
    required this.projectId,
    required this.appId,
    required this.uid,
    required this.email,
    required this.tokenOk,
    required this.tokenError,
    required this.usersErrorCode,
    required this.usersErrorMessage,
    required this.clientsProbeOk,
    required this.clientsProbeError,
  });

  final String? role;
  final String projectId;
  final String appId;
  final String uid;
  final String? email;
  final bool tokenOk;
  final String? tokenError;
  final String? usersErrorCode;
  final String? usersErrorMessage;
  final bool clientsProbeOk;
  final String? clientsProbeError;

  bool get hasUsersReadError => usersErrorCode != null;
}

class HomeEntryPage extends StatelessWidget {
  const HomeEntryPage({super.key});

  Future<_EntryDiagnostics> _loadDiagnostics(User user) async {
    final firestore = FirebaseFirestore.instance;
    final app = Firebase.app();

    String? role;
    String? usersErrorCode;
    String? usersErrorMessage;
    bool tokenOk = false;
    String? tokenError;
    bool clientsProbeOk = false;
    String? clientsProbeError;

    try {
      await user.getIdToken(true);
      tokenOk = true;
    } catch (error) {
      tokenError = error.toString();
    }

    try {
      final snapshot = await firestore.collection('users').doc(user.uid).get();
      role = (snapshot.data()?['role'] as String?)?.trim().toLowerCase();
    } catch (error) {
      final firebaseError = error is FirebaseException ? error : null;
      usersErrorCode = firebaseError?.code ?? error.runtimeType.toString();
      usersErrorMessage = firebaseError?.message ?? error.toString();
    }

    try {
      await firestore.collection('clients').limit(1).get();
      clientsProbeOk = true;
    } catch (error) {
      final firebaseError = error is FirebaseException ? error : null;
      clientsProbeError =
          'code=${firebaseError?.code ?? error.runtimeType} message=${firebaseError?.message ?? error}';
    }

    debugPrint(
      '[HomeEntryPage] project=${app.options.projectId} appId=${app.options.appId} '
      'uid=${user.uid} email=${user.email} tokenOk=$tokenOk '
      'usersError=$usersErrorCode clientsProbeOk=$clientsProbeOk clientsProbeError=$clientsProbeError',
    );

    return _EntryDiagnostics(
      role: role,
      projectId: app.options.projectId,
      appId: app.options.appId,
      uid: user.uid,
      email: user.email,
      tokenOk: tokenOk,
      tokenError: tokenError,
      usersErrorCode: usersErrorCode,
      usersErrorMessage: usersErrorMessage,
      clientsProbeOk: clientsProbeOk,
      clientsProbeError: clientsProbeError,
    );
  }

  Widget _buildDiagnosticError(_EntryDiagnostics data) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFB3261E),
                  size: 30,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Falha ao ler o perfil do usuario',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B1830),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'projectId: ${data.projectId}\nappId: ${data.appId}\nuid: ${data.uid}\nemail: ${data.email ?? '-'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF72778A),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'tokenOk: ${data.tokenOk}${data.tokenError == null ? '' : '\n${data.tokenError}'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF72778A),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'users/{uid}: code=${data.usersErrorCode ?? '-'}\n${data.usersErrorMessage ?? '-'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF72778A),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'clients probe: ${data.clientsProbeOk ? 'ok' : data.clientsProbeError ?? 'falhou'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF72778A),
                    height: 1.5,
                  ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Diagnostico temporario habilitado para confirmar a causa real.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Color(0xFF9A9EAE),
                      height: 1.5,
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    return FutureBuilder<_EntryDiagnostics>(
      future: _loadDiagnostics(user),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFFF7F7FB),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF7357D8)),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          final message = snapshot.error?.toString() ?? 'Diagnostico indisponivel';
          return Scaffold(
            backgroundColor: const Color(0xFFF7F7FB),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Inter', color: Color(0xFF72778A)),
                ),
              ),
            ),
          );
        }

        final data = snapshot.data!;
        if (data.hasUsersReadError) {
          return _buildDiagnosticError(data);
        }

        if (data.role == 'admin') {
          return const HomePage();
        }
        return const AuditorHomePage();
      },
    );
  }
}
