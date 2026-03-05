import 'package:web/web.dart' as web;

const bool supportsFileDownload = false;

Future<String> savePdfBytes(List<int> bytes) {
  throw UnsupportedError('Download de arquivo local nao suportado no web.');
}

Future<void> sharePdfFile(String filePath) {
  throw UnsupportedError('Compartilhamento por arquivo local nao suportado no web.');
}

Future<void> openPdfUrl(String url) async {
  final parsed = Uri.tryParse(url);
  if (parsed == null || (!parsed.hasScheme)) {
    throw StateError('URL de PDF invalida.');
  }
  web.window.open(url, '_blank');
}
