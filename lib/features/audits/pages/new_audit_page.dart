import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/audit_fill_page.dart';
import '../services/audit_creation_service.dart';

class NewAuditPage extends StatefulWidget {
  const NewAuditPage({super.key});

  @override
  State<NewAuditPage> createState() => _NewAuditPageState();
}

class _NewAuditPageState extends State<NewAuditPage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _brandDark = Color(0xFF1B1830);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _surfaceSoft = Color(0xFFF6F6FA);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuditCreationService _creationService = AuditCreationService();
  final TextEditingController _clientSearchController = TextEditingController();
  final FocusNode _clientFocusNode = FocusNode();

  DocumentReference? _companyRef;
  DocumentReference? _selectedClientRef;
  String? _selectedClientName;
  DateTime _chosenDate = DateTime.now();
  int? _previewAuditNumber;
  bool _isLoading = true;
  bool _isCreating = false;
  List<_ClientOption> _clientResults = const [];
  int _searchRequestId = 0;

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

  @override
  void initState() {
    super.initState();
    _chosenDate = DateTime(_chosenDate.year, _chosenDate.month, _chosenDate.day);
    _clientSearchController.addListener(_onClientSearchChanged);
    _clientFocusNode.addListener(_onClientFocusChanged);
    _loadInitialData();
  }

  @override
  void dispose() {
    _clientSearchController.removeListener(_onClientSearchChanged);
    _clientFocusNode.removeListener(_onClientFocusChanged);
    _clientSearchController.dispose();
    _clientFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
      final userData = userSnapshot.data();
      _companyRef = userData?['companyref'] as DocumentReference?;

      final counterSnapshot = await _firestore.collection('counters').doc('audits').get();
      final counterData = counterSnapshot.data();
      final current = (counterData?['currentNumber'] as num?)?.toInt() ?? 0;
      _previewAuditNumber = current + 1;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onClientSearchChanged() {
    final query = _clientSearchController.text.trim();
    if (_selectedClientName != null && query != _selectedClientName) {
      _selectedClientName = null;
      _selectedClientRef = null;
    }
    _searchClients(query);
  }

  void _onClientFocusChanged() {
    if (!_clientFocusNode.hasFocus && mounted) {
      setState(() {
        _clientResults = const [];
      });
    }
  }

  Future<void> _searchClients(String query) async {
    final companyRef = _companyRef;
    if (companyRef == null) {
      if (mounted) {
        setState(() {
          _clientResults = const [];
        });
      }
      return;
    }

    final requestId = ++_searchRequestId;
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _clientResults = const [];
        });
      }
      return;
    }

    bool shouldFallback = false;
    List<_ClientOption> prefixResults = const [];

    try {
      final prefixSnapshot = await _firestore
          .collection('clients')
          .where('companyref', isEqualTo: companyRef)
          .orderBy('name')
          .startAt([query])
          .endAt(['$query\uf8ff'])
          .limit(6)
          .get();

      prefixResults = prefixSnapshot.docs
          .map((doc) => _ClientOption.fromSnapshot(doc))
          .toList(growable: false);

      shouldFallback = prefixResults.isEmpty;
    } catch (e) {
      debugPrint('prefix clients error: $e');
      shouldFallback = true;
    }

    if (!shouldFallback) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _clientResults = prefixResults;
      });
      return;
    }

    try {
      final fallbackSnapshot = await _firestore
          .collection('clients')
          .where('companyref', isEqualTo: companyRef)
          .limit(200)
          .get();

      if (!mounted || requestId != _searchRequestId) return;

      final queryLower = query.toLowerCase();
      final filtered = fallbackSnapshot.docs
          .map((doc) => _ClientOption.fromSnapshot(doc))
          .where((client) => client.name.toLowerCase().contains(queryLower))
          .toList(growable: false)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      setState(() {
        _clientResults = filtered.take(6).toList(growable: false);
      });
    } catch (e) {
      debugPrint('fallback clients error: $e');
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _clientResults = const [];
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _chosenDate.isAfter(today) ? today : _chosenDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today.subtract(const Duration(days: 3650)),
      lastDate: today,
      locale: const Locale('pt', 'BR'),
    );

    if (picked == null) return;
    setState(() {
      _chosenDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _handleCreate({required bool draft}) async {
    final user = FirebaseAuth.instance.currentUser;
    final selectedClientRef = _selectedClientRef;
    if (user == null || selectedClientRef == null || _isCreating) return;

    setState(() {
      _isCreating = true;
    });

    try {
      final auditId = await _creationService.createAudit(
        uid: user.uid,
        clientRef: selectedClientRef,
        chosenDate: _chosenDate,
        draft: draft,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AuditFillPage(auditId: auditId)),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.toString(),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível criar a auditoria.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  String _formatPreviewCode() {
    final number = _previewAuditNumber;
    if (number == null) return 'ART-0000';
    return 'ART-${number.toString().padLeft(4, '0')}';
  }

  String _formatShortDate(DateTime date) {
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    final day = date.day.toString().padLeft(2, '0');
    final month = months[date.month - 1];
    final year = date.year.toString().substring(2);
    return '$day $month $year';
  }

  Widget _buildHeader() {
    return Padding(
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
              child: SizedBox(width: 40, height: 40),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nova auditoria',
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
              'Selecione o cliente e defina a data para iniciar a auditoria.',
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

  @override
  Widget build(BuildContext context) {
    final canSubmit = _selectedClientRef != null && !_isCreating && !_isLoading;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() {
          _clientResults = const [];
        });
      },
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
                    _buildIntro(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
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
                        Container(
                          decoration: BoxDecoration(
                            color: _surfaceSoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _pickDate,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'ID: ${_formatPreviewCode()}',
                                        style: _inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: _brandColor,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatShortDate(_chosenDate),
                                      style: _inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: _mutedColor,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.calendar_month,
                                      size: 22,
                                      color: _brandColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_selectedClientRef == null) ...[
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: _surfaceSoft,
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
                              controller: _clientSearchController,
                              focusNode: _clientFocusNode,
                              style: _inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _brandDark,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Buscar cliente...',
                                hintStyle: _inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF9A9EAE),
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Color(0xFF9A9EAE),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFEEF0F6)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Cliente',
                                        style: _inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: _mutedColor,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _selectedClientName ?? 'Cliente sem nome',
                                        style: _inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: _brandDark,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedClientRef = null;
                                      _selectedClientName = null;
                                      _clientSearchController.clear();
                                      _clientResults = const [];
                                    });
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: _brandColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Trocar',
                                    style: _inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _brandColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_selectedClientRef == null && _clientResults.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ...List.generate(_clientResults.length, (index) {
                            final client = _clientResults[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == _clientResults.length - 1 ? 0 : 12,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0F171A24),
                                      blurRadius: 24,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () {
                                      setState(() {
                                        _selectedClientRef = client.ref;
                                        _selectedClientName = client.name;
                                        _clientSearchController.text = client.name;
                                        _clientResults = const [];
                                      });
                                      _clientFocusNode.unfocus();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 18,
                                      ),
                                      child: Text(
                                        client.name,
                                        style: _inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: _brandDark,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                    ),
                  ),
                ],
              ),
            ),
            if (canSubmit)
              SafeArea(
                top: false,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _brandColor,
                        borderRadius: BorderRadius.circular(22),
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
                          borderRadius: BorderRadius.circular(22),
                          onTap: _isCreating
                              ? null
                              : () => _handleCreate(draft: false),
                          child: Center(
                            child: _isCreating
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Criar auditoria',
                                    style: _inter(
                                      fontSize: 16,
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
          ],
        ),
      ),
    );
  }
}

class _ClientOption {
  final String name;
  final DocumentReference ref;

  const _ClientOption({
    required this.name,
    required this.ref,
  });

  factory _ClientOption.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final name = (data['name'] as String?)?.trim();
    return _ClientOption(
      name: (name == null || name.isEmpty) ? 'Sem nome' : name,
      ref: snapshot.reference,
    );
  }
}
