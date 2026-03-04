import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/audit_fill_page.dart';
import '../services/audit_creation_service.dart';

class NewAuditPage extends StatefulWidget {
  const NewAuditPage({Key? key}) : super(key: key);

  @override
  State<NewAuditPage> createState() => _NewAuditPageState();
}

class _NewAuditPageState extends State<NewAuditPage> {
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

    final int requestId = ++_searchRequestId;
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nao foi possivel criar a auditoria.',
            style: TextStyle(),
          ),
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
      'dez'
    ];
    final day = date.day.toString().padLeft(2, '0');
    final month = months[date.month - 1];
    final year = date.year.toString().substring(2);
    return '$day $month $year';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width >= 900 ? width * 0.16 : (width >= 600 ? 24.0 : 16.0);
    final canSubmit = _selectedClientRef != null && !_isCreating && !_isLoading;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() {
          _clientResults = const [];
        });
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF6F5F5),
      body: SafeArea(
        child: Column(
          children: [
            Container(
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
                        icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF39306E)),
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
            ),
            const SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nova auditoria',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1C1C),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 16),
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F1F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'ID: ${_formatPreviewCode()}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF39306E),
                                  ),
                                ),
                              ),
                              Text(
                                _formatShortDate(_chosenDate),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: const Color(0xFF8A8FA3),
                                ),
                              ),
                              IconButton(
                                onPressed: _pickDate,
                                icon: const Icon(
                                  Icons.calendar_month_outlined,
                                  color: Color(0xFF39306E),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_selectedClientRef == null) ...[
                          TextField(
                            controller: _clientSearchController,
                            focusNode: _clientFocusNode,
                            style: TextStyle(
                              fontSize: 14,
                              color: const Color(0xFF1C1C1C),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Buscar cliente...',
                              hintStyle: TextStyle(
                                color: const Color(0xFF8A8FA3),
                                fontSize: 14,
                              ),
                              prefixIcon: const Icon(Icons.search, color: Color(0xFF8A8FA3)),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Color(0xFFE6E6EF)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF6D4BC3),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE6E6EF)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Cliente',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: const Color(0xFF8A8FA3),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _selectedClientName ?? 'Cliente sem nome',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: const Color(0xFF1C1C1C),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Trocar',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF5A3E8E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_selectedClientRef == null && _clientResults.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 280),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE6E6EF)),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _clientResults.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                thickness: 1,
                                color: Color(0xFFE6E6EF),
                              ),
                              itemBuilder: (context, index) {
                                final client = _clientResults[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    client.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: const Color(0xFF1C1C1C),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _selectedClientRef = client.ref;
                                      _selectedClientName = client.name;
                                      _clientSearchController.text = client.name;
                                      _clientResults = const [];
                                    });
                                    _clientFocusNode.unfocus();
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 16),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: canSubmit ? const Color(0xFF7262C2) : const Color(0xFFDCDCE6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: canSubmit ? () => _handleCreate(draft: false) : null,
                            child: Center(
                              child: _isCreating
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Text(
                                      'Criar auditoria',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: canSubmit
                                            ? Colors.white
                                            : const Color(0xFF9A9AB0),
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
          ],
        ),
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
