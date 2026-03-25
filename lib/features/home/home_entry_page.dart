import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_page.dart';
import 'auditor_home_page.dart';
import 'home_page.dart';

class HomeEntryPage extends StatelessWidget {
  const HomeEntryPage({super.key});

  Future<String?> _loadRole(User user) async {
    final firestore = FirebaseFirestore.instance;

    try {
      final snapshot = await firestore.collection('users').doc(user.uid).get();
      return (snapshot.data()?['role'] as String?)?.trim().toLowerCase();
    } on FirebaseException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    return FutureBuilder<String?>(
      future: _loadRole(user),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFFF7F7FB),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF7357D8)),
            ),
          );
        }

        final role = snapshot.data;
        if (role == 'admin') {
          return const HomePage();
        }
        return const AuditorHomePage();
      },
    );
  }
}
