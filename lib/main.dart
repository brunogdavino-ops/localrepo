import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/app.dart';

String? _firebaseErrorCode(Object error) {
  if (error is FirebaseException) return error.code;
  try {
    final dynamic code = (error as dynamic).code;
    return code?.toString();
  } catch (_) {
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On web release builds, querying Firebase.apps before initialization can
  // itself fail depending on the interop/runtime state. Prefer trying a single
  // initialization and only swallowing duplicate-app races.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    final code = _firebaseErrorCode(error);
    if (code != 'duplicate-app') rethrow;
    // Ignore duplicate initialization races, especially on web builds.
  }
  runApp(const AuditApp());
}
