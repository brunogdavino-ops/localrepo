import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/artezi_answer_icon_button.dart';
import '../widgets/artezi_progress_bar.dart';

class AuditFillPage extends StatefulWidget {
  final String auditId;

  const AuditFillPage({Key? key, required this.auditId}) : super(key: key);

  @override
  State<AuditFillPage> createState() => _AuditFillPageState();
}

class _AuditFillPageState extends State<AuditFillPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  int _selectedCategoryIndex = 0;

  String _headerTitle = 'Auditoria';
  final List<_CategorySection> _sections = [];
  final Map<String, String?> _responses = {};
  final Map<String, String> _notes = {};
  final Map<String, DocumentReference<Map<String, dynamic>>> _answerDocByQuestion = {};
  final Map<String, DocumentReference<Map<String, dynamic>>> _questionRefByQuestion = {};
  final Map<String, DocumentReference<Map<String, dynamic>>> _categoryRefByQuestion = {};
  final Map<String, TextEditingController> _noteControllers = {};
  final Map<String, Timer> _noteDebounce = {};
  final Map<String, int> _totalQuestionsByCategory = {};
  final Map<String, int> _answeredQuestionsByCategory = {};
  final Map<String, bool> _photoUploadingByQuestion = {};

  static const Color _bgColor = Color(0xFFF6F5F5);
  static const Color _brandColor = Color(0xFF39306E);
  static const Color _blackColor = Color(0xFF1C1C1C);
  static const Color _mutedColor = Color(0xFF8A8FA3);
  static const Color _lineColor = Color(0xFFE6E6EF);
  static const Color _chipBgColor = Color(0xFFECECF3);
  static const Color _chipBorderColor = Color(0xFFE2E2EE);
  static const Color _primaryButton = Color(0xFF7262C2);

  TextStyle _inter({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAuditData();
  }

  @override
  void dispose() {
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    for (final timer in _noteDebounce.values) {
      timer.cancel();
    }
    super.dispose();
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
      final defaultTitle = auditNumber == null
          ? 'Auditoria'
          : 'Auditoria ART-${auditNumber.toString().padLeft(4, '0')}';

      String? clientName;
      final clientRef = auditData['clientRef'] as DocumentReference?;
      if (clientRef != null) {
        final clientSnapshot = await clientRef.get();
        final clientData = clientSnapshot.data() as Map<String, dynamic>?;
        final client = (clientData?['name'] as String?)?.trim();
        if (client != null && client.isNotEmpty) {
          clientName = client;
        }
      }
      _headerTitle = clientName == null ? defaultTitle : 'Auditoria: $clientName';

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

      final categoriesByPath = <String, _CategoryMeta>{};
      for (final doc in categoriesSnapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim();
        final order = (data['order'] as num?)?.toInt() ?? 999999;
        categoriesByPath[doc.reference.path] = _CategoryMeta(
          id: doc.id,
          name: (name == null || name.isEmpty) ? 'Sem categoria' : name,
          order: order,
        );
      }
      debugPrint('AuditFillPage: categories loaded = ${categoriesSnapshot.docs.length}');
      debugPrint('AuditFillPage: questions loaded = ${questionsSnapshot.docs.length}');

      _responses.clear();
      _notes.clear();
      _answerDocByQuestion.clear();
      _questionRefByQuestion.clear();
      _categoryRefByQuestion.clear();
      _totalQuestionsByCategory.clear();
      _answeredQuestionsByCategory.clear();

      for (final answerDoc in answersSnapshot.docs) {
        final data = answerDoc.data();
        final questionRef = data['questionRef'] as DocumentReference?;
        if (questionRef == null) continue;

        final questionId = questionRef.id;
        _responses[questionId] = (data['response'] as String?) ?? (data['value'] as String?);
        _notes[questionId] =
            ((data['notes'] as String?) ?? (data['comment'] as String?) ?? '').trim();
        _answerDocByQuestion[questionId] = answerDoc.reference;
      }

      final grouped = <String, List<_QuestionItem>>{};
      int missingCategoryLogCount = 0;
      for (final doc in questionsSnapshot.docs) {
        final data = doc.data();
        final text = (data['text'] as String?)?.trim();
        final order = (data['order'] as num?)?.toInt() ?? 999999;
        final categoryRef = data['categoryRef'] as DocumentReference?;
        final categoryPath = categoryRef?.path ?? 'uncategorized';
        if (categoryRef != null &&
            !categoriesByPath.containsKey(categoryRef.path) &&
            missingCategoryLogCount < 5) {
          debugPrint('Missing category for question: ${categoryRef.path}');
          missingCategoryLogCount++;
        }

        _questionRefByQuestion[doc.id] = doc.reference;
        if (categoryRef != null) {
          _categoryRefByQuestion[doc.id] = categoryRef
              .withConverter<Map<String, dynamic>>(
                fromFirestore: (snap, _) => snap.data() ?? {},
                toFirestore: (value, _) => value,
              );
        }
        _responses.putIfAbsent(doc.id, () => null);
        _notes.putIfAbsent(doc.id, () => '');

        _totalQuestionsByCategory[categoryPath] =
            (_totalQuestionsByCategory[categoryPath] ?? 0) + 1;
        if (_responses[doc.id] != null) {
          _answeredQuestionsByCategory[categoryPath] =
              (_answeredQuestionsByCategory[categoryPath] ?? 0) + 1;
        }

        grouped.putIfAbsent(categoryPath, () => []);
        grouped[categoryPath]!.add(
          _QuestionItem(
            id: doc.id,
            text: (text == null || text.isEmpty) ? 'Pergunta sem texto' : text,
            order: order,
          ),
        );
      }

      final sectionEntries = grouped.entries.map((entry) {
        final categoryPath = entry.key;
        final questions = entry.value..sort((a, b) => a.order.compareTo(b.order));
        final meta = categoriesByPath[categoryPath] ??
            _CategoryMeta(id: categoryPath, name: 'Sem categoria', order: 999999);
        return _CategorySection(
          id: meta.id,
          categoryPath: categoryPath,
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
        if (_sections.isEmpty) {
          _selectedCategoryIndex = 0;
        } else if (_selectedCategoryIndex >= _sections.length) {
          _selectedCategoryIndex = _sections.length - 1;
        }
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

  _CategorySection? get _selectedSection {
    if (_sections.isEmpty) return null;
    if (_selectedCategoryIndex < 0 || _selectedCategoryIndex >= _sections.length) {
      return _sections.first;
    }
    return _sections[_selectedCategoryIndex];
  }

  double _progressForSection(_CategorySection? section) {
    if (section == null || section.questions.isEmpty) return 0;
    final answered = section.questions.where((q) => _isAnswered(_responses[q.id])).length;
    return answered / section.questions.length;
  }

  bool _isCategoryComplete(String categoryPath) {
    final total = _totalQuestionsByCategory[categoryPath] ?? 0;
    final answered = _answeredQuestionsByCategory[categoryPath] ?? 0;
    return total > 0 && answered == total;
  }

  void _rebuildCategoryStats() {
    _answeredQuestionsByCategory.clear();
    for (final section in _sections) {
      int answered = 0;
      for (final question in section.questions) {
        if (_responses[question.id] != null) {
          answered++;
        }
      }
      _answeredQuestionsByCategory[section.categoryPath] = answered;
      _totalQuestionsByCategory[section.categoryPath] = section.questions.length;
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> _ensureAnswerRef(String questionId) async {
    final existing = _answerDocByQuestion[questionId];
    if (existing != null) return existing;

    final auditRef = _firestore.collection('audits').doc(widget.auditId);
    final questionRef = _questionRefByQuestion[questionId];
    final categoryRef = _categoryRefByQuestion[questionId];
    if (questionRef == null) {
      throw StateError('Pergunta sem referencia para anexar foto.');
    }

    final newAnswerRef = auditRef.collection('answers').doc();
    await newAnswerRef.set({
      'questionRef': questionRef,
      'categoryRef': categoryRef,
      'response': _responses[questionId],
      'value': _responses[questionId],
      'notes': _notes[questionId] ?? '',
      'comment': _notes[questionId] ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _answerDocByQuestion[questionId] = newAnswerRef;
    return newAnswerRef;
  }

  Future<ImageSource?> _pickImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tirar foto'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Escolher da galeria'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancelar'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleAddPhoto(String questionId) async {
    try {
      final source = await _pickImageSource();
      if (source == null) return;

      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() {
        _photoUploadingByQuestion[questionId] = true;
      });

      final answerRef = await _ensureAnswerRef(questionId);
      final photoDoc = answerRef.collection('photos').doc();
      final filePath = 'audit_photos/${widget.auditId}/${answerRef.id}/${photoDoc.id}.jpg';
      final storageRef = _storage.ref().child(filePath);
      final file = File(picked.path);

      await storageRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await storageRef.getDownloadURL();
      final uid = FirebaseAuth.instance.currentUser?.uid;

      await photoDoc.set({
        'url': url,
        'path': filePath,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid ?? '',
        'fileName': picked.name,
      });

      await _firestore.collection('audits').doc(widget.auditId).update({
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao anexar foto.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _photoUploadingByQuestion[questionId] = false;
        });
      }
    }
  }

  Future<void> _deletePhoto({
    required String questionId,
    required DocumentSnapshot<Map<String, dynamic>> photoDoc,
  }) async {
    try {
      final data = photoDoc.data() ?? {};
      final path = data['path'] as String?;
      if (path != null && path.isNotEmpty) {
        await _storage.ref().child(path).delete();
      }
      await photoDoc.reference.delete();

      await _firestore.collection('audits').doc(widget.auditId).update({
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao remover foto.')),
      );
    }
  }

  void _openPhotoPreview(String url) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhotosStrip(String questionId) {
    final answerRef = _answerDocByQuestion[questionId];
    if (answerRef == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: answerRef
          .collection('photos')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final photos = snapshot.data!.docs;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final photoDoc = photos[index];
                final data = photoDoc.data();
                final url = data['url'] as String?;
                if (url == null || url.isEmpty) return const SizedBox.shrink();

                return GestureDetector(
                  onTap: () => _openPhotoPreview(url),
                  onLongPress: () => _deletePhoto(questionId: questionId, photoDoc: photoDoc),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _deletePhoto(questionId: questionId, photoDoc: photoDoc),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  TextEditingController _controllerForQuestion(String questionId) {
    return _noteControllers.putIfAbsent(
      questionId,
      () => TextEditingController(text: _notes[questionId] ?? ''),
    );
  }

  void _queueNoteSave({
    required String questionId,
    required String text,
  }) {
    _notes[questionId] = text;
    _noteDebounce[questionId]?.cancel();
    _noteDebounce[questionId] = Timer(const Duration(milliseconds: 450), () {
      _setNote(questionId: questionId, note: text);
    });
  }

  Future<void> _setNote({
    required String questionId,
    required String note,
  }) async {
    final auditRef = _firestore.collection('audits').doc(widget.auditId);
    final previous = _notes[questionId] ?? '';
    _notes[questionId] = note;

    try {
      final existingAnswerRef = _answerDocByQuestion[questionId];
      if (existingAnswerRef != null) {
        await existingAnswerRef.update({
          'notes': note,
          'comment': note,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final questionRef = _questionRefByQuestion[questionId];
        final categoryRef = _categoryRefByQuestion[questionId];
        final newAnswerRef = auditRef.collection('answers').doc();
        await newAnswerRef.set({
          'questionRef': questionRef,
          'categoryRef': categoryRef,
          'response': _responses[questionId],
          'value': _responses[questionId],
          'notes': note,
          'comment': note,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _answerDocByQuestion[questionId] = newAnswerRef;
      }

      await auditRef.update({
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!mounted) return;
      _notes[questionId] = previous;
      final controller = _noteControllers[questionId];
      if (controller != null && controller.text != previous) {
        controller.text = previous;
        controller.selection = TextSelection.collapsed(offset: previous.length);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao salvar comentario.')),
      );
    }
  }

  Future<void> _setResponse({
    required String questionId,
    required String response,
  }) async {
    final previous = _responses[questionId];
    setState(() {
      _responses[questionId] = response;
      _rebuildCategoryStats();
    });

    try {
      final auditRef = _firestore.collection('audits').doc(widget.auditId);
      final existingAnswerRef = _answerDocByQuestion[questionId];

      if (existingAnswerRef != null) {
        await existingAnswerRef.update({
          'response': response,
          'value': response,
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
          'value': response,
          'notes': _notes[questionId] ?? '',
          'comment': _notes[questionId] ?? '',
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
        _rebuildCategoryStats();
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

  void _selectCategory(int index) {
    if (index < 0 || index >= _sections.length) return;
    setState(() {
      _selectedCategoryIndex = index;
    });
  }

  Widget _buildCategoryChip({
    required _CategorySection section,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final completed = _isCategoryComplete(section.categoryPath);
    final completedColor = const Color(0xFF16A34A);
    final textStyle = _inter(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: selected
          ? Colors.white
          : completed
              ? completedColor
              : _brandColor,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: selected
            ? const LinearGradient(
                colors: [Color(0xFF6D4BC3), Color(0xFF5A3E8E)],
              )
            : null,
        color: selected
            ? null
            : completed
                ? completedColor.withValues(alpha: 0.14)
                : _chipBgColor,
        border: Border.all(
          color: selected
              ? Colors.transparent
              : completed
                  ? completedColor.withValues(alpha: 0.22)
                  : _chipBorderColor,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!selected && completed) ...[
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  section.name,
                  style: textStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionItem(_QuestionItem question) {
    final controller = _controllerForQuestion(question.id);
    final questionStyle = _inter(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: _brandColor,
      height: 1.25,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _lineColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  question.text,
                  style: questionStyle,
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ArteziAnswerIconButton(
                    icon: Icons.check_circle_outline,
                    stateColor: const Color(0xFF16A34A),
                    selectedFillOpacity: 0.12,
                    selectedBorderOpacity: 0.20,
                    selected: _responses[question.id] == 'compliant',
                    onTap: () => _setResponse(questionId: question.id, response: 'compliant'),
                  ),
                  const SizedBox(width: 8),
                  ArteziAnswerIconButton(
                    icon: Icons.cancel_outlined,
                    stateColor: const Color(0xFFDC2626),
                    selectedFillOpacity: 0.10,
                    selectedBorderOpacity: 0.18,
                    selected: _responses[question.id] == 'non_compliant',
                    onTap: () =>
                        _setResponse(questionId: question.id, response: 'non_compliant'),
                  ),
                  const SizedBox(width: 8),
                  ArteziAnswerIconButton(
                    icon: Icons.do_not_disturb_on_outlined,
                    stateColor: const Color(0xFF6B7280),
                    selectedFillOpacity: 0.10,
                    selectedBorderOpacity: 0.18,
                    selected: _responses[question.id] == 'not_applicable',
                    onTap: () =>
                        _setResponse(questionId: question.id, response: 'not_applicable'),
                  ),
                  const SizedBox(width: 8),
                  ArteziAnswerIconButton(
                    icon: Icons.visibility_off_outlined,
                    stateColor: const Color(0xFF2563EB),
                    selectedFillOpacity: 0.10,
                    selectedBorderOpacity: 0.18,
                    selected: _responses[question.id] == 'not_observed',
                    onTap: () => _setResponse(questionId: question.id, response: 'not_observed'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: controller,
                    onChanged: (value) => _queueNoteSave(questionId: question.id, text: value),
                    onSubmitted: (value) => _setNote(questionId: question.id, note: value),
                    style: _inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: _blackColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Comentar',
                      hintStyle: _inter(
                        fontSize: 12.5,
                        color: _mutedColor,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.96),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color.fromRGBO(57, 48, 110, 0.12),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color.fromRGBO(57, 48, 110, 0.28),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              (_photoUploadingByQuestion[question.id] ?? false)
                  ? const SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : ArteziAnswerIconButton(
                      icon: Icons.photo_camera_outlined,
                      onTap: () => _handleAddPhoto(question.id),
                    ),
            ],
          ),
          _buildPhotosStrip(question.id),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final selectedSection = _selectedSection;
    final selectedProgress = _progressForSection(selectedSection);
    final selectedPercent = (selectedProgress * 100).round();

    final headerTextStyle = _inter(
      fontSize: 13,
      color: _mutedColor,
      fontWeight: FontWeight.w500,
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              Row(
                children: [
                  Expanded(
                    child: ArteziProgressBar(
                      progress: _totalQuestions == 0 ? 0 : _answeredQuestions / _totalQuestions,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${((_totalQuestions == 0 ? 0 : _answeredQuestions / _totalQuestions) * 100).round()}% concluido',
                    style: headerTextStyle,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (int i = 0; i < _sections.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        _buildCategoryChip(
                          section: _sections[i],
                          selected: i == _selectedCategoryIndex,
                          onTap: () => _selectCategory(i),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ArteziProgressBar(progress: selectedProgress),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$selectedPercent% concluido',
                    style: headerTextStyle,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (selectedSection == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'Nenhuma pergunta encontrada para esta auditoria.',
                    style: _inter(fontSize: 13, color: _mutedColor),
                  ),
                )
              else
                ...selectedSection.questions.map(_buildQuestionItem),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final answered = _answeredQuestions;
    final total = _totalQuestions;
    final allAnswered = total > 0 && answered == total;

    final appBarTextStyle = _inter(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: _blackColor,
    );

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        surfaceTintColor: _bgColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _brandColor),
        ),
        titleSpacing: 0,
        title: Text(
          _headerTitle,
          style: appBarTextStyle,
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
                      style: _inter(color: _mutedColor),
                    ),
                  ),
                )
              : _buildContent(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: _bgColor,
            border: Border(
              top: BorderSide(color: _lineColor),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _primaryButton,
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
                      child: Center(
                        child: Text(
                          'Salvar progresso',
                          style: _inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
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
                                style: _inter(
                                  color: allAnswered ? Colors.white : const Color(0xFF9A9AB0),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
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
  final String categoryPath;
  final String name;
  final int order;
  final List<_QuestionItem> questions;

  const _CategorySection({
    required this.id,
    required this.categoryPath,
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
