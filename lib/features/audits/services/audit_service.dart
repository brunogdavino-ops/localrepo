import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/audit_model.dart';

class AuditService {
  Stream<List<AuditModel>> getUserAudits(String uid) async* {
    final firestore = FirebaseFirestore.instance;
    final userDocRef = firestore.collection('users').doc(uid);
    final userSnapshot = await userDocRef.get();
    final userData = userSnapshot.data();
    final role = userData?['role'] as String?;

    final Query<Map<String, dynamic>> query = role == 'admin'
        ? firestore.collection('audits').orderBy('updated_at', descending: true)
        : firestore.collection('audits').where('auditorRef', isEqualTo: userDocRef);

    yield* query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => AuditModel.fromDocument(doc))
          .toList(growable: false);
    });
  }
}
