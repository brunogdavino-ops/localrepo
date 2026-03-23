import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../audits/services/active_template_service.dart';

class ClientResponsibilitiesPage extends StatefulWidget {
  final String? clientId;
  final String clientName;
  final Set<String>? initialClientQuestionPaths;
  final bool persistOnSave;

  const ClientResponsibilitiesPage({
    super.key,
    this.clientId,
    required this.clientName,
    this.initialClientQuestionPaths,
    this.persistOnSave = true,
  });

  @override
  State<ClientResponsibilitiesPage> createState() =>
      _ClientResponsibilitiesPageState();
}

class _ClientResponsibilitiesPageState extends State<ClientResponsibilitiesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ActiveTemplateService _activeTemplateService = ActiveTemplateService();
  final Set<String> _clientQuestionPaths = <String>{};
  final Set<String> _expandedCategoryPaths = <String>{};
  final List<_CategorySection> _sections = <_CategorySection>[];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAdmin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('Usuario nao autenticado.');
      }

      final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
      final role = (userSnapshot.data()?['role'] as String?)?.trim().toLowerCase();
      _isAdmin = role == 'admin';

      _clientQuestionPaths
        ..clear()
        ..addAll(widget.initialClientQuestionPaths ?? const <String>{});

      final persistedOperatorQuestionPaths = <String>{};

      if (widget.persistOnSave) {
        final clientId = widget.clientId;
        if (clientId == null || clientId.isEmpty) {
          throw StateError('Cliente nao informado.');
        }

        final clientRef = _firestore.collection('clients').doc(clientId);
        final clientSnapshot = await clientRef.get();
        if (!clientSnapshot.exists) {
          throw StateError('Cliente nao encontrado.');
        }

        final clientData = clientSnapshot.data() ?? <String, dynamic>{};
        final responsibilityMap =
            (clientData['responsibilityMap'] as Map<String, dynamic>?) ?? <String, dynamic>{};

        persistedOperatorQuestionPaths.addAll(
          responsibilityMap.entries
              .where((entry) => entry.value == 'operator')
              .map((entry) => entry.key),
        );
      }

      final templateRef = await _activeTemplateService.resolveActiveTemplateRef();

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

      final categoriesByPath = <String, _CategoryMeta>{};
      for (final doc in categoriesSnapshot.docs) {
        final data = doc.data();
        categoriesByPath[doc.reference.path] = _CategoryMeta(
          path: doc.reference.path,
          name: ((data['name'] as String?) ?? 'Sem categoria').trim(),
          order: (data['order'] as num?)?.toInt() ?? 999999,
        );
      }

      final groupedQuestions = <String, List<_QuestionItem>>{};
      for (final doc in questionsSnapshot.docs) {
        final data = doc.data();
        final categoryRef = data['categoryRef'] as DocumentReference?;
        final categoryPath = categoryRef?.path ?? 'uncategorized';
        groupedQuestions.putIfAbsent(categoryPath, () => <_QuestionItem>[]);
        groupedQuestions[categoryPath]!.add(
          _QuestionItem(
            path: doc.reference.path,
            text: ((data['text'] as String?) ?? 'Pergunta sem texto').trim(),
            order: (data['order'] as num?)?.toInt() ?? 999999,
          ),
        );
      }

      final sections = groupedQuestions.entries.map((entry) {
        final meta = categoriesByPath[entry.key] ??
            _CategoryMeta(
              path: entry.key,
              name: 'Sem categoria',
              order: 999999,
            );
        final questions = entry.value..sort((a, b) => a.order.compareTo(b.order));
        return _CategorySection(
          path: meta.path,
          name: meta.name,
          order: meta.order,
          questions: questions,
        );
      }).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      final allQuestionPaths = <String>{
        for (final section in sections)
          for (final question in section.questions) question.path,
      };

      if (widget.persistOnSave) {
        _clientQuestionPaths
          ..clear()
          ..addAll(allQuestionPaths.difference(persistedOperatorQuestionPaths));
      }

      if (!mounted) return;
      setState(() {
        _sections
          ..clear()
          ..addAll(sections);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveResponsibilities() async {
    if (_isSaving || !_isAdmin) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final allQuestionPaths = <String>{
        for (final section in _sections)
          for (final question in section.questions) question.path,
      };
      final responsibilityMap = <String, String>{
        for (final questionPath in allQuestionPaths)
          if (!_clientQuestionPaths.contains(questionPath)) questionPath: 'operator',
      };

      if (!widget.persistOnSave) {
        if (!mounted) return;
        Navigator.of(context).pop(Set<String>.from(_clientQuestionPaths));
        return;
      }

      await _firestore.collection('clients').doc(widget.clientId).update({
        'responsibilityMap': responsibilityMap,
        'responsibilityUpdatedAt': FieldValue.serverTimestamp(),
        'responsibilityUpdatedBy': _firestore.collection('users').doc(user.uid),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Responsabilidades salvas com sucesso.')),
      );
      Navigator.of(context).pop(Set<String>.from(_clientQuestionPaths));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel salvar as responsabilidades.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<int> _selectedQuestionNumbersSorted() {
    final numbers = <int>[];
    for (final section in _sections) {
      for (final question in section.questions) {
        if (_clientQuestionPaths.contains(question.path)) {
          numbers.add(question.order);
        }
      }
    }
    numbers.sort();
    return numbers;
  }

  Future<void> _confirmAndSaveResponsibilities() async {
    final selectedNumbers = _selectedQuestionNumbersSorted();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar responsabilidades'),
          content: selectedNumbers.isEmpty
              ? const Text(
                  'Nenhuma pergunta foi marcada para Cliente. Todas ficarao como Operadora por padrao.',
                )
              : SizedBox(
                  width: 320,
                  child: SingleChildScrollView(
                    child: Text(
                      'Perguntas marcadas para Cliente:\n${selectedNumbers.join(', ')}',
                    ),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7262C2),
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _saveResponsibilities();
    }
  }

  bool _isCategoryAllSelected(_CategorySection section) {
    if (section.questions.isEmpty) return false;
    for (final question in section.questions) {
      if (!_clientQuestionPaths.contains(question.path)) {
        return false;
      }
    }
    return true;
  }

  bool _isCategoryPartiallySelected(_CategorySection section) {
    if (section.questions.isEmpty) return false;
    int selectedCount = 0;
    for (final question in section.questions) {
      if (_clientQuestionPaths.contains(question.path)) {
        selectedCount++;
      }
    }
    return selectedCount > 0 && selectedCount < section.questions.length;
  }

  void _toggleCategorySelection(_CategorySection section, bool selectAll) {
    setState(() {
      for (final question in section.questions) {
        if (selectAll) {
          _clientQuestionPaths.add(question.path);
        } else {
          _clientQuestionPaths.remove(question.path);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F5),
      appBar: AppBar(
        title: const Text('Definir responsabilidades'),
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Text(
                      widget.clientName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1C),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Marque as perguntas do Cliente. As nao marcadas ficam como Operadora por padrao.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF8A8FA3),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_isAdmin)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Somente admin pode editar as responsabilidades.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF8A8FA3),
                          ),
                        ),
                      ),
                    ..._sections.map((section) {
                      final isExpanded = _expandedCategoryPaths.contains(section.path);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE6E6EF)),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            key: ValueKey(section.path),
                            maintainState: true,
                            initiallyExpanded: isExpanded,
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                            title: Text(
                              section.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF39306E),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  tristate: true,
                                  value: _isCategoryAllSelected(section)
                                      ? true
                                      : _isCategoryPartiallySelected(section)
                                          ? null
                                          : false,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  side: const BorderSide(color: Color(0xFFB8B3D9)),
                                  activeColor: const Color(0xFF7262C2),
                                  checkColor: Colors.white,
                                  onChanged: !_isAdmin
                                      ? null
                                      : (value) {
                                          _toggleCategorySelection(
                                            section,
                                            value == true,
                                          );
                                        },
                                ),
                                const Icon(
                                  Icons.expand_more_rounded,
                                  color: Color(0xFF8A8FA3),
                                ),
                              ],
                            ),
                            onExpansionChanged: (expanded) {
                              setState(() {
                                if (expanded) {
                                  _expandedCategoryPaths.add(section.path);
                                } else {
                                  _expandedCategoryPaths.remove(section.path);
                                }
                              });
                            },
                            children: section.questions.map((question) {
                              final selected =
                                  _clientQuestionPaths.contains(question.path);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: !_isAdmin
                                      ? null
                                      : () {
                                          setState(() {
                                            if (selected) {
                                              _clientQuestionPaths.remove(
                                                question.path,
                                              );
                                            } else {
                                              _clientQuestionPaths.add(
                                                question.path,
                                              );
                                            }
                                          });
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      6,
                                      8,
                                      8,
                                      8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 34,
                                          child: Checkbox(
                                            value: selected,
                                            activeColor:
                                                const Color(0xFF7262C2),
                                            checkColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFFB8B3D9),
                                            ),
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onChanged: !_isAdmin
                                                ? null
                                                : (value) {
                                                    setState(() {
                                                      if (value == true) {
                                                        _clientQuestionPaths
                                                            .add(
                                                          question.path,
                                                        );
                                                      } else {
                                                        _clientQuestionPaths
                                                            .remove(
                                                          question.path,
                                                        );
                                                      }
                                                    });
                                                  },
                                          ),
                                        ),
                                        SizedBox(
                                          width: 28,
                                          height: 24,
                                          child: Center(
                                            child: Text(
                                              '${question.order}',
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF39306E),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                question.text,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  color: Color(0xFF4B5563),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                selected
                                                    ? 'Cliente'
                                                    : 'Operadora',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: selected
                                                      ? const Color(
                                                          0xFF5A3E8E,
                                                        )
                                                      : const Color(
                                                          0xFF8A8FA3,
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
                              );
                            }).toList(growable: false),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
      bottomNavigationBar: _isAdmin
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _confirmAndSaveResponsibilities,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7262C2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Salvar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _CategoryMeta {
  final String path;
  final String name;
  final int order;

  const _CategoryMeta({
    required this.path,
    required this.name,
    required this.order,
  });
}

class _CategorySection {
  final String path;
  final String name;
  final int order;
  final List<_QuestionItem> questions;

  const _CategorySection({
    required this.path,
    required this.name,
    required this.order,
    required this.questions,
  });
}

class _QuestionItem {
  final String path;
  final String text;
  final int order;

  const _QuestionItem({
    required this.path,
    required this.text,
    required this.order,
  });
}
