import 'package:flutter/material.dart';
import '../features/auth/splash_page.dart';

class AuditApp extends StatelessWidget {
  const AuditApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audit App',
      debugShowCheckedModeBanner: false,
      home: const SplashPage(),
    );
  }
}
