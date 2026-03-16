import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/login_page.dart';
import '../models/audit_model.dart';
import 'audit_fill_page.dart';
import 'audit_pdf_preview_page_stub.dart'
    if (dart.library.io) 'audit_pdf_preview_page_mobile.dart';
import '../services/audit_pdf_service.dart';
import '../services/audit_score_service.dart';
import '../utils/category_name_formatter.dart';

class AuditDetailPage extends StatefulWidget {
  final String auditId;

  const AuditDetailPage({super.key, required this.auditId});

  @override
  State<AuditDetailPage> createState() => _AuditDetailPageState();
}

class _AuditDetailPageState extends State<AuditDetailPage> {
  static const bool _pdfExportEnabled = true;
  static const bool _refreshScoreBeforePdf = true;

  late Future<_AuditDetailData> _detailFuture;
  final AuditPdfService _auditPdfService = AuditPdfService();
  final AuditScoreService _auditScoreService = AuditScoreService();
  String? _loadedAuditStatus;
  String? _currentUserRole;
  bool _isGeneratingPdf = false;
  bool _isPdfLoadingDialogOpen = false;
  bool _isHeaderMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _refreshDetail();
  }

  @override
  void dispose() {
    _auditPdfService.dispose();
    super.dispose();
  }

  Future<_AuditDetailData> _loadAuditDetails() async {
    final firestore = FirebaseFirestore.instance;
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      final userSnapshot = await firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userData = userSnapshot.data();
      _currentUserRole = userData?['role'] as String?;
    } else {
      _currentUserRole = null;
    }

    final auditDoc = await firestore
        .collection('audits')
        .doc(widget.auditId)
        .get();
    if (!auditDoc.exists) {
      throw StateError('Auditoria nao encontrada.');
    }

    final audit = AuditModel.fromDocument(auditDoc);
    _loadedAuditStatus = audit.status;
    final answersFuture = auditDoc.reference.collection('answers').get();
    final questionsFuture = firestore
        .collection('questions')
        .where('templateRef', isEqualTo: audit.templateRef)
        .get();
    final categoriesFuture = firestore
        .collection('categories')
        .where('templateref', isEqualTo: audit.templateRef)
        .get();

    final answersSnapshot = await answersFuture;
    final questionsSnapshot = await questionsFuture;
    final categoriesSnapshot = await categoriesFuture;
    final questions = questionsSnapshot.docs;
    final answers = answersSnapshot.docs
        .map((doc) => doc.data())
        .toList(growable: false);
    final persistedScoreByCategory = audit.scoreByCategory;

    int compliantCount = 0;
    int nonCompliantCount = 0;
    for (final answer in answers) {
      final response = answer['response'];
      if (response == 'compliant') compliantCount++;
      if (response == 'non_compliant') nonCompliantCount++;
    }
    final int evaluatedCount = compliantCount + nonCompliantCount;
    final localOverallScore = _calculateWeightedScore(
      answers,
      questionsSnapshot.docs,
    );
    final usedOverallScoreFallback = _isScoreOutOfSync(
      audit.scoreFinal,
      localOverallScore,
    );
    final overallScore = usedOverallScoreFallback
        ? localOverallScore
        : audit.scoreFinal!;

    final clientRef = audit.clientRef;
    String clientName = 'Cliente sem nome';
    final clientSnapshot = await clientRef.get();
    final clientData = clientSnapshot.data() as Map<String, dynamic>?;
    final name = (clientData?['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      clientName = name;
    }

    final questionsByPath =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final questionDoc in questionsSnapshot.docs) {
      questionsByPath[questionDoc.reference.path] = questionDoc;
    }

    final categoriesByPath =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final categoryDoc in categoriesSnapshot.docs) {
      categoriesByPath[categoryDoc.reference.path] = categoryDoc;
    }

    final Map<String, _CategoryGroupBuilder> grouped = {};
    for (final answerDoc in answersSnapshot.docs) {
      final answerData = answerDoc.data();
      final questionRef = answerData['questionRef'] as DocumentReference?;
      if (questionRef == null) continue;

      final questionDoc = questionsByPath[questionRef.path];
      if (questionDoc == null) continue;
      final questionData = questionDoc.data();

      final categoryRef = questionData['categoryRef'] as DocumentReference?;
      final categoryPath = categoryRef?.path ?? '__sem_categoria__';
      final categoryDoc = categoryRef == null
          ? null
          : categoriesByPath[categoryPath];
      final categoryData = categoryDoc?.data();

      final builder = grouped.putIfAbsent(
        categoryPath,
        () => _CategoryGroupBuilder(
          categoryRefPath: categoryPath,
          categoryName: formatCategoryName(
            (categoryData?['name'] as String?) ?? 'Sem categoria',
          ),
          categoryOrder: (categoryData?['order'] as num?)?.toInt() ?? 999999,
        ),
      );

      builder.items.add(
        _QuestionAnswerItem(
          questionText:
              (questionData['text'] as String?) ?? 'Pergunta sem texto',
          questionOrder: (questionData['order'] as num?)?.toInt() ?? 999999,
          value:
              (answerData['response'] as String?) ??
              (answerData['value'] as String?) ??
              '-',
          weight: answerData['weight'],
        ),
      );
    }

    int categoryFallbackCount = 0;
    final groups = grouped.values.map((builder) {
      builder.items.sort((a, b) => a.questionOrder.compareTo(b.questionOrder));
      final localCategoryScore = _calculateCategoryWeightedScore(
        builder.categoryRefPath,
        questions,
        answers,
      );
      final persistedCategoryScore =
          persistedScoreByCategory[builder.categoryRefPath];
      if (_isScoreOutOfSync(persistedCategoryScore, localCategoryScore)) {
        categoryFallbackCount += 1;
      }
      return _CategoryGroup(
        categoryRefPath: builder.categoryRefPath,
        categoryName: builder.categoryName,
        categoryOrder: builder.categoryOrder,
        categoryScore: _isScoreOutOfSync(
              persistedCategoryScore,
              localCategoryScore,
            )
            ? localCategoryScore
            : persistedCategoryScore!,
        items: builder.items,
      );
    }).toList();

    groups.sort((a, b) => a.categoryOrder.compareTo(b.categoryOrder));

    final int totalItems = groups.fold<int>(
      0,
      (totalCount, group) => totalCount + group.items.length,
    );
    final int completedItems = groups.fold<int>(
      0,
      (totalCount, group) =>
          totalCount + group.items.where((item) => item.isAnswered).length,
    );

    if (usedOverallScoreFallback || categoryFallbackCount > 0) {
      debugPrint(
        'AuditDetail fallback score used for audit ${widget.auditId}: '
        'overallFallback=$usedOverallScoreFallback, '
        'categoryFallbackCount=$categoryFallbackCount',
      );
    }

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
      usedScoreFallback: usedOverallScoreFallback || categoryFallbackCount > 0,
    );
  }

  double _calculateWeightedScore(List answers, List questions) {
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
      final question =
          questionDoc as QueryDocumentSnapshot<Map<String, dynamic>>;
      final questionData = question.data();
      final questionCategoryRef =
          questionData['categoryRef'] as DocumentReference?;
      if (questionCategoryRef?.path != categoryRef) continue;

      Map<String, dynamic>? answer;
      for (final a in answers) {
        final answerData = a as Map<String, dynamic>;
        final answerQuestionRef =
            answerData['questionRef'] as DocumentReference?;
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

  bool _isScoreOutOfSync(double? persistedScore, double localScore) {
    if (persistedScore == null) return true;
    return (persistedScore - localScore).abs() > 0.05;
  }

  bool _isAdminRole() {
    return _currentUserRole == 'admin';
  }

  bool _canContinueEditing(String? status) {
    if (_isAdminRole()) return true;
    return status == 'draft' || status == 'in_progress';
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

  void _refreshDetail() {
    _detailFuture = _loadAuditDetails();
  }

  Future<void> _handleContinueEditing([String? status]) async {
    final currentStatus = status ?? _loadedAuditStatus;
    if (!_canContinueEditing(currentStatus)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Auditoria em validacao')));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuditFillPage(auditId: widget.auditId)),
    );

    if (!mounted) return;
    try {
      await _auditScoreService.computeAndPersistScore(widget.auditId);
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'computeAndPersistAuditScore on return from edit failed (${error.code}): ${error.message}',
      );
    } catch (error) {
      debugPrint(
        'computeAndPersistAuditScore on return from edit unexpected failure: $error',
      );
    }
    if (!mounted) return;
    setState(() {
      _refreshDetail();
    });
  }

  void _toggleHeaderMenu() {
    if (!mounted) return;
    setState(() {
      _isHeaderMenuOpen = !_isHeaderMenuOpen;
    });
  }

  void _closeHeaderMenu() {
    if (!mounted || !_isHeaderMenuOpen) return;
    setState(() {
      _isHeaderMenuOpen = false;
    });
  }

  Future<String?> _generatePdfUrlWithFeedback() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      await _handleExpiredSession();
      return null;
    }

    try {
      await currentUser.getIdToken(true);
    } catch (_) {
      await _handleExpiredSession();
      return null;
    }

    try {
      if (_refreshScoreBeforePdf) {
        try {
          await _auditScoreService.computeAndPersistScore(widget.auditId);
        } on FirebaseFunctionsException catch (error) {
          debugPrint(
            'computeAndPersistAuditScore before PDF failed (${error.code}): ${error.message}',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Nao foi possivel atualizar o score agora. O PDF sera gerado com o ultimo score salvo.',
                ),
              ),
            );
          }
        } catch (error) {
          debugPrint(
            'computeAndPersistAuditScore before PDF unexpected error: $error',
          );
        }
      }
      return await _auditPdfService.generatePdfUrl(widget.auditId);
    } on PdfSessionExpiredException {
      await _handleExpiredSession();
      return null;
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint('PDF callable error (${error.code}): $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pdfFunctionErrorMessage(error))));
      return null;
    } on StateError catch (error, stackTrace) {
      debugPrint('PDF callable invalid response: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resposta invalida da funcao de PDF.')),
      );
      return null;
    } catch (error, stackTrace) {
      debugPrint('PDF callable unexpected error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Falha ao gerar PDF.')));
      return null;
    }
  }

  Future<String?> _downloadPdfFileWithFeedback(String url) async {
    try {
      return await _auditPdfService.downloadPdf(url);
    } on PdfDownloadException catch (error, stackTrace) {
      debugPrint('PDF download error (status ${error.statusCode}): $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao baixar PDF (status ${error.statusCode}).'),
        ),
      );
      return null;
    } catch (error, stackTrace) {
      debugPrint('PDF download unexpected error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Falha ao baixar PDF.')));
      return null;
    }
  }

  Future<void> _handlePreviewPdf() async {
    if (!_pdfExportEnabled || _isGeneratingPdf) return;

    setState(() {
      _isGeneratingPdf = true;
    });
    _showPdfLoadingDialog();

    try {
      final url = await _generatePdfUrlWithFeedback();
      if (url == null) return;

      if (kIsWeb) {
        try {
          await _auditPdfService.openPdfUrl(url);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preview no web aberto em nova aba.'),
            ),
          );
        } catch (error, stackTrace) {
          debugPrint('PDF web open-url error: $error');
          debugPrintStack(stackTrace: stackTrace);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Falha ao abrir o PDF no navegador.')),
          );
        }
        return;
      }

      final filePath = await _downloadPdfFileWithFeedback(url);
      if (filePath == null || !mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AuditPdfPreviewPage(filePath: filePath),
        ),
      );
    } finally {
      _closePdfLoadingDialog();
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  Future<void> _handleGeneratePdf() async {
    if (!_pdfExportEnabled || _isGeneratingPdf) return;

    setState(() {
      _isGeneratingPdf = true;
    });
    _showPdfLoadingDialog();

    try {
      final url = await _generatePdfUrlWithFeedback();
      if (url == null) return;

      if (kIsWeb) {
        try {
          await _auditPdfService.openPdfUrl(url);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF gerado. Abrimos uma nova aba para download.'),
            ),
          );
        } catch (error, stackTrace) {
          debugPrint('PDF web open-url error: $error');
          debugPrintStack(stackTrace: stackTrace);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Falha ao abrir o PDF no navegador.')),
          );
        }
        return;
      }

      final filePath = await _downloadPdfFileWithFeedback(url);
      if (filePath == null) return;

      try {
        await _auditPdfService.sharePdf(filePath);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF pronto para compartilhamento.')),
        );
      } catch (error, stackTrace) {
        debugPrint('PDF share error: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Falha ao compartilhar PDF. Use o download gerado no navegador.',
            ),
          ),
        );
      }
    } finally {
      _closePdfLoadingDialog();
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  Future<void> _handleExpiredSession() async {
    _closePdfLoadingDialog();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sessao expirada. Faca login novamente.')),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _showPdfLoadingDialog() {
    if (!mounted || _isPdfLoadingDialogOpen) return;
    _isPdfLoadingDialogOpen = true;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: const Color(0x99000000),
      builder: (_) => const _PdfGeneratingDialog(),
    ).whenComplete(() {
      _isPdfLoadingDialogOpen = false;
    });
  }

  void _closePdfLoadingDialog() {
    if (!mounted || !_isPdfLoadingDialogOpen) return;
    _isPdfLoadingDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  String _pdfFunctionErrorMessage(FirebaseFunctionsException error) {
    final details = (error.message ?? '').trim();
    switch (error.code) {
      case 'permission-denied':
        return details.isEmpty
            ? 'Sem permissao para exportar.'
            : 'Sem permissao para exportar: $details';
      case 'not-found':
        return details.isEmpty
            ? 'Auditoria ou recurso do PDF nao encontrado.'
            : 'Recurso nao encontrado: $details';
      case 'invalid-argument':
        return details.isEmpty
            ? 'Parametros invalidos para gerar PDF.'
            : 'Parametro invalido: $details';
      case 'failed-precondition':
        return details.isEmpty
            ? 'Precondicao para gerar PDF nao atendida.'
            : 'Precondicao nao atendida: $details';
      case 'unavailable':
        return details.isEmpty
            ? 'Funcao de PDF indisponivel.'
            : 'Funcao de PDF indisponivel: $details';
      case 'internal':
        return details.isEmpty
            ? 'Falha interna ao gerar PDF. Tente novamente.'
            : 'Falha interna ao gerar PDF: $details';
      default:
        if (details.isEmpty) {
          return 'Falha ao gerar PDF (codigo: ${error.code}).';
        }
        return 'Falha ao gerar PDF (${error.code}): $details';
    }
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
        return Icons.check_circle_outline;
      case 'non_compliant':
        return Icons.cancel_outlined;
      case 'not_applicable':
        return Icons.remove_circle_outline;
      case 'not_observed':
        return Icons.visibility_off;
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
      case 'not_observed':
        return const Color(0xFF4B79D8);
      default:
        return const Color(0xFF8A8FA3);
    }
  }

  Widget _buildSummaryCard(_AuditDetailData detail, double progress) {
    return RepaintBoundary(
      child: Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0F171A24),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.clientName,
                  style: _inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7357D8),
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${detail.formattedCode} - ${_formatDate(detail.startedAt)}',
                  style: _inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF72778A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).round()}% concluido',
                  style: _inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF72778A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${detail.overallScore.toStringAsFixed(1)}%',
                style: _inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF7357D8),
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${detail.compliantCount} conformes',
                style: _inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF72778A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${detail.nonCompliantCount} nao conformes',
                style: _inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF72778A),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildCategorySection(_CategoryGroup group) {
    return RepaintBoundary(
      child: _AuditCategoryCard(
        key: PageStorageKey(group.categoryRefPath),
        group: group,
        valueIcon: _valueIcon,
        valueColor: _valueColor,
      ),
    );
  }

  Widget _buildHeaderActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEE9FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: IconButton(
        onPressed: onPressed,
        splashRadius: 18,
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          size: 18,
          color: const Color(0xFF7357D8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width >= 900
        ? width * 0.16
        : (width >= 600 ? 24.0 : 16.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
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
                    opacity: _isHeaderMenuOpen ? 0.28 : 1,
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
                      child: _isHeaderMenuOpen
                          ? Row(
                              key: const ValueKey('header-actions-open'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildHeaderActionButton(
                                  onPressed: () {
                                    _closeHeaderMenu();
                                    _handleContinueEditing(_loadedAuditStatus);
                                  },
                                  icon: Icons.edit_outlined,
                                ),
                                if (_pdfExportEnabled)
                                  _buildHeaderActionButton(
                                    onPressed: _isGeneratingPdf
                                        ? null
                                        : () {
                                            _closeHeaderMenu();
                                            _handleGeneratePdf();
                                          },
                                    icon: Icons.share_outlined,
                                  ),
                                if (_pdfExportEnabled)
                                  _buildHeaderActionButton(
                                    onPressed: _isGeneratingPdf
                                        ? null
                                        : () {
                                            _closeHeaderMenu();
                                            _handlePreviewPdf();
                                          },
                                    icon: Icons.picture_as_pdf_outlined,
                                  ),
                              ],
                            )
                          : const SizedBox(
                              key: ValueKey('header-actions-closed'),
                              width: 0,
                            ),
                    ),
                    IconButton(
                      onPressed: _toggleHeaderMenu,
                      icon: Icon(
                        _isHeaderMenuOpen
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
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _closeHeaderMenu,
        child: FutureBuilder<_AuditDetailData>(
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
          return ListView(
            padding: EdgeInsets.fromLTRB(
              0,
              0,
              0,
              24,
            ),
            children: [
              _buildSummaryCard(detail, progress),
              ...detail.groups.map(
                (group) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: _buildCategorySection(group),
                ),
              ),
            ],
          );
          },
        ),
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
  final bool usedScoreFallback;

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
    required this.usedScoreFallback,
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

class _AuditCategoryCard extends StatefulWidget {
  final _CategoryGroup group;
  final IconData Function(String value) valueIcon;
  final Color Function(String value) valueColor;

  const _AuditCategoryCard({
    super.key,
    required this.group,
    required this.valueIcon,
    required this.valueColor,
  });

  @override
  State<_AuditCategoryCard> createState() => _AuditCategoryCardState();
}

class _AuditCategoryCardState extends State<_AuditCategoryCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final total = group.items.length;
    final filled = group.items.where((item) => item.isAnswered).length;
    final completed = total > 0 && filled == total;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F171A24),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.categoryName,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1B1830),
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _AuditCategoryBadge(completed: completed),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$filled de $total itens preenchidos',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF72778A),
                                ),
                              ),
                            ),
                            Text(
                              '${group.categoryScore.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7357D8),
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              _isExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: const Color(0xFF7357D8),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  for (int index = 0; index < group.items.length; index++) ...[
                    if (index > 0) const SizedBox(height: 12),
                    _AuditQuestionTile(
                      item: group.items[index],
                      valueIcon: widget.valueIcon,
                      valueColor: widget.valueColor,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AuditCategoryBadge extends StatelessWidget {
  final bool completed;

  const _AuditCategoryBadge({required this.completed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: completed
            ? const Color(0xFFE8F7EF)
            : const Color(0xFFFFF3DF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        completed ? 'Concluida' : 'Pendente',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: completed
              ? const Color(0xFF22A861)
              : const Color(0xFFD9921A),
        ),
      ),
    );
  }
}

class _AuditQuestionTile extends StatelessWidget {
  final _QuestionAnswerItem item;
  final IconData Function(String value) valueIcon;
  final Color Function(String value) valueColor;

  const _AuditQuestionTile({
    required this.item,
    required this.valueIcon,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6FA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '${item.questionOrder}.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9A9EAE),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.questionText,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF171A24),
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            valueIcon(item.value),
            color: valueColor(item.value),
            size: 21,
          ),
        ],
      ),
    );
  }
}

class _PdfGeneratingDialog extends StatelessWidget {
  const _PdfGeneratingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFF4F0FF)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE3DBFF), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _PdfLoadingSpinner(),
            SizedBox(height: 18),
            Text(
              'Gerando relat\u00f3rio PDF',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF39306E),
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Estamos processando as respostas e montando o arquivo. Isso pode levar alguns segundos.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Color(0xFF8A8FA3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfLoadingSpinner extends StatelessWidget {
  const _PdfLoadingSpinner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFF0EAFF), Color(0xFFE7DEFF)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2D6D4BC3),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6D4BC3)),
          ),
        ),
      ),
    );
  }
}
