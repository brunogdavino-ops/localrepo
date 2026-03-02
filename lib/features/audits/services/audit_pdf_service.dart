import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

typedef GeneratePdfCallable =
    Future<Map<String, dynamic>> Function(String auditId);
typedef TempDirProvider = Future<Directory> Function();

class PdfDownloadException implements Exception {
  PdfDownloadException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'PdfDownloadException(statusCode: $statusCode)';
}

class AuditPdfService {
  AuditPdfService({
    FirebaseFunctions? functions,
    http.Client? httpClient,
    TempDirProvider? tempDirProvider,
    GeneratePdfCallable? generatePdfCallable,
  }) : _functions = functions ?? FirebaseFunctions.instance,
       _httpClient = httpClient ?? http.Client(),
       _tempDirProvider = tempDirProvider ?? _defaultTempDirProvider,
       _generatePdfCallable = generatePdfCallable;

  final FirebaseFunctions _functions;
  final http.Client _httpClient;
  final TempDirProvider _tempDirProvider;
  final GeneratePdfCallable? _generatePdfCallable;

  Future<String> generatePdfUrl(String auditId) async {
    final data = _generatePdfCallable == null
        ? await _defaultGeneratePdfCallable(auditId)
        : await _generatePdfCallable(auditId);

    final url = (data['url'] as String?)?.trim();
    final downloadUrl = (data['downloadUrl'] as String?)?.trim();
    final resolvedUrl = (url != null && url.isNotEmpty)
        ? url
        : ((downloadUrl != null && downloadUrl.isNotEmpty)
              ? downloadUrl
              : null);
    if (resolvedUrl == null) {
      throw StateError(
        'Resposta invalida da funcao: campo url ausente ou vazio.',
      );
    }
    return resolvedUrl;
  }

  Future<String> downloadPdf(String url) async {
    final uri = Uri.parse(url);
    final response = await _httpClient.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PdfDownloadException(response.statusCode);
    }

    final tempDir = await _tempDirProvider();
    final filePath =
        '${tempDir.path}${Platform.pathSeparator}auditoria_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<void> sharePdf(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('Arquivo de PDF nao encontrado para compartilhamento.');
    }
    await Share.shareXFiles([XFile(file.path)], text: 'Relatorio de auditoria');
  }

  Future<Map<String, dynamic>> _defaultGeneratePdfCallable(
    String auditId,
  ) async {
    final callable = _functions.httpsCallable('generateAuditPdf');
    final result = await callable.call<Map<String, dynamic>>({
      'auditId': auditId,
    });
    return Map<String, dynamic>.from(result.data);
  }

  void dispose() {
    _httpClient.close();
  }

  static Future<Directory> _defaultTempDirProvider() async {
    return Directory.systemTemp;
  }
}
