import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audits/services/active_template_service.dart';
import 'client_responsibilities_page.dart';

class ClientRegistrationPage extends StatefulWidget {
  final String? clientId;

  const ClientRegistrationPage({super.key, this.clientId});

  @override
  State<ClientRegistrationPage> createState() => _ClientRegistrationPageState();
}

class _ClientRegistrationPageState extends State<ClientRegistrationPage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _brandDark = Color(0xFF1B1830);
  static const Color _softBrand = Color(0xFFEEE9FF);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _fieldBg = Color(0xFFF6F6FA);

  static const List<String> _recurrenceOptions = <String>[
    'Quinzenal',
    'Mensal',
    'Bimensal',
    'Trimestral',
  ];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ActiveTemplateService _activeTemplateService = ActiveTemplateService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cnpjController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _operatorController = TextEditingController();

  final List<_ResponsibleFormItem> _responsibles = [];
  final Set<String> _clientQuestionPaths = <String>{};
  final Set<String> _allResponsibilityQuestionPaths = <String>{};

  DocumentReference? _companyRef;
  DocumentReference? _selectedAuditorRef;
  String? _selectedAuditRecurrence;
  bool _hasOperator = false;
  bool _isLoadingCompany = true;
  bool _isSaving = false;
  List<_AuditorOption> _auditors = const [];
  bool get _isEditMode => widget.clientId != null;

  Future<Set<String>> _loadAllResponsibilityQuestionPaths() async {
    final templateRef = await _activeTemplateService.resolveActiveTemplateRef();
    final questionsSnapshot = await _firestore
        .collection('questions')
        .where('templateRef', isEqualTo: templateRef)
        .orderBy('order')
        .get();
    return questionsSnapshot.docs.map((doc) => doc.reference.path).toSet();
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

  bool _parseHasOperator(Map<String, dynamic> data) {
    final dynamic raw = data.containsKey('hasOperator')
        ? data['hasOperator']
        : data['has_operator'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final value = raw.trim().toLowerCase();
      return value == 'true' || value == '1' || value == 'sim';
    }
    return false;
  }

  String _auditorLabelFromData(Map<String, dynamic>? data, String fallback) {
    final candidates = [data?['name'], data?['displayName'], data?['email']];
    for (final candidate in candidates) {
      final value = (candidate as String?)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  String _selectedAuditorLabel() {
    if (_selectedAuditorRef == null) {
      return 'Selecionar auditor responsável';
    }
    final match = _auditors.where((item) => item.ref.path == _selectedAuditorRef!.path);
    if (match.isNotEmpty) return match.first.label;
    return 'Auditora selecionada';
  }

  InputDecoration _primaryFieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: _inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF9A9EAE),
      ),
      filled: true,
      fillColor: _fieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color.fromRGBO(115, 87, 216, 0.26),
          width: 1.2,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cnpjController.dispose();
    _addressController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
      final userData = userSnapshot.data();
      _companyRef = userData?['companyref'] as DocumentReference?;
      final usersSnapshot = await _firestore.collection('users').get();
      _auditors = usersSnapshot.docs
          .map(
            (doc) => _AuditorOption(
              ref: doc.reference,
              label: _auditorLabelFromData(doc.data(), 'Usuário ${doc.id}'),
            ),
          )
          .toList()
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

      final allQuestionPaths = await _loadAllResponsibilityQuestionPaths();
      _allResponsibilityQuestionPaths
        ..clear()
        ..addAll(allQuestionPaths);

      if (_isEditMode) {
        final clientSnapshot = await _firestore.collection('clients').doc(widget.clientId).get();
        final clientData = clientSnapshot.data();
        if (clientData != null) {
          _nameController.text = ((clientData['name'] as String?) ?? '').trim();
          _cnpjController.text = ((clientData['cnpjFormatted'] as String?) ?? '').trim();
          _addressController.text = ((clientData['address'] as String?) ?? '').trim();
          _hasOperator = _parseHasOperator(clientData);
          _operatorController.text =
              ((clientData['operatorName'] ?? clientData['operator_name']) as String? ?? '').trim();
          _selectedAuditorRef = clientData['auditorRef'] as DocumentReference?;
          _selectedAuditRecurrence = (clientData['auditrecurrence'] as String?)?.trim();
          final responsibilityMap =
              (clientData['responsibilityMap'] as Map<String, dynamic>?) ??
              <String, dynamic>{};
          final operatorQuestionPaths = responsibilityMap.entries
              .where((entry) => entry.value == 'operator')
              .map((entry) => entry.key)
              .toSet();
          _clientQuestionPaths
            ..clear()
            ..addAll(_allResponsibilityQuestionPaths.difference(operatorQuestionPaths));

          final responsiblesRaw = clientData['responsibles'] as List<dynamic>?;
          _responsibles
            ..clear()
            ..addAll(
              (responsiblesRaw ?? const [])
                  .whereType<Map>()
                  .map((item) => _ResponsibleFormItem(
                        name: ((item['name'] as String?) ?? '').trim(),
                        email: ((item['email'] as String?) ?? '').trim(),
                      ))
                  .where((item) => item.name.isNotEmpty || item.email.isNotEmpty),
            );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCompany = false;
        });
      }
    }
  }

  String _cnpjDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
  }

  String? _validateForm() {
    if (_nameController.text.trim().isEmpty) return 'Informe o nome da empresa.';
    if (_cnpjDigits(_cnpjController.text).length != 14) {
      return 'Informe um CNPJ válido com 14 dígitos.';
    }
    if (_addressController.text.trim().isEmpty) return 'Informe o endereço completo.';
    if (_responsibles.isEmpty) return 'Adicione ao menos 1 responsável.';
    for (final responsible in _responsibles) {
      if (responsible.name.trim().isEmpty) return 'Todo responsável precisa ter nome.';
      if (!_isValidEmail(responsible.email)) {
        return 'Informe um e-mail válido para os responsáveis.';
      }
    }
    if (_hasOperator && _operatorController.text.trim().isEmpty) {
      return 'Informe o nome da operadora.';
    }
    if (_companyRef == null) {
      return 'Não foi possível identificar a empresa do usuário logado.';
    }
    return null;
  }

  Future<void> _addResponsible() async {
    final result = await showModalBottomSheet<_ResponsibleFormItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddResponsibleSheet(),
    );

    if (result == null || !mounted) return;
    setState(() {
      _responsibles.add(result);
    });
  }

  Future<void> _selectAuditor() async {
    final result = await showModalBottomSheet<DocumentReference>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _SelectionSheet<DocumentReference>(
        title: 'Selecionar auditor responsável',
        subtitle: 'Escolha a pessoa responsável por essa empresa.',
        options: _auditors
            .map((auditor) => _SelectionOption<DocumentReference>(value: auditor.ref, label: auditor.label))
            .toList(growable: false),
        selectedValue: _selectedAuditorRef,
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _selectedAuditorRef = result;
    });
  }

  Future<void> _selectRecurrence() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _SelectionSheet<String>(
        title: 'Selecionar recorrência',
        subtitle: 'Defina a frequência com que essa auditoria deve acontecer.',
        options: _recurrenceOptions
            .map((item) => _SelectionOption<String>(value: item, label: item))
            .toList(growable: false),
        selectedValue: _selectedAuditRecurrence,
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _selectedAuditRecurrence = result;
    });
  }

  Future<void> _saveClient() async {
    final validationError = _validateForm();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      if (_allResponsibilityQuestionPaths.isEmpty) {
        _allResponsibilityQuestionPaths.addAll(await _loadAllResponsibilityQuestionPaths());
      }
      final payload = {
        'name': _nameController.text.trim(),
        'cnpjDigits': _cnpjDigits(_cnpjController.text),
        'cnpjFormatted': _cnpjController.text.trim(),
        'address': _addressController.text.trim(),
        'responsibles': _responsibles
            .map((item) => {'name': item.name.trim(), 'email': item.email.trim()})
            .toList(growable: false),
        'hasOperator': _hasOperator,
        'operatorName': _hasOperator ? _operatorController.text.trim() : null,
        'responsibilityMap': {
          for (final questionPath in _allResponsibilityQuestionPaths)
            if (!_clientQuestionPaths.contains(questionPath)) questionPath: 'operator',
        },
        'auditorRef': _selectedAuditorRef,
        'auditrecurrence': _selectedAuditRecurrence,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (_isEditMode) {
        await _firestore.collection('clients').doc(widget.clientId).update(payload);
      } else {
        await _firestore.collection('clients').add({
          ...payload,
          'companyref': _companyRef,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditMode ? 'Cliente atualizado com sucesso.' : 'Cliente criado com sucesso.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditMode ? 'Não foi possível atualizar o cliente.' : 'Não foi possível criar o cliente.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _openResponsibilitiesEditor() async {
    final result = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => ClientResponsibilitiesPage(
          clientId: widget.clientId,
          clientName: _nameController.text.trim().isEmpty
              ? 'Cliente'
              : _nameController.text.trim(),
          initialClientQuestionPaths: _clientQuestionPaths,
          persistOnSave: false,
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _clientQuestionPaths
        ..clear()
        ..addAll(result);
    });
  }

  Future<List<_ResponsibilityPreviewItem>> _loadSelectedResponsibilityPreviewItems() async {
    if (_clientQuestionPaths.isEmpty) {
      return const <_ResponsibilityPreviewItem>[];
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

    final categoriesByPath = <String, String>{};
    for (final doc in categoriesSnapshot.docs) {
      final data = doc.data();
      categoriesByPath[doc.reference.path] =
          ((data['name'] as String?) ?? 'Sem categoria').trim();
    }

    final items = <_ResponsibilityPreviewItem>[];
    for (final doc in questionsSnapshot.docs) {
      if (!_clientQuestionPaths.contains(doc.reference.path)) continue;
      final data = doc.data();
      final categoryRef = data['categoryRef'] as DocumentReference?;
      items.add(
        _ResponsibilityPreviewItem(
          order: (data['order'] as num?)?.toInt() ?? 999999,
          categoryName: categoriesByPath[categoryRef?.path] ?? 'Sem categoria',
          text: ((data['text'] as String?) ?? 'Pergunta sem texto').trim(),
        ),
      );
    }

    items.sort((a, b) => a.order.compareTo(b.order));
    return items;
  }

  Future<void> _showResponsibilitiesPreview() async {
    final items = await _loadSelectedResponsibilityPreviewItems();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ResponsibilitiesPreviewSheet(
        clientName: _nameController.text.trim().isEmpty
            ? 'Cliente'
            : _nameController.text.trim(),
        items: items,
      ),
    );
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
                  onPressed: () => Navigator.of(context).pop(),
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
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: 32, height: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditMode ? 'Editar cliente' : 'Cadastro de cliente',
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
              'Preencha os dados do cliente e configure responsáveis e recorrência das auditorias.',
              style: _inter(
                fontSize: 14,
                height: 1.6,
                color: _mutedColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: _inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _mutedColor,
        ),
      ),
    );
  }

  Widget _buildSelectorField({
    required String label,
    required String value,
    required bool placeholder,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F171A24),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: _inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: placeholder ? const Color(0xFF9A9EAE) : _brandDark,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, color: Color(0xFF9A9EAE), size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOperatorToggle({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? _softBrand : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: _inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? _brandColor : _mutedColor,
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiblesBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Responsáveis',
              style: _inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _brandDark,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _addResponsible,
              style: IconButton.styleFrom(
                backgroundColor: _softBrand,
                foregroundColor: _brandColor,
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.add_circle, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_responsibles.isEmpty)
          Text(
            'Nenhum responsável adicionado.',
            style: _inter(fontSize: 14, color: const Color(0xFF9A9EAE)),
          )
        else
          ..._responsibles.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: _fieldBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F171A24),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: _inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _brandDark,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.email,
                          style: _inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _responsibles.removeAt(index);
                      });
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF9A9EAE),
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildOperatorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Operadora',
          style: _inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _brandDark,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F171A24),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOperatorToggle(
                label: 'Não',
                selected: !_hasOperator,
                onTap: () {
                  setState(() {
                    _hasOperator = false;
                    _operatorController.clear();
                  });
                },
              ),
              _buildOperatorToggle(
                label: 'Sim',
                selected: _hasOperator,
                onTap: () {
                  setState(() {
                    _hasOperator = true;
                  });
                },
              ),
            ],
          ),
        ),
        if (_hasOperator) ...[
          const SizedBox(height: 16),
          _buildSectionLabel('Nome da operadora'),
          TextField(
            controller: _operatorController,
            textCapitalization: TextCapitalization.words,
            style: _inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _brandDark,
            ),
            decoration: _primaryFieldDecoration('Nome da operadora'),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F171A24),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(
                'Definir responsabilidades',
                style: _inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _brandDark,
                ),
              ),
              subtitle: Text(
                _clientQuestionPaths.isEmpty
                    ? 'Nenhuma questão marcada para Cliente.'
                    : '${_clientQuestionPaths.length} questões marcadas para Cliente.',
                style: _inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _brandColor,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _showResponsibilitiesPreview,
                    style: IconButton.styleFrom(
                      foregroundColor: _brandColor,
                      minimumSize: const Size(28, 28),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _openResponsibilitiesEditor,
                    style: IconButton.styleFrom(
                      foregroundColor: _brandColor,
                      minimumSize: const Size(28, 28),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width >= 900 ? width * 0.16 : (width >= 600 ? 24.0 : 16.0);

    return Scaffold(
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
                  _buildIntro(),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoadingCompany
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 160),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dados do cliente',
                              style: _inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF34384A),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildSectionLabel('Nome do cliente'),
                            TextField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              style: _inter(fontSize: 14, fontWeight: FontWeight.w500, color: _brandDark),
                              decoration: _primaryFieldDecoration('Nome da empresa'),
                            ),
                            const SizedBox(height: 16),
                            _buildSectionLabel('CNPJ'),
                            TextField(
                              controller: _cnpjController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _CnpjInputFormatter(),
                              ],
                              style: _inter(fontSize: 14, fontWeight: FontWeight.w500, color: _brandDark),
                              decoration: _primaryFieldDecoration('00.000.000/0000-00'),
                            ),
                            const SizedBox(height: 16),
                            _buildSectionLabel('Endereço completo'),
                            TextField(
                              controller: _addressController,
                              textCapitalization: TextCapitalization.sentences,
                              style: _inter(fontSize: 14, fontWeight: FontWeight.w500, color: _brandDark),
                              decoration: _primaryFieldDecoration('Rua, número, bairro, cidade e CEP'),
                            ),
                            const SizedBox(height: 20),
                            _buildResponsiblesBlock(),
                            const SizedBox(height: 18),
                            _buildSelectorField(
                              label: 'Auditor responsável',
                              value: _selectedAuditorLabel(),
                              placeholder: _selectedAuditorRef == null,
                              onTap: _selectAuditor,
                            ),
                            const SizedBox(height: 16),
                            _buildSelectorField(
                              label: 'Recorrência da auditoria',
                              value: _selectedAuditRecurrence ?? 'Selecionar recorrência',
                              placeholder: _selectedAuditRecurrence == null,
                              onTap: _selectRecurrence,
                            ),
                            const SizedBox(height: 20),
                            _buildOperatorSection(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(horizontalPadding, 14, horizontalPadding, 16),
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveClient,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
                  : Text(
                      _isEditMode ? 'Salvar alterações' : 'Criar cliente',
                      style: _inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditorOption {
  final DocumentReference ref;
  final String label;

  const _AuditorOption({required this.ref, required this.label});
}

class _ResponsibleFormItem {
  final String name;
  final String email;

  const _ResponsibleFormItem({required this.name, required this.email});
}

class _SelectionOption<T> {
  final T value;
  final String label;

  const _SelectionOption({required this.value, required this.label});
}

class _SelectionSheet<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_SelectionOption<T>> options;
  final T? selectedValue;

  const _SelectionSheet({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selectedValue,
  });

  bool _isSelected(T optionValue) {
    if (selectedValue is DocumentReference && optionValue is DocumentReference) {
      return (selectedValue as DocumentReference).path == optionValue.path;
    }
    return selectedValue == optionValue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F171A24),
              blurRadius: 40,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: _ClientRegistrationPageState._brandDark,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              height: 1.6,
                              color: _ClientRegistrationPageState._mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF6F6FA),
                        foregroundColor: const Color(0xFF9A9EAE),
                        minimumSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final selected = _isSelected(option.value);
                      return Material(
                        color: selected ? const Color(0xFFEEE9FF) : const Color(0xFFF6F6FA),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(option.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: selected ? const Color(0xFF7357D8) : const Color(0xFF34384A),
                                    ),
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check, size: 18, color: Color(0xFF7357D8)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

class _ResponsibilityPreviewItem {
  final int order;
  final String categoryName;
  final String text;

  const _ResponsibilityPreviewItem({
    required this.order,
    required this.categoryName,
    required this.text,
  });
}

class _ResponsibilitiesPreviewSheet extends StatelessWidget {
  final String clientName;
  final List<_ResponsibilityPreviewItem> items;

  const _ResponsibilitiesPreviewSheet({
    required this.clientName,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F171A24),
              blurRadius: 40,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Responsabilidades do cliente',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: _ClientRegistrationPageState._brandDark,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            clientName,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _ClientRegistrationPageState._mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF6F6FA),
                        foregroundColor: const Color(0xFF9A9EAE),
                        minimumSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (items.isEmpty)
                  const Text(
                    'Nenhuma questão foi marcada para Cliente.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      height: 1.6,
                      color: _ClientRegistrationPageState._mutedColor,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F6FA),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Q${item.order} • ${item.categoryName}',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF7357D8),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.text,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _ClientRegistrationPageState._brandDark,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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

class _AddResponsibleSheet extends StatefulWidget {
  const _AddResponsibleSheet();

  @override
  State<_AddResponsibleSheet> createState() => _AddResponsibleSheetState();
}

class _AddResponsibleSheetState extends State<_AddResponsibleSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
  }

  InputDecoration _sheetFieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF9A9EAE),
      ),
      filled: true,
      fillColor: const Color(0xFFF6F6FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: Color.fromRGBO(115, 87, 216, 0.26),
          width: 1.2,
        ),
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _localError = 'Informe o nome.';
      });
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() {
        _localError = 'Informe um e-mail válido.';
      });
      return;
    }
    Navigator.of(context).pop(_ResponsibleFormItem(name: name, email: email));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F171A24),
              blurRadius: 40,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adicionar responsável',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: _ClientRegistrationPageState._brandDark,
                              letterSpacing: -0.4,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Preencha nome e e-mail para adicionar um novo contato.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              height: 1.6,
                              color: _ClientRegistrationPageState._mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF6F6FA),
                        foregroundColor: const Color(0xFF9A9EAE),
                        minimumSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: _ClientRegistrationPageState._brandDark),
                  decoration: _sheetFieldDecoration('Nome'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: _ClientRegistrationPageState._brandDark),
                  decoration: _sheetFieldDecoration('E-mail'),
                ),
                if (_localError != null) ...[
                  const SizedBox(height: 12),
                  Text(_localError!, style: const TextStyle(fontFamily: 'Inter', color: Color(0xFFDC2626))),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ClientRegistrationPageState._brandColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: _submit,
                    child: const Text(
                      'Adicionar',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
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
}

class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final trimmed = digits.length > 14 ? digits.substring(0, 14) : digits;
    final buffer = StringBuffer();

    for (int i = 0; i < trimmed.length; i++) {
      if (i == 2 || i == 5) buffer.write('.');
      if (i == 8) buffer.write('/');
      if (i == 12) buffer.write('-');
      buffer.write(trimmed[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

