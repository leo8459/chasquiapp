import '../modelos/authenticated_user.dart';

abstract class AuthRepository {
  const AuthRepository();

  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  });

  Future<AuthenticatedUser> authorizeRememberedAccount(String email);
}
