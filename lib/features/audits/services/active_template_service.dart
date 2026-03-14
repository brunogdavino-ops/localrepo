import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveTemplateService {
  final FirebaseFirestore _firestore;

  ActiveTemplateService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<DocumentReference<Map<String, dynamic>>> resolveActiveTemplateRef() async {
    final activeTemplatesSnapshot = await _firestore
        .collection('templates')
        .where('is_active', isEqualTo: true)
        .get();

    if (activeTemplatesSnapshot.docs.isEmpty) {
      throw StateError('Nenhum template ativo foi encontrado.');
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? selectedTemplate;
    int selectedVersion = -1;

    for (final templateDoc in activeTemplatesSnapshot.docs) {
      final data = templateDoc.data();
      final version = (data['version'] as num?)?.toInt() ?? 0;
      if (selectedTemplate == null || version > selectedVersion) {
        selectedTemplate = templateDoc;
        selectedVersion = version;
      }
    }

    if (selectedTemplate == null) {
      throw StateError('Nao foi possivel resolver o template ativo.');
    }

    return selectedTemplate.reference;
  }
}
