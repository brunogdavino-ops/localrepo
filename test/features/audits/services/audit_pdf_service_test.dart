import 'dart:convert';
import 'dart:io';

import 'package:audit_app/features/audits/services/audit_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AuditPdfService', () {
    test('generatePdfUrl returns callable URL', () async {
      final service = AuditPdfService(
        generatePdfCallable: (auditId) async {
          expect(auditId, 'audit-1');
          return {'url': 'https://example.com/report.pdf'};
        },
      );

      final url = await service.generatePdfUrl('audit-1');
      expect(url, 'https://example.com/report.pdf');
    });

    test('generatePdfUrl throws when URL missing', () async {
      final service = AuditPdfService(
        generatePdfCallable: (_) async => {},
      );

      expect(
        () => service.generatePdfUrl('audit-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('downloadPdf stores file in temp directory', () async {
      final tempDir = await Directory.systemTemp.createTemp('audit_pdf_service_test');
      final client = MockClient((request) async {
        return http.Response.bytes(utf8.encode('pdf-bytes'), 200);
      });

      final service = AuditPdfService(
        httpClient: client,
        tempDirProvider: () async => tempDir,
        generatePdfCallable: (_) async => {'url': 'https://example.com/report.pdf'},
      );

      final path = await service.downloadPdf('https://example.com/report.pdf');
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), 'pdf-bytes');

      await tempDir.delete(recursive: true);
      service.dispose();
    });

    test('sharePdf throws while fallback is disabled', () async {
      final tempDir = await Directory.systemTemp.createTemp('audit_pdf_share_test');
      final file = File('${tempDir.path}${Platform.pathSeparator}report.pdf');
      await file.writeAsBytes(const [1, 2, 3]);
      final service = AuditPdfService();

      expect(
        () => service.sharePdf(file.path),
        throwsA(isA<UnimplementedError>()),
      );

      await tempDir.delete(recursive: true);
      service.dispose();
    });
  });
}
