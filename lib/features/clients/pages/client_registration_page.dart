import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client_responsibilities_page.dart';

class ClientRegistrationPage extends StatefulWidget {
  final String? clientId;

  const ClientRegistrationPage({super.key, this.clientId});

  @override
  State<ClientRegistrationPage> createState() => _ClientRegistrationPageState();
}

class _ClientRegistrationPageState extends State<ClientRegistrationPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cnpjController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _operatorController = TextEditingController();

  final List<_ResponsibleFormItem> _responsibles = [];

  DocumentReference? _companyRef;
  bool _hasOperator = false;
  bool _isAdmin = false;
  bool _isLoadingCompany = true;
  bool _isSaving = false;
  bool get _isEditMode => widget.clientId != null;

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

  InputDecoration _primaryFieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Color(0xFF9AA0B2),
      ),
      filled: true,
      fillColor: const Color(0xFFF8F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6E6EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color.fromRGBO(57, 48, 110, 0.28),
          width: 1.2,
        ),
      ),
    );
  }

  Widget _buildHeader(double horizontalPadding) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE6E6EF),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 4),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                padding: const EdgeInsets.only(left: 6, right: 8),
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Color(0xFF39306E),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Image.asset(
                'assets/logo-escura.png',
                height: 30,
                fit: BoxFit.contain,
              ),
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: 48, height: 48),
            ),
          ],
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
      final role = (userData?['role'] as String?)?.trim().toLowerCase();
      _isAdmin = role == 'admin';

      if (_isEditMode) {
        final clientSnapshot =
            await _firestore.collection('clients').doc(widget.clientId).get();
        final clientData = clientSnapshot.data();
        if (clientData != null) {
          _nameController.text = ((clientData['name'] as String?) ?? '').trim();
          _cnpjController.text =
              ((clientData['cnpjFormatted'] as String?) ?? '').trim();
          _addressController.text =
              ((clientData['address'] as String?) ?? '').trim();
          _hasOperator = _parseHasOperator(clientData);
          _operatorController.text =
              ((clientData['operatorName'] ??
                          clientData['operator_name']) as String? ??
                      '')
                  .trim();

          final responsiblesRaw = clientData['responsibles'] as List<dynamic>?;
          _responsibles
            ..clear()
            ..addAll(
              (responsiblesRaw ?? const [])
                  .whereType<Map>()
                  .map((item) {
                    final name = (item['name'] as String?) ?? '';
                    final email = (item['email'] as String?) ?? '';
                    return _ResponsibleFormItem(
                      name: name.trim(),
                      email: email.trim(),
                    );
                  })
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

  String _cnpjDigits(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
  }

  String? _validateForm() {
    if (_nameController.text.trim().isEmpty) {
      return 'Informe o nome da empresa.';
    }
    if (_cnpjDigits(_cnpjController.text).length != 14) {
      return 'Informe um CNPJ valido com 14 digitos.';
    }
    if (_addressController.text.trim().isEmpty) {
      return 'Informe o endereco completo.';
    }
    if (_responsibles.isEmpty) {
      return 'Adicione ao menos 1 responsavel.';
    }
    for (final responsible in _responsibles) {
      if (responsible.name.trim().isEmpty) {
        return 'Todo responsavel precisa ter nome.';
      }
      if (!_isValidEmail(responsible.email)) {
        return 'Informe um e-mail valido para os responsaveis.';
      }
    }
    if (_hasOperator && _operatorController.text.trim().isEmpty) {
      return 'Informe o nome da operadora.';
    }
    if (_companyRef == null) {
      return 'Nao foi possivel identificar a empresa do usuario logado.';
    }
    return null;
  }

  Future<void> _addResponsible() async {
    final result = await showModalBottomSheet<_ResponsibleFormItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => const _AddResponsibleSheet(),
    );

    if (result == null || !mounted) return;
    setState(() {
      _responsibles.add(result);
    });
  }

  Future<void> _saveClient() async {
    final validationError = _validateForm();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final cnpjDigits = _cnpjDigits(_cnpjController.text);
      final payload = {
        'name': _nameController.text.trim(),
        'cnpjDigits': cnpjDigits,
        'cnpjFormatted': _cnpjController.text.trim(),
        'address': _addressController.text.trim(),
        'responsibles': _responsibles
            .map((item) => {
                  'name': item.name.trim(),
                  'email': item.email.trim(),
                })
            .toList(growable: false),
        'hasOperator': _hasOperator,
        'operatorName': _hasOperator ? _operatorController.text.trim() : null,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (_isEditMode) {
        await _firestore
            .collection('clients')
            .doc(widget.clientId)
            .update(payload);
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
            _isEditMode
                ? 'Cliente atualizado com sucesso.'
                : 'Cliente criado com sucesso.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel criar o cliente.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width >= 900 ? width * 0.16 : (width >= 600 ? 24.0 : 16.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(horizontalPadding),
            const SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _isEditMode ? 'Editar Cliente' : 'Cadastro de Cliente',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1C),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoadingCompany
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE6E6EF)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 52,
                                child: TextField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B7280),
                                  ),
                                  decoration: _primaryFieldDecoration('Nome da empresa'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 52,
                                child: TextField(
                                  controller: _cnpjController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B7280),
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    _CnpjInputFormatter(),
                                  ],
                                  decoration: _primaryFieldDecoration('CNPJ'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 52,
                                child: TextField(
                                  controller: _addressController,
                                  textCapitalization: TextCapitalization.sentences,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B7280),
                                  ),
                                  decoration: _primaryFieldDecoration('Endereco completo'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Text(
                                    'Responsaveis',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1C1C1C),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: _addResponsible,
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      color: Color(0xFF39306E),
                                    ),
                                  ),
                                ],
                              ),
                              if (_responsibles.isEmpty)
                                const Text(
                                  'Nenhum responsavel adicionado.',
                                  style: TextStyle(
                                    color: Color(0xFF8A8FA3),
                                    fontSize: 12,
                                  ),
                                )
                              else
                                ..._responsibles.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final item = entry.value;
                                  return Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8F8FC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE6E6EF)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                item.email,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF8A8FA3),
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
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Color(0xFF8A8FA3),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              const SizedBox(height: 16),
                              const Text(
                                'Possui operadora?',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1C1C1C),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ChoiceChip(
                                    checkmarkColor: Colors.white,
                                    label: Text(
                                      'Nao',
                                      style: TextStyle(
                                        color: !_hasOperator
                                            ? Colors.white
                                            : const Color(0xFF6B7280),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    selected: !_hasOperator,
                                    selectedColor: const Color(0xFF7262C2),
                                    backgroundColor: const Color(0xFFE5E7EB),
                                    side: BorderSide(
                                      color: !_hasOperator
                                          ? const Color(0xFF7262C2)
                                          : const Color(0xFFD1D5DB),
                                    ),
                                    onSelected: (_) {
                                      setState(() {
                                        _hasOperator = false;
                                        _operatorController.clear();
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    checkmarkColor: Colors.white,
                                    label: Text(
                                      'Sim',
                                      style: TextStyle(
                                        color: _hasOperator
                                            ? Colors.white
                                            : const Color(0xFF6B7280),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    selected: _hasOperator,
                                    selectedColor: const Color(0xFF7262C2),
                                    backgroundColor: const Color(0xFFE5E7EB),
                                    side: BorderSide(
                                      color: _hasOperator
                                          ? const Color(0xFF7262C2)
                                          : const Color(0xFFD1D5DB),
                                    ),
                                    onSelected: (_) {
                                      setState(() {
                                        _hasOperator = true;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              if (_hasOperator) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 52,
                                  child: TextField(
                                    controller: _operatorController,
                                    textCapitalization: TextCapitalization.words,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF6B7280),
                                    ),
                                    decoration: _primaryFieldDecoration('Nome da operadora'),
                                  ),
                                ),
                              ],
                              if (_isAdmin) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      if (!_isEditMode) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Salve o cliente antes de definir responsabilidades.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ClientResponsibilitiesPage(
                                            clientId: widget.clientId!,
                                            clientName: _nameController.text.trim().isEmpty
                                                ? 'Cliente'
                                                : _nameController.text.trim(),
                                          ),
                                        ),
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF39306E),
                                      backgroundColor: const Color(0xFFF1EEFF),
                                      side: const BorderSide(color: Color(0xFF6D4BC3)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Definir responsabilidades'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveClient,
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
                  : Text(
                      _isEditMode ? 'Salvar alteracoes' : 'Criar Cliente',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponsibleFormItem {
  final String name;
  final String email;

  const _ResponsibleFormItem({
    required this.name,
    required this.email,
  });
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
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Color(0xFF9AA0B2),
      ),
      filled: true,
      fillColor: const Color(0xFFF8F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6E6EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color.fromRGBO(57, 48, 110, 0.28),
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
        _localError = 'Informe um e-mail valido.';
      });
      return;
    }
    Navigator.of(context).pop(_ResponsibleFormItem(name: name, email: email));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adicionar responsavel',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1C),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
              decoration: _sheetFieldDecoration('Nome'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
              decoration: _sheetFieldDecoration('E-mail'),
            ),
          ),
          if (_localError != null) ...[
            const SizedBox(height: 10),
            Text(
              _localError!,
              style: const TextStyle(color: Color(0xFFDC2626)),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7262C2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _submit,
              child: const Text('Adicionar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
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
