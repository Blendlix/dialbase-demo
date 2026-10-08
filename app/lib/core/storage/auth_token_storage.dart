import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokenStorage {
  AuthTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'dialbase.auth.token';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _tokenKey);

  Future<void> write(String token) => _storage.write(
        key: _tokenKey,
        value: token,
      );

  Future<void> clear() => _storage.delete(key: _tokenKey);
}