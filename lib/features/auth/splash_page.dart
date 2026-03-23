import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../home/home_entry_page.dart';
import 'login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _timer;
  bool _delayDone = false;
  bool _authResolved = false;
  bool _hasNavigated = false;
  User? _resolvedUser;

  @override
  void initState() {
    super.initState();

    _timer = Timer(const Duration(seconds: 2), () {
      _delayDone = true;
      _tryNavigate();
    });

    FirebaseAuth.instance
        .authStateChanges()
        .first
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => FirebaseAuth.instance.currentUser,
        )
        .then((user) {
          _resolvedUser = user;
          _authResolved = true;
          _tryNavigate();
        })
        .catchError((_) {
          _resolvedUser = FirebaseAuth.instance.currentUser;
          _authResolved = true;
          _tryNavigate();
        });
  }

  void _tryNavigate() {
    if (_hasNavigated || !_delayDone || !_authResolved || !mounted) return;
    _hasNavigated = true;

    Navigator.pushReplacement(
      context,
        MaterialPageRoute(
          builder: (_) =>
            _resolvedUser != null ? const HomeEntryPage() : const LoginPage(),
        ),
      );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF11131A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1624), Color(0xFF141821)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.2, -0.4),
                  radius: 0.8,
                  colors: [Color(0x2A6D4BC3), Colors.transparent],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
          const Center(
            child: Image(
              image: AssetImage('assets/logo-artezi.png'),
              width: 220,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}
