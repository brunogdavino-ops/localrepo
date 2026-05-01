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
  // Avoid duplicate initialize errors when the native SDK is already initialized.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (error) {
    final code = _firebaseErrorCode(error);
    if (code != 'duplicate-app') rethrow;
    // Ignore duplicate initialization races, especially on web builds.
  }
  runApp(const AuditApp());
}
