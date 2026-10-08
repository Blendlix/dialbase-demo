class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final Map<String, dynamic> user;

  bool get isEmailVerified => user['email_verified_at'] != null;
}
