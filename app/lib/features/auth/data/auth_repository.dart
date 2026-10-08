import 'package:dialabsetest/core/network/dialbase_api.dart';
import 'package:dialabsetest/core/storage/auth_token_storage.dart';
import 'package:dialabsetest/features/auth/data/auth_session.dart';

class AuthRepository {
  AuthRepository({DialbaseApi? api, AuthTokenStorage? tokenStorage})
    : _api = api ?? dialbaseApi,
      _tokenStorage = tokenStorage ?? AuthTokenStorage();

  final DialbaseApi _api;
  final AuthTokenStorage _tokenStorage;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/login',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'device_name': 'dialabse-mobile',
      },
    );
    final data = response;

    if (data['requires_two_factor'] == true) {
      throw const DialbaseApiException(
        message: 'Two-step verification is enabled for this account. Mobile verification is not set up yet.',
      );
    }

    final session = _sessionFrom(data);
    await _tokenStorage.write(session.token);
    return session;
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final trimmedName = name.trim();
    final response = await _api.post(
      '/auth/register',
      body: {
        'name': trimmedName,
        'email': email.trim().toLowerCase(),
        'password': password,
        'password_confirmation': password,
        'device_name': 'dialabse-mobile',
      },
    );
    final token = response['access_token'] as String?;
    if (token != null && token.isNotEmpty) {
      await _tokenStorage.write(token);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _api.post(
      '/auth/forgot-password',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  Future<void> resendVerification() async {
    final token = await _tokenStorage.read();
    if (token == null) {
      throw const DialbaseApiException(
        message: 'Sign in first to request another verification email.',
      );
    }
    await _api.post('/auth/email/verification-notification', token: token);
  }

  Future<AuthSession?> restoreSession() async {
    final token = await _tokenStorage.read();
    if (token == null) {
      return null;
    }

    try {
      final response = await _api.get('/me', token: token);
      final user = _map(response['data']);
      if (user['email_verified_at'] == null) {
        return null;
      }
      return AuthSession(token: token, user: user);
    } on DialbaseApiException catch (error) {
      if (error.statusCode == 401) {
        await _tokenStorage.clear();
        return null;
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final token = await _tokenStorage.read();
    try {
      if (token != null) {
        await _api.post('/auth/logout', token: token);
      }
    } finally {
      await _tokenStorage.clear();
    }
  }

  AuthSession _sessionFrom(Map<String, dynamic> data) {
    final token = data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const DialbaseApiException(
        message: 'The API response did not include a sign-in token.',
      );
    }
    return AuthSession(token: token, user: _map(data['user']));
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  }
}

final authRepository = AuthRepository();
