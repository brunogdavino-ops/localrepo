import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_page.dart';
import '../clients/clients_page.dart';
import 'models/audit_model.dart';
import 'pages/audit_detail_page.dart';
import 'pages/new_audit_page.dart';
import 'services/audit_service.dart';

class AuditsPage extends StatefulWidget {
  const AuditsPage({Key? key}) : super(key: key);

  @override
  State<AuditsPage> createState() => _AuditsPageState();
}

class _AuditsPageState extends State<AuditsPage> {
  final AuditService _auditService = AuditService();
  final Map<String, Future<_AuditCardInfo>> _cardInfoCache = {};
  bool _isSigningOut = false;

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;

    setState(() {
      _isSigningOut = true;
    });

    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
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

  Future<_AuditCardInfo> _loadCardInfo(AuditModel audit) async {
    final clientSnapshot = await audit.clientRef.get();
    final clientData = clientSnapshot.data() as Map<String, dynamic>?;
    final clientName = (clientData?['name'] as String?)?.trim();

    final templateSnapshot = await audit.templateRef.get();
    final templateData = templateSnapshot.data() as Map<String, dynamic>?;
    final templateName =
        ((templateData?['name'] ?? templateData?['title']) as String?)?.trim();

    return _AuditCardInfo(
      clientName: (clientName == null || clientName.isEmpty)
          ? 'Cliente sem nome'
          : clientName,
      templateName: (templateName == null || templateName.isEmpty)
          ? 'Template'
          : templateName,
    );
  }

  Future<_AuditCardInfo> _getCardInfo(AuditModel audit) {
    return _cardInfoCache.putIfAbsent(audit.id, () => _loadCardInfo(audit));
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '--/--/----';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$day/$month/$year';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'Em andamento';
      case 'validation_pending':
        return 'Em Validação';
      case 'completed':
        return 'Concluída';
      default:
        return status;
    }
  }

  Color _statusBackgroundColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green.withValues(alpha: 0.12);
      case 'validation_pending':
        return const Color(0xFF3B82F6).withValues(alpha: 0.12);
      case 'in_progress':
        return Colors.amber.withValues(alpha: 0.15);
      default:
        return Colors.amber.withValues(alpha: 0.15);
    }
  }

  Color _statusTextColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'validation_pending':
        return const Color(0xFF3B82F6);
      case 'in_progress':
        return Colors.amber[800]!;
      default:
        return Colors.amber[800]!;
    }
  }

  Widget _buildAuditCard(BuildContext context, AuditModel audit) {
    return FutureBuilder<_AuditCardInfo>(
      future: _getCardInfo(audit),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: SizedBox(
              height: 98,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
            ),
          );
        }

        final info = snapshot.data ??
            const _AuditCardInfo(clientName: 'Cliente sem nome', templateName: 'Template');

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C1C1C1C),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AuditDetailPage(auditId: audit.id),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.clientName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1C1C1C),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${audit.formattedCode} - ${_formatDate(audit.startedAt)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: const Color(0xFF8A8FA3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusBackgroundColor(audit.status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(audit.status),
                        style: TextStyle(
                          color: _statusTextColor(audit.status),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width >= 900 ? width * 0.16 : (width >= 600 ? 24.0 : 16.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          'Auditorias',
          style: TextStyle(
            color: const Color(0xFF1C1C1C),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ClientsPage()),
              );
            },
            icon: const Icon(Icons.person_outline, color: Color(0xFF39306E)),
          ),
          IconButton(
            onPressed: _isSigningOut ? null : _handleSignOut,
            icon: const Icon(Icons.logout, color: Color(0xFF39306E)),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE6E6EF)),
        ),
      ),
      body: StreamBuilder<List<AuditModel>>(
        stream: _auditService.getUserAudits(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Erro ao carregar auditorias.',
                style: TextStyle(color: const Color(0xFF8A8FA3)),
              ),
            );
          }

          final audits = snapshot.data ?? const <AuditModel>[];
          if (audits.isEmpty) {
            return Center(
              child: Text(
                'Nenhuma auditoria encontrada.',
                style: TextStyle(color: const Color(0xFF8A8FA3)),
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 92),
            itemCount: audits.length,
            itemBuilder: (context, index) {
              return _buildAuditCard(context, audits[index]);
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF7262C2),
                borderRadius: BorderRadius.circular(16),
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
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NewAuditPage()),
                    );
                  },
                  child: Center(
                    child: Text(
                      'Nova auditoria',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditCardInfo {
  final String clientName;
  final String templateName;

  const _AuditCardInfo({
    required this.clientName,
    required this.templateName,
  });
}


