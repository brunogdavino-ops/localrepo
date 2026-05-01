import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA5dvmJiKpE0kY6_X_vCIPnvxBnvypEFDA',
    appId: '1:309238860637:android:f5fc1fab0d8a59bfedb6b4',
    messagingSenderId: '309238860637',
    projectId: 'auditapp-94b97',
    storageBucket: 'auditapp-94b97.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDtLQ_oIkiWjbnO4UYgl_adulyV0lg8zF4',
    appId: '1:309238860637:web:6c76e81efed98232edb6b4',
    messagingSenderId: '309238860637',
    projectId: 'auditapp-94b97',
    authDomain: 'auditapp-94b97.firebaseapp.com',
    storageBucket: 'auditapp-94b97.firebasestorage.app',
  );
}
