import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  String? _firebaseErrorCode(Object error) {
    if (error is FirebaseAuthException) return error.code;
    if (error is FirebaseException) return error.code;
    try {
      final dynamic code = (error as dynamic).code;
      return code?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } catch (error) {
      final code = _firebaseErrorCode(error);
      if (code != null) {
        throw _mapAuthErrorCode(code);
      }
      throw 'Erro inesperado. Tente novamente.';
    }
  }

  String _mapAuthErrorCode(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Usuario ou senha incorretos.';
      case 'invalid-email':
        return 'E-mail invalido.';
      case 'user-disabled':
        return 'Usuario desativado.';
      case 'operation-not-allowed':
        return 'Login por e-mail e senha nao esta habilitado no Firebase.';
      case 'too-many-requests':
        return 'Muitas tentativas. Tente novamente mais tarde.';
      case 'network-request-failed':
        return 'Erro de conexao. Verifique sua internet.';
      default:
        return 'Erro ao fazer login (' + code + '). Tente novamente.';
    }
  }
}

