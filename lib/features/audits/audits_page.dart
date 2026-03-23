import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../home/home_entry_page.dart';
import 'models/audit_model.dart';
import 'pages/audit_detail_page.dart';
import 'pages/new_audit_page.dart';
import 'services/audit_service.dart';

class AuditsPage extends StatefulWidget {
  const AuditsPage({super.key});

  @override
  State<AuditsPage> createState() => _AuditsPageState();
}

class _AuditsPageState extends State<AuditsPage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _brandDark = Color(0xFF1B1830);
  static const Color _mutedColor = Color(0xFF72778A);

  final AuditService _auditService = AuditService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Map<String, Future<_AuditListItem>> _auditInfoCache = {};
  Future<List<_AuditListItem>>? _auditItemsFuture;
  String? _auditItemsSignature;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  Future<void> _openNewAudit() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NewAuditPage()));
  }

  void _openAuditDetail(AuditModel audit) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuditDetailPage(auditId: audit.id)),
    );
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeEntryPage()),
    );
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
      case 'completed':
        return 'Concluída';
      case 'in_progress':
      case 'draft':
        return 'Em andamento';
      default:
        return 'Em andamento';
    }
  }

  Color _statusBackgroundColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFFE8F7EF);
      case 'in_progress':
      case 'draft':
      default:
        return const Color(0xFFFFF3DF);
    }
  }

  Color _statusTextColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF22A861);
      case 'in_progress':
      case 'draft':
      default:
        return const Color(0xFFD9921A);
    }
  }

  String _formatTrailingMetric(AuditModel audit, double completionPercent) {
    if (audit.status == 'completed') {
      final score = audit.scoreFinal ?? audit.score;
      final scoreValue = score is num ? score.toDouble() : 0.0;
      return '${scoreValue.toStringAsFixed(1).replaceAll('.', ',')}% de score';
    }

    final rounded = completionPercent.round();
    return '$rounded% concluído';
  }

  Future<_AuditListItem> _loadAuditListItem(AuditModel audit) async {
    try {
      final clientSnapshot = await audit.clientRef.get();
      final clientData = clientSnapshot.data() as Map<String, dynamic>?;
      final clientName = (clientData?['name'] as String?)?.trim();

      final answersSnapshot = await FirebaseFirestore.instance
          .collection('audits')
          .doc(audit.id)
          .collection('answers')
          .get();

      final totalAnswers = answersSnapshot.docs.length;
      final answeredCount = answersSnapshot.docs.where((doc) {
        final data = doc.data();
        final response =
            ((data['response'] as String?) ?? (data['value'] as String?))
                ?.trim();
        return response != null && response.isNotEmpty;
      }).length;

      final completionPercent = totalAnswers == 0
          ? 0.0
          : (answeredCount / totalAnswers) * 100;

      return _AuditListItem(
        audit: audit,
        clientName: (clientName == null || clientName.isEmpty)
            ? 'Cliente sem nome'
            : clientName,
        completionPercent: completionPercent.clamp(0, 100),
      );
    } catch (error) {
      debugPrint('Failed to enrich audit ${audit.id}: $error');
      return _AuditListItem(
        audit: audit,
        clientName: 'Cliente indisponível',
        completionPercent: 0,
      );
    }
  }

  Future<_AuditListItem> _getAuditListItem(AuditModel audit) {
    return _auditInfoCache.putIfAbsent(
      audit.id,
      () => _loadAuditListItem(audit),
    );
  }

  Future<List<_AuditListItem>> _buildAuditItems(List<AuditModel> audits) {
    return Future.wait(audits.map(_getAuditListItem));
  }

  Future<List<_AuditListItem>> _resolveAuditItemsFuture(List<AuditModel> audits) {
    final signature = audits
        .map(
          (audit) =>
              '${audit.id}:${audit.status}:${audit.scoreFinal}:${audit.score}:${audit.startedAt?.millisecondsSinceEpoch}',
        )
        .join('|');

    if (_auditItemsFuture == null || _auditItemsSignature != signature) {
      _auditItemsSignature = signature;
      _auditItemsFuture = _buildAuditItems(audits);
    }

    return _auditItemsFuture!;
  }

  List<_AuditListItem> _applySearch(List<_AuditListItem> items, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return items;

    return items.where((item) {
      final clientName = item.clientName.toLowerCase();
      final code = item.audit.formattedCode.toLowerCase();
      return clientName.contains(query) || code.contains(query);
    }).toList(growable: false);
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
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
                  onPressed: _handleBack,
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
                onPressed: _openNewAudit,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFEEE9FF),
                  foregroundColor: _brandColor,
                  minimumSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.add_circle, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroBlock() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Minhas auditorias',
            style: _inter(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _brandColor,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              'Acompanhe auditorias em andamento, revise auditorias já realizadas ou inicie uma nova.',
              style: _inter(
                fontSize: 14,
                height: 1.6,
                color: _mutedColor,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F6FA),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F171A24),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: _inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _brandDark,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar auditoria ou cliente',
                hintStyle: _inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF9A9EAE),
                ),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF9A9EAE)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditCard(_AuditListItem item) {
    final audit = item.audit;

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
          onTap: () => _openAuditDetail(audit),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _statusBackgroundColor(audit.status),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusLabel(audit.status),
                              style: _inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _statusTextColor(audit.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${audit.formattedCode} • ${_formatDate(audit.startedAt)}',
                        style: _inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _mutedColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatTrailingMetric(audit, item.completionPercent),
                        style: _inter(
                          fontSize: 14,
                          height: 1.5,
                          color: _mutedColor,
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
                    color: const Color(0xFFEEE9FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: Color(0xFF7357D8),
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const HomeEntryPage();
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bgColor,
        body: Column(
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
                    _buildIntroBlock(),
                  ],
                ),
              ),
            ),
            Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, searchValue, _) {
                return StreamBuilder<List<AuditModel>>(
                  stream: _auditService.getUserAudits(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Erro ao carregar auditorias.',
                          style: _inter(color: _mutedColor),
                        ),
                      );
                    }

                    final audits = [...(snapshot.data ?? const <AuditModel>[])]
                      ..sort((a, b) {
                        final aNumber = a.auditNumber ?? -1;
                        final bNumber = b.auditNumber ?? -1;
                        return bNumber.compareTo(aNumber);
                      });

                    return FutureBuilder<List<_AuditListItem>>(
                      future: _resolveAuditItemsFuture(audits),
                      builder: (context, itemsSnapshot) {
                        final isLoadingItems =
                            itemsSnapshot.connectionState == ConnectionState.waiting;
                        final items = _applySearch(
                          itemsSnapshot.data ?? const [],
                          searchValue.text,
                        );

                        if (isLoadingItems) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (itemsSnapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                              child: Text(
                                'Erro ao montar a lista de auditorias.',
                                style: _inter(color: _mutedColor),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        if (items.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                              child: Text(
                                audits.isEmpty
                                    ? 'Nenhuma auditoria encontrada.'
                                    : 'Nenhum resultado para a busca.',
                                style: _inter(color: _mutedColor),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            return _buildAuditCard(items[index]);
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditListItem {
  final AuditModel audit;
  final String clientName;
  final double completionPercent;

  const _AuditListItem({
    required this.audit,
    required this.clientName,
    required this.completionPercent,
  });
}
