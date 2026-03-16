import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'pages/client_registration_page.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  static const Color _bgColor = Color(0xFFF7F7FB);
  static const Color _brandColor = Color(0xFF7357D8);
  static const Color _brandDark = Color(0xFF1B1830);
  static const Color _mutedColor = Color(0xFF72778A);
  static const Color _softBrand = Color(0xFFEEE9FF);
  static const Color _surfaceSoft = Color(0xFFF6F6FA);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  DocumentReference? _companyRef;
  bool _isLoading = true;

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
    _loadCompanyRef();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanyRef() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final userDoc = await _firestore.collection('users').doc(uid).get();
      _companyRef = userDoc.data()?['companyref'] as DocumentReference?;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  bool _matchesSearch(Map<String, dynamic> data, String raw) {
    if (raw.isEmpty) return true;

    final queryLower = raw.toLowerCase();
    final queryDigits = _digitsOnly(raw);

    final name = ((data['name'] as String?) ?? '').toLowerCase();
    final cnpjFormatted = ((data['cnpjFormatted'] as String?) ?? '').toLowerCase();
    final cnpjDigits = _digitsOnly((data['cnpjDigits'] as String?) ?? '');

    if (name.contains(queryLower)) return true;
    if (cnpjFormatted.contains(queryLower)) return true;
    if (queryDigits.isNotEmpty && cnpjDigits.contains(queryDigits)) return true;
    return false;
  }

  Future<void> _openRegistration({String? clientId}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientRegistrationPage(clientId: clientId),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
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
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => _openRegistration(),
                    style: IconButton.styleFrom(
                      backgroundColor: _softBrand,
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
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clientes',
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
              'Gerencie os clientes cadastrados, pesquise rapidamente e atualize informações quando necessário.',
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
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: _inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _brandDark,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar cliente ou CNPJ...',
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

  Widget _buildClientCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = ((data['name'] as String?) ?? '').trim();
    final cnpj = (((data['cnpjFormatted'] as String?) ?? '').trim().isNotEmpty)
        ? (data['cnpjFormatted'] as String).trim()
        : '--';

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Cliente sem nome' : name,
                    style: _inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _brandDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cnpj,
                    style: _inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _mutedColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => _openRegistration(clientId: doc.id),
              style: IconButton.styleFrom(
                backgroundColor: _softBrand,
                foregroundColor: _brandColor,
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final companyRef = _companyRef;
    if (companyRef == null) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(
          child: Text(
            'Não foi possível identificar a empresa.',
            style: TextStyle(color: _mutedColor),
          ),
        ),
      );
    }

    final rawSearch = _searchController.text.trim();

    return Scaffold(
      backgroundColor: _bgColor,
      body: Column(
        children: [
          _buildHeader(),
          _buildIntro(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('clients')
                  .where('companyref', isEqualTo: companyRef)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  debugPrint('ClientsPage stream error: ${snapshot.error}');
                  return Center(
                    child: Text(
                      'Erro ao carregar clientes.',
                      style: _inter(color: _mutedColor),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                final filtered = docs.where((doc) => _matchesSearch(doc.data(), rawSearch)).toList()
                  ..sort((a, b) {
                    final aName = ((a.data()['name'] as String?) ?? '').toLowerCase();
                    final bName = ((b.data()['name'] as String?) ?? '').toLowerCase();
                    return aName.compareTo(bName);
                  });

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhum cliente encontrado.',
                      style: _inter(color: _mutedColor),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    return _buildClientCard(filtered[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
