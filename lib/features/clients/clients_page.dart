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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  DocumentReference? _companyRef;
  bool _isLoading = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadCompanyRef();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
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

  bool _matchesSearch(Map<String, dynamic> data) {
    final raw = _searchController.text.trim();
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F5F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final companyRef = _companyRef;
    if (companyRef == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F5F5),
        body: Center(
          child: Text(
            'Nao foi possivel identificar a empresa.',
            style: TextStyle(color: Color(0xFF8A8FA3)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF7262C2)),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar por nome ou CNPJ',
                  hintStyle: TextStyle(color: Color(0xFF8A8FA3), fontSize: 14),
                  border: InputBorder.none,
                ),
                style: const TextStyle(
                  color: Color(0xFF1C1C1C),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              )
            : const Text(
                'Clientes',
                style: TextStyle(
                  color: Color(0xFF1C1C1C),
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _isSearching = false;
                } else {
                  _isSearching = true;
                }
              });
            },
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: const Color(0xFF7262C2),
            ),
          ),
          IconButton(
            onPressed: () => _openRegistration(),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEDE9FE),
              foregroundColor: const Color(0xFF7262C2),
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.add),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE6E6EF)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
            return const Center(
              child: Text(
                'Erro ao carregar clientes.',
                style: TextStyle(color: Color(0xFF8A8FA3)),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? const [];
          final filtered = docs.where((doc) => _matchesSearch(doc.data())).toList()
            ..sort((a, b) {
              final aName = ((a.data()['name'] as String?) ?? '').toLowerCase();
              final bName = ((b.data()['name'] as String?) ?? '').toLowerCase();
              return aName.compareTo(bName);
            });

          if (filtered.isEmpty) {
            return const Center(
              child: Text(
                'Nenhum cliente encontrado.',
                style: TextStyle(color: Color(0xFF8A8FA3)),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE6E6EF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFEEF0F6),
                ),
                itemBuilder: (context, index) {
                  final doc = filtered[index];
                  final data = doc.data();
                  final name = ((data['name'] as String?) ?? '').trim();
                  final cnpj =
                      (((data['cnpjFormatted'] as String?) ?? '').trim().isNotEmpty)
                      ? (data['cnpjFormatted'] as String).trim()
                      : '--';

                  return SizedBox(
                    height: 72,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? 'Cliente sem nome' : name,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1C1C1C),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cnpj,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF8A8FA3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _openRegistration(clientId: doc.id),
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Color(0xFF7262C2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
