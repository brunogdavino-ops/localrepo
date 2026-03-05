import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'audit_pdf_platform_io.dart'
    if (dart.library.html) 'audit_pdf_platform_web.dart' as pdf_platform;

typedef GeneratePdfCallable = Future<Map<String, dynamic>> Function(String auditId);
typedef SharePdfFileCallback = Future<void> Function(String filePath);
typedef OpenPdfUrlCallback = Future<void> Function(String url);

class PdfDownloadException implements Exception {
  PdfDownloadException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'PdfDownloadException(statusCode: $statusCode)';
}

class PdfSessionExpiredException implements Exception {
  const PdfSessionExpiredException();

  @override
  String toString() => 'PdfSessionExpiredException';
}

class AuditPdfService {
  AuditPdfService({
    FirebaseFunctions? functions,
    http.Client? httpClient,
    GeneratePdfCallable? generatePdfCallable,
    SharePdfFileCallback? sharePdfFile,
    OpenPdfUrlCallback? openPdfUrl,
  }) : _functions = functions,
       _httpClient = httpClient ?? http.Client(),
       _generatePdfCallable = generatePdfCallable,
       _sharePdfFile = sharePdfFile ?? pdf_platform.sharePdfFile,
       _openPdfUrl = openPdfUrl ?? pdf_platform.openPdfUrl;

  final FirebaseFunctions? _functions;
  final http.Client _httpClient;
  final GeneratePdfCallable? _generatePdfCallable;
  final SharePdfFileCallback _sharePdfFile;
  final OpenPdfUrlCallback _openPdfUrl;

  bool get supportsFileDownload => pdf_platform.supportsFileDownload;

  Future<String> generatePdfUrl(String auditId) async {
    final data = _generatePdfCallable == null
        ? await _defaultGeneratePdfCallable(auditId)
        : await _generatePdfCallable(auditId);

    final url = (data['url'] as String?)?.trim();
    final downloadUrl = (data['downloadUrl'] as String?)?.trim();
    final resolvedUrl = (url != null && url.isNotEmpty)
        ? url
        : ((downloadUrl != null && downloadUrl.isNotEmpty) ? downloadUrl : null);
    if (resolvedUrl == null) {
      throw StateError('Resposta invalida da funcao: campo url ausente ou vazio.');
    }
    return resolvedUrl;
  }

  Future<String> downloadPdf(String url) async {
    final uri = Uri.parse(url);
    final response = await _httpClient.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PdfDownloadException(response.statusCode);
    }
    return pdf_platform.savePdfBytes(response.bodyBytes);
  }

  Future<void> sharePdf(String filePath) async {
    await _sharePdfFile(filePath);
  }

  Future<void> openPdfUrl(String url) async {
    await _openPdfUrl(url);
  }

  Future<Map<String, dynamic>> _defaultGeneratePdfCallable(String auditId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const PdfSessionExpiredException();
    }

    try {
      await user.getIdToken(true);
    } catch (_) {
      throw const PdfSessionExpiredException();
    }

    final callable = (_functions ??
            FirebaseFunctions.instanceFor(region: 'southamerica-east1'))
        .httpsCallable(
      'generateAuditPdf',
    );
    final result = await callable.call<Map<String, dynamic>>({'auditId': auditId});
    return Map<String, dynamic>.from(result.data);
  }

  void dispose() {
    _httpClient.close();
  }
}
