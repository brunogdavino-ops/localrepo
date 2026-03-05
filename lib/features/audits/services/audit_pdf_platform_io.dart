import 'dart:io';

import 'package:share_plus/share_plus.dart';

const bool supportsFileDownload = true;

Future<String> savePdfBytes(List<int> bytes) async {
  final tempDir = Directory.systemTemp;
  final filePath =
      '${tempDir.path}${Platform.pathSeparator}auditoria_${DateTime.now().millisecondsSinceEpoch}.pdf';
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> sharePdfFile(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw StateError('Arquivo de PDF nao encontrado para compartilhamento.');
  }
  await Share.shareXFiles([XFile(file.path)], text: 'Relatorio de auditoria');
}

Future<void> openPdfUrl(String url) {
  throw UnsupportedError('Abertura direta por URL e usada apenas no web.');
}
