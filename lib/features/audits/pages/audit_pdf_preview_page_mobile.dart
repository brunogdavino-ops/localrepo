import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

import '../services/audit_pdf_service.dart';

class AuditPdfPreviewPage extends StatefulWidget {
  final String filePath;

  const AuditPdfPreviewPage({super.key, required this.filePath});

  @override
  State<AuditPdfPreviewPage> createState() => _AuditPdfPreviewPageState();
}

class _AuditPdfPreviewPageState extends State<AuditPdfPreviewPage> {
  final AuditPdfService _auditPdfService = AuditPdfService();
  bool _isSharing = false;
  bool _isReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _validateFile();
  }

  @override
  void dispose() {
    _auditPdfService.dispose();
    super.dispose();
  }

  Future<void> _validateFile() async {
    final file = File(widget.filePath);
    final exists = await file.exists();
    if (!mounted) return;

    if (!exists) {
      setState(() {
        _error = 'Arquivo de preview do PDF nao encontrado.';
      });
    }
  }

  Future<void> _handleShare() async {
    if (_isSharing) return;

    setState(() {
      _isSharing = true;
    });

    try {
      await _auditPdfService.sharePdf(widget.filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF pronto para compartilhamento.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao compartilhar o PDF.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

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
        actions: [
          IconButton(
            onPressed: _isSharing ? null : _handleShare,
            icon: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF39306E),
                      ),
                    ),
                  )
                : const Icon(
                    Icons.ios_share_outlined,
                    color: Color(0xFF39306E),
                  ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFF4F0FF)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE3DBFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8A8FA3),
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    PDFView(
                      filePath: widget.filePath,
                      autoSpacing: true,
                      pageFling: true,
                      pageSnap: true,
                      fitEachPage: true,
                      onRender: (_) {
                        if (!mounted) return;
                        setState(() {
                          _isReady = true;
                        });
                      },
                      onError: (error) {
                        if (!mounted) return;
                        setState(() {
                          _error = 'Nao foi possivel abrir o preview do PDF.';
                        });
                      },
                    ),
                    if (!_isReady)
                      const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF6D4BC3),
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
