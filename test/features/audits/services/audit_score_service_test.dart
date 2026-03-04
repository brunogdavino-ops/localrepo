import 'package:flutter_test/flutter_test.dart';

import 'package:audit_app/features/audits/services/audit_score_service.dart';

void main() {
  test('computeAndPersistScore uses injected callable', () async {
    var calledWith = '';
    final service = AuditScoreService(
      computeScoreCallable: (auditId) async {
        calledWith = auditId;
        return <String, dynamic>{
          'auditId': auditId,
          'scoreFinal': 91.2,
          'scoreVersion': 1,
        };
      },
    );

    final response = await service.computeAndPersistScore('audit-xyz');

    expect(calledWith, 'audit-xyz');
    expect(response['scoreFinal'], 91.2);
    expect(response['scoreVersion'], 1);
  });
}
