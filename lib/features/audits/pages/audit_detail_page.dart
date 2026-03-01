import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/audit_model.dart';
import 'audit_fill_page.dart';
import '../widgets/gradient_button.dart';
import '../widgets/status_badge.dart';

class AuditDetailPage extends StatefulWidget {
  final String auditId;

  const AuditDetailPage({Key? key, required this.auditId}) : super(key: key);

  @override
  State<AuditDetailPage> createState() => _AuditDetailPageState();
}

class _AuditDetailPageState extends State<AuditDetailPage> {
  late final Future<_AuditDetailData> _detailFuture;
  String? _loadedAuditStatus;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadAuditDetails();
  }

  Future<_AuditDetailData> _loadAuditDetails() async {
    final firestore = FirebaseFirestore.instance;

    final auditDoc = await firestore.collection('audits').doc(widget.auditId).get();
    if (!auditDoc.exists) {
      throw StateError('Auditoria nao encontrada.');
    }

    final audit = AuditModel.fromDocument(auditDoc);
    _loadedAuditStatus = audit.status;
    final answersSnapshot = await auditDoc.reference.collection('answers').get();
    final questionsSnapshot = await firestore
        .collection('questions')
        .where('templateRef', isEqualTo: audit.templateRef)
        .get();
    final questions = questionsSnapshot.docs;
    final answers = answersSnapshot.docs.map((doc) => doc.data()).toList(growable: false);
    int compliantCount = 0;
    int nonCompliantCount = 0;
    for (final answer in answers) {
      final response = answer['response'];
      if (response == 'compliant') compliantCount++;
      if (response == 'non_compliant') nonCompliantCount++;
    }
    final int evaluatedCount = compliantCount + nonCompliantCount;
    final double overallScore = _calculateWeightedScore(answers, questionsSnapshot.docs);

    final clientRef = audit.clientRef;
    String clientName = 'Cliente sem nome';
    final clientSnapshot = await clientRef.get();
    final clientData = clientSnapshot.data() as Map<String, dynamic>?;
    final name = (clientData?['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      clientName = name;
    }

    final Map<String, _CategoryGroupBuilder> grouped = {};

    for (final answerDoc in answersSnapshot.docs) {
      final answerData = answerDoc.data();
      final questionRef = answerData['questionRef'] as DocumentReference?;
      if (questionRef == null) continue;

      final questionSnapshot = await questionRef.get();
      if (!questionSnapshot.exists) continue;

      final questionData = questionSnapshot.data() as Map<String, dynamic>;
      final categoryRef = questionData['categoryRef'] as DocumentReference?;
      if (categoryRef == null) continue;

      final categorySnapshot = await categoryRef.get();
      if (!categorySnapshot.exists) continue;

      final categoryData = categorySnapshot.data() as Map<String, dynamic>;
      final categoryId = categorySnapshot.id;

      final builder = grouped.putIfAbsent(
        categoryId,
        () => _CategoryGroupBuilder(
          categoryRefPath: categorySnapshot.reference.path,
          categoryName: (categoryData['name'] as String?) ?? 'Sem categoria',
          categoryOrder: (categoryData['order'] as num?)?.toInt() ?? 999999,
        ),
      );

      builder.items.add(
        _QuestionAnswerItem(
          questionText: (questionData['text'] as String?) ?? 'Pergunta sem texto',
          questionOrder: (questionData['order'] as num?)?.toInt() ?? 999999,
          value: (answerData['value'] as String?) ?? '-',
          weight: answerData['weight'],
        ),
      );
    }

    final groups = grouped.values.map((builder) {
      builder.items.sort((a, b) => a.questionOrder.compareTo(b.questionOrder));
      return _CategoryGroup(
        categoryRefPath: builder.categoryRefPath,
        categoryName: builder.categoryName,
        categoryOrder: builder.categoryOrder,
        categoryScore: _calculateCategoryWeightedScore(
          builder.categoryRefPath,
          questions,
          answers,
        ),
        items: builder.items,
      );
    }).toList();

    groups.sort((a, b) => a.categoryOrder.compareTo(b.categoryOrder));

    final int totalItems = groups.fold<int>(0, (sum, group) => sum + group.items.length);
    final int completedItems = groups.fold<int>(
      0,
      (sum, group) => sum + group.items.where((item) => item.isAnswered).length,
    );

    return _AuditDetailData(
      clientName: clientName,
      formattedCode: audit.formattedCode,
      status: audit.status,
      score: audit.score,
      compliantCount: compliantCount,
      nonCompliantCount: nonCompliantCount,
      evaluatedCount: evaluatedCount,
      overallScore: overallScore,
      startedAt: audit.startedAt,
      groups: groups,
      totalItems: totalItems,
      completedItems: completedItems,
    );
  }

  double _calculateWeightedScore(
    List answers,
    List questions,
  ) {
    double totalEvaluatedWeight = 0;
    double totalCompliantWeight = 0;

    for (final answer in answers) {
      final response = answer['response'];
      if (response != 'compliant' && response != 'non_compliant') continue;

      final answerQuestionRef = answer['questionRef'] as DocumentReference?;
      QueryDocumentSnapshot<Map<String, dynamic>>? question;
      for (final q in questions) {
        final questionDoc = q as QueryDocumentSnapshot<Map<String, dynamic>>;
        if (questionDoc.reference.path == answerQuestionRef?.path) {
          question = questionDoc;
          break;
        }
      }

      final weightValue = question?.data()['weight'];
      final weight = weightValue is num ? weightValue.toDouble() : 1.0;

      totalEvaluatedWeight += weight;

      if (response == 'compliant') {
        totalCompliantWeight += weight;
      }
    }

    if (totalEvaluatedWeight == 0) return 0.0;

    final score = (totalCompliantWeight / totalEvaluatedWeight) * 100;
    return double.parse(score.toStringAsFixed(1));
  }

  double _calculateCategoryWeightedScore(
    String categoryRef,
    List questions,
    List answers,
  ) {
    double totalEvaluatedWeight = 0;
    double totalCompliantWeight = 0;

    for (final questionDoc in questions) {
      final question = questionDoc as QueryDocumentSnapshot<Map<String, dynamic>>;
      final questionData = question.data();
      final questionCategoryRef = questionData['categoryRef'] as DocumentReference?;
      if (questionCategoryRef?.path != categoryRef) continue;

      Map<String, dynamic>? answer;
      for (final a in answers) {
        final answerData = a as Map<String, dynamic>;
        final answerQuestionRef = answerData['questionRef'] as DocumentReference?;
        if (answerQuestionRef?.path == question.reference.path) {
          answer = answerData;
          break;
        }
      }

      if (answer == null) continue;

      final response = answer['response'];
      if (response != 'compliant' && response != 'non_compliant') continue;

      final weightValue = questionData['weight'];
      final weight = weightValue is num ? weightValue.toDouble() : 1.0;

      totalEvaluatedWeight += weight;

      if (response == 'compliant') {
        totalCompliantWeight += weight;
      }
    }

    if (totalEvaluatedWeight == 0) return 0.0;

    final score = (totalCompliantWeight / totalEvaluatedWeight) * 100;
    return double.parse(score.toStringAsFixed(1));
  }

  bool _canContinueEditing(String? status) {
    return status == 'draft' || status == 'in_progress';
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

  void _handleContinueEditing([String? status]) {
    final currentStatus = status ?? _loadedAuditStatus;
    if (!_canContinueEditing(currentStatus)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auditoria em validacao')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuditFillPage(auditId: widget.auditId),
      ),
    );
  }

  void _handleGeneratePdf() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Geracao de PDF sera habilitada nesta tela.')),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '--/--/----';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$day/$month/$year';
  }

  IconData _valueIcon(String value) {
    switch (value) {
      case 'compliant':
        return Icons.check_circle;
      case 'non_compliant':
        return Icons.cancel;
      case 'not_applicable':
        return Icons.remove_circle;
      default:
        return Icons.help_outline;
    }
  }

  Color _valueColor(String value) {
    switch (value) {
      case 'compliant':
        return const Color(0xFF16A34A);
      case 'non_compliant':
        return const Color(0xFFDC2626);
      case 'not_applicable':
        return const Color(0xFF8A8FA3);
      default:
        return const Color(0xFF8A8FA3);
    }
  }

  Widget _buildProgressBar(double progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFFE3E3EC),
            borderRadius: BorderRadius.circular(999),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6D4BC3), Color(0xFF5A3E8E)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress * 100).round()}% concluido',
          style: TextStyle(
            fontSize: 12,
            color: const Color(0xFF8A8FA3),
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection(_CategoryGroup group) {
    final int total = group.items.length;
    final int filled = group.items.where((item) => item.isAnswered).length;
    final bool completed = total > 0 && filled == total;

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFE6E6EF), width: 1),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(vertical: 8),
          childrenPadding: const EdgeInsets.only(bottom: 10),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      group.categoryName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF39306E),
                      ),
                    ),
                  ),
                  StatusBadge(
                    label: completed ? 'Concluida' : 'Pendente',
                    type: completed ? StatusBadgeType.completed : StatusBadgeType.pending,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$filled de $total itens preenchidos',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A8FA3),
                    ),
                  ),
                  Text(
                    '${group.categoryScore.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6D4BC3),
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: group.items.map((item) {
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(
                item.questionText,
                style: TextStyle(
                  fontSize: 13.5,
                  color: const Color(0xFF1C1C1C),
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                '${item.value} - Peso ${item.weight ?? '-'}',
                style: TextStyle(
                  fontSize: 12,
                  color: const Color(0xFF8A8FA3),
                ),
              ),
              trailing: Icon(
                _valueIcon(item.value),
                color: _valueColor(item.value),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width >= 900 ? width * 0.16 : (width >= 600 ? 24.0 : 20.0);
    const primaryPurpleColor = Color(0xFF6D4BC3);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F5F5),
        surfaceTintColor: const Color(0xFFF6F5F5),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF39306E)),
        ),
        actions: [
          IconButton(
            onPressed: _handleGeneratePdf,
            icon: const Icon(
              Icons.insert_drive_file_outlined,
              color: Color(0xFF39306E),
            ),
          ),
          IconButton(
            onPressed: () => _handleContinueEditing(_loadedAuditStatus),
            icon: Icon(
              Icons.edit_outlined,
              color: _canContinueEditing(_loadedAuditStatus)
                  ? const Color(0xFF39306E)
                  : const Color(0xFF8A8FA3),
            ),
          ),
        ],
      ),
      body: FutureBuilder<_AuditDetailData>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Erro ao carregar auditoria.',
                style: TextStyle(color: const Color(0xFF8A8FA3)),
              ),
            );
          }

          final detail = snapshot.data;
          if (detail == null) {
            return Center(
              child: Text(
                'Dados da auditoria indisponiveis.',
                style: TextStyle(color: const Color(0xFF8A8FA3)),
              ),
            );
          }

          final double progress = detail.totalItems == 0
              ? 0
              : detail.completedItems / detail.totalItems;
          final bool canSend = progress >= 1.0;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 18),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.clientName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1C1C1C),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '${detail.overallScore.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: primaryPurpleColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${detail.compliantCount} conformes • ${detail.nonCompliantCount} nao conformes',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${detail.formattedCode} - ${_formatDate(detail.startedAt)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: const Color(0xFF8A8FA3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Status: ${_statusLabel(detail.status)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFF8A8FA3),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildProgressBar(progress),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...detail.groups.map(_buildCategorySection),
                  ],
                ),
              ),
              Container(
                color: const Color(0xFFF6F5F5),
                padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GradientButton(
                      text: 'Salvar progresso',
                      useGradient: false,
                      enabled: true,
                      onPressed: () {},
                    ),
                    const SizedBox(height: 12),
                    GradientButton(
                      text: 'Enviar para validacao',
                      useGradient: true,
                      enabled: canSend,
                      onPressed: canSend ? () {} : null,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AuditDetailData {
  final String clientName;
  final String formattedCode;
  final String status;
  final dynamic score;
  final int compliantCount;
  final int nonCompliantCount;
  final int evaluatedCount;
  final double overallScore;
  final DateTime? startedAt;
  final List<_CategoryGroup> groups;
  final int totalItems;
  final int completedItems;

  const _AuditDetailData({
    required this.clientName,
    required this.formattedCode,
    required this.status,
    required this.score,
    required this.compliantCount,
    required this.nonCompliantCount,
    required this.evaluatedCount,
    required this.overallScore,
    required this.startedAt,
    required this.groups,
    required this.totalItems,
    required this.completedItems,
  });
}

class _CategoryGroup {
  final String categoryRefPath;
  final String categoryName;
  final int categoryOrder;
  final double categoryScore;
  final List<_QuestionAnswerItem> items;

  const _CategoryGroup({
    required this.categoryRefPath,
    required this.categoryName,
    required this.categoryOrder,
    required this.categoryScore,
    required this.items,
  });
}

class _CategoryGroupBuilder {
  final String categoryRefPath;
  final String categoryName;
  final int categoryOrder;
  final List<_QuestionAnswerItem> items = [];

  _CategoryGroupBuilder({
    required this.categoryRefPath,
    required this.categoryName,
    required this.categoryOrder,
  });
}

class _QuestionAnswerItem {
  final String questionText;
  final int questionOrder;
  final String value;
  final dynamic weight;

  const _QuestionAnswerItem({
    required this.questionText,
    required this.questionOrder,
    required this.value,
    required this.weight,
  });

  bool get isAnswered => value.isNotEmpty && value != '-';
}
