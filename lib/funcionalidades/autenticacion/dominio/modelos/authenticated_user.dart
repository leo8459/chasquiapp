class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.roles,
  });

  final int id;
  final String name;
  final String email;
  final Set<String> roles;

  String get primaryRole => roles.isEmpty ? '' : roles.first;
}
