import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AuditFillPage extends StatefulWidget {
  final String auditId;

  const AuditFillPage({Key? key, required this.auditId}) : super(key: key);

  @override
  State<AuditFillPage> createState() => _AuditFillPageState();
}

class _AuditFillPageState extends State<AuditFillPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  String _headerTitle = 'Auditoria';
  final List<_CategorySection> _sections = [];
  final Map<String, String?> _responses = {};
  final Map<String, DocumentReference<Map<String, dynamic>>> _answerDocByQuestion = {};
  final Map<String, DocumentReference<Map<String, dynamic>>> _questionRefByQuestion = {};
  final Map<String, DocumentReference<Map<String, dynamic>>> _categoryRefByQuestion = {};

  @override
  void initState() {
    super.initState();
    _loadAuditData();
  }

  Future<void> _loadAuditData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auditRef = _firestore.collection('audits').doc(widget.auditId);
      final auditSnapshot = await auditRef.get();
      if (!auditSnapshot.exists) {
        throw StateError('Auditoria nao encontrada.');
      }

      final auditData = auditSnapshot.data() as Map<String, dynamic>;
      final templateRef = auditData['templateRef'] as DocumentReference?;
      if (templateRef == null) {
        throw StateError('templateRef ausente na auditoria.');
      }

      final auditNumber = (auditData['auditnumber'] as num?)?.toInt();
      _headerTitle = auditNumber == null
          ? 'Auditoria'
          : 'Auditoria ART-${auditNumber.toString().padLeft(4, '0')}';

      final categoriesSnapshot = await _firestore
          .collection('categories')
          .where('templateref', isEqualTo: templateRef)
          .orderBy('order')
          .get();

      final questionsSnapshot = await _firestore
          .collection('questions')
          .where('templateRef', isEqualTo: templateRef)
          .orderBy('order')
          .get();

      final answersSnapshot = await auditRef.collection('answers').get();

      final categoryMeta = <String, _CategoryMeta>{};
      for (final doc in categoriesSnapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim();
        final order = (data['order'] as num?)?.toInt() ?? 999999;
        categoryMeta[doc.id] = _CategoryMeta(
          id: doc.id,
          name: (name == null || name.isEmpty) ? 'Sem categoria' : name,
          order: order,
        );
      }

      _responses.clear();
      _answerDocByQuestion.clear();
      _questionRefByQuestion.clear();
      _categoryRefByQuestion.clear();

      for (final answerDoc in answersSnapshot.docs) {
        final data = answerDoc.data();
        final questionRef = data['questionRef'] as DocumentReference?;
        if (questionRef == null) continue;

        final questionId = questionRef.id;
        _responses[questionId] = data['response'] as String?;
        _answerDocByQuestion[questionId] = answerDoc.reference;
      }

      final grouped = <String, List<_QuestionItem>>{};
      for (final doc in questionsSnapshot.docs) {
        final data = doc.data();
        final text = (data['text'] as String?)?.trim();
        final order = (data['order'] as num?)?.toInt() ?? 999999;
        final categoryRef = data['categoryRef'] as DocumentReference?;
        final categoryId = categoryRef?.id ?? 'uncategorized';

        _questionRefByQuestion[doc.id] = doc.reference;
        if (categoryRef != null) {
          _categoryRefByQuestion[doc.id] = categoryRef
              .withConverter<Map<String, dynamic>>(
                fromFirestore: (snap, _) => snap.data() ?? {},
                toFirestore: (value, _) => value,
              );
        }
        _responses.putIfAbsent(doc.id, () => null);

        grouped.putIfAbsent(categoryId, () => []);
        grouped[categoryId]!.add(
          _QuestionItem(
            id: doc.id,
            text: (text == null || text.isEmpty) ? 'Pergunta sem texto' : text,
            order: order,
          ),
        );
      }

      final sectionEntries = grouped.entries.map((entry) {
        final categoryId = entry.key;
        final questions = entry.value..sort((a, b) => a.order.compareTo(b.order));
        final meta = categoryMeta[categoryId] ??
            _CategoryMeta(id: categoryId, name: 'Sem categoria', order: 999999);
        return _CategorySection(
          id: meta.id,
          name: meta.name,
          order: meta.order,
          questions: questions,
        );
      }).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      if (!mounted) return;
      setState(() {
        _sections
          ..clear()
          ..addAll(sectionEntries);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  bool _isAnswered(String? value) {
    return value != null && value.isNotEmpty;
  }

  int get _totalQuestions {
    return _sections.fold<int>(0, (total, section) => total + section.questions.length);
  }

  int get _answeredQuestions {
    int count = 0;
    for (final section in _sections) {
      for (final question in section.questions) {
        if (_isAnswered(_responses[question.id])) {
          count++;
        }
      }
    }
    return count;
  }

  Future<void> _setResponse({
    required String questionId,
    required String response,
  }) async {
    final previous = _responses[questionId];
    setState(() {
      _responses[questionId] = response;
    });

    try {
      final auditRef = _firestore.collection('audits').doc(widget.auditId);
      final existingAnswerRef = _answerDocByQuestion[questionId];

      if (existingAnswerRef != null) {
        await existingAnswerRef.update({
          'response': response,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final questionRef = _questionRefByQuestion[questionId];
        final categoryRef = _categoryRefByQuestion[questionId];
        final newAnswerRef = auditRef.collection('answers').doc();
        await newAnswerRef.set({
          'questionRef': questionRef,
          'categoryRef': categoryRef,
          'response': response,
          'comment': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _answerDocByQuestion[questionId] = newAnswerRef;
      }

      await auditRef.update({
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _responses[questionId] = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao salvar resposta.')),
      );
    }
  }

  Future<void> _submitForValidation() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final auditRef = _firestore.collection('audits').doc(widget.auditId);
      await auditRef.update({
        'status': 'validation_pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel enviar para validacao.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _responseChoice({
    required String questionId,
    required String value,
    required String label,
    required Color color,
  }) {
    final selected = _responses[questionId] == value;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => _setResponse(questionId: questionId, response: value),
      label: Text(label),
      selectedColor: color.withOpacity(0.2),
      labelStyle: TextStyle(
        color: selected ? color : const Color(0xFF5A5F73),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: selected ? color : const Color(0xFFE6E6EF)),
      backgroundColor: Colors.white,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildQuestionTile(_QuestionItem question) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1C1C),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _responseChoice(
                questionId: question.id,
                value: 'compliant',
                label: 'OK',
                color: const Color(0xFF16A34A),
              ),
              _responseChoice(
                questionId: question.id,
                value: 'non_compliant',
                label: 'NC',
                color: const Color(0xFFDC2626),
              ),
              _responseChoice(
                questionId: question.id,
                value: 'not_applicable',
                label: 'NA',
                color: const Color(0xFF6B7280),
              ),
              _responseChoice(
                questionId: question.id,
                value: 'not_observed',
                label: 'NO',
                color: const Color(0xFF6B7280),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(_CategorySection section) {
    final answered = section.questions
        .where((q) => _isAnswered(_responses[q.id]))
        .length;

    return ExpansionTile(
      title: Text(
        section.name,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF39306E),
        ),
      ),
      subtitle: Text(
        '$answered de ${section.questions.length} respondidas',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF8A8FA3),
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: section.questions.map(_buildQuestionTile).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final answered = _answeredQuestions;
    final total = _totalQuestions;
    final progress = total == 0 ? 0.0 : answered / total;
    final allAnswered = total > 0 && answered == total;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          _headerTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1C1C1C),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFF8A8FA3)),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(999),
                            backgroundColor: const Color(0xFFE3E3EC),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6D4BC3)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$answered de $total respondidas',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8A8FA3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: _sections.map(_buildCategorySection).toList(growable: false),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF7262C2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Progresso salvo automaticamente.'),
                          ),
                        );
                      },
                      child: const Center(
                        child: Text(
                          'Salvar progresso',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: allAnswered ? const Color(0xFF5A3E8E) : const Color(0xFFDCDCE6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: allAnswered && !_isSubmitting ? _submitForValidation : null,
                      child: Center(
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                'Enviar para validacao',
                                style: TextStyle(
                                  color: allAnswered ? Colors.white : const Color(0xFF9A9AB0),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryMeta {
  final String id;
  final String name;
  final int order;

  const _CategoryMeta({
    required this.id,
    required this.name,
    required this.order,
  });
}

class _CategorySection {
  final String id;
  final String name;
  final int order;
  final List<_QuestionItem> questions;

  const _CategorySection({
    required this.id,
    required this.name,
    required this.order,
    required this.questions,
  });
}

class _QuestionItem {
  final String id;
  final String text;
  final int order;

  const _QuestionItem({
    required this.id,
    required this.text,
    required this.order,
  });
}
