import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:audit_app/features/audits/models/audit_model.dart';

class _DocRef implements DocumentReference<Map<String, dynamic>> {
  _DocRef(this.path);

  @override
  final String path;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AuditModel.fromData', () {
    test('reads persisted score fields', () {
      final model = AuditModel.fromData(
        id: 'a1',
        data: <String, dynamic>{
          'auditnumber': 9,
          'status': 'in_progress',
          'scoreFinal': 88.5,
          'scoreByCategory': <String, dynamic>{
            'categories/c1': 90,
            'categories/c2': 75.4,
          },
          'scoreVersion': 1,
        },
        auditorRef: _DocRef('users/u1'),
        clientRef: _DocRef('clients/c1'),
        templateRef: _DocRef('templates/t1'),
      );

      expect(model.scoreFinal, 88.5);
      expect(model.scoreByCategory['categories/c1'], 90.0);
      expect(model.scoreByCategory['categories/c2'], 75.4);
      expect(model.scoreVersion, 1);
    });

    test('keeps compatibility with legacy score field', () {
      final model = AuditModel.fromData(
        id: 'a2',
        data: <String, dynamic>{
          'auditnumber': 10,
          'status': 'completed',
          'score': 74,
        },
        auditorRef: _DocRef('users/u1'),
        clientRef: _DocRef('clients/c1'),
        templateRef: _DocRef('templates/t1'),
      );

      expect(model.score, 74);
      expect(model.scoreFinal, 74.0);
      expect(model.scoreByCategory, isEmpty);
      expect(model.scoreVersion, isNull);
    });
  });
}
