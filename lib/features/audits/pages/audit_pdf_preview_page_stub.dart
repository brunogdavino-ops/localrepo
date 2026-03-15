import 'package:flutter/material.dart';

class AuditPdfPreviewPage extends StatelessWidget {
  final String filePath;

  const AuditPdfPreviewPage({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F5F5),
        surfaceTintColor: const Color(0xFFF6F5F5),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF39306E)),
        ),
        title: const Text(
          'Preview do relatorio',
          style: TextStyle(
            color: Color(0xFF1C1C1C),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Preview interno indisponivel nesta plataforma.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8A8FA3),
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
