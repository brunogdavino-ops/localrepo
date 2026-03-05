import 'package:cloud_functions/cloud_functions.dart';

typedef ComputeScoreCallable =
    Future<Map<String, dynamic>> Function(String auditId);

class AuditScoreService {
  AuditScoreService({
    FirebaseFunctions? functions,
    ComputeScoreCallable? computeScoreCallable,
  }) : _functions = functions,
       _computeScoreCallable = computeScoreCallable;

  final FirebaseFunctions? _functions;
  final ComputeScoreCallable? _computeScoreCallable;

  Future<Map<String, dynamic>> computeAndPersistScore(String auditId) async {
    if (_computeScoreCallable != null) {
      return _computeScoreCallable(auditId);
    }
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('computeAndPersistAuditScore');
    final response = await callable.call<Map<String, dynamic>>({
      'auditId': auditId,
    });
    return Map<String, dynamic>.from(response.data);
  }
}
