import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

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
    } on FirebaseAuthException catch (e) {
      throw _mapAuthException(e);
    } catch (_) {
      throw 'Erro inesperado. Tente novamente.';
    }
  }

  String _mapAuthException(FirebaseAuthException e) {
    switch (e.code) {
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
        return 'Erro ao fazer login (' + e.code + '). Tente novamente.';
    }
  }
}

