import 'dart:convert';

import 'package:dialabsetest/core/network/dialbase_api.dart';
import 'package:dialabsetest/core/storage/auth_token_storage.dart';
import 'package:dialabsetest/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStorage extends AuthTokenStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  test(
    'login reads the Laravel demo token and user, then restores via me',
    () async {
      final storage = MemoryTokenStorage();
      final user = {
        'id': 1,
        'name': 'Amina',
        'email_verified_at': '2026-10-08T00:00:00Z',
      };
      final requests = <http.Request>[];
      final api = DialbaseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/login')
                  ? {'access_token': 'demo-token', 'user': user}
                  : {'data': user},
            ),
            200,
          );
        }),
      );
      final repository = AuthRepository(api: api, tokenStorage: storage);
      final session = await repository.login(
        email: ' Amina@example.test ',
        password: 'secret',
      );
      expect(session.token, 'demo-token');
      expect(session.isEmailVerified, isTrue);
      expect(storage.value, 'demo-token');
      expect((await repository.restoreSession())!.user['id'], 1);
      expect(requests.last.url.path, '/api/v1/me');
      expect(requests.last.headers['authorization'], 'Bearer demo-token');
    },
  );

  test(
    'registration sends only demo fields and stores the returned token',
    () async {
      final storage = MemoryTokenStorage();
      late Map<String, dynamic> payload;
      final repository = AuthRepository(
        tokenStorage: storage,
        api: DialbaseApi(
          client: MockClient((request) async {
            payload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'access_token': 'new-token',
                'user': {'id': 1},
              }),
              201,
            );
          }),
        ),
      );
      await repository.register(
        name: 'Amina',
        email: 'amina@example.test',
        password: 'secret',
      );
      expect(
        payload.keys,
        containsAll([
          'name',
          'email',
          'password',
          'password_confirmation',
          'device_name',
        ]),
      );
      expect(payload.containsKey('workspace_name'), isFalse);
      expect(storage.value, 'new-token');
    },
  );

  test(
    'expired tokens are removed while network failures preserve them',
    () async {
      final storage = MemoryTokenStorage()..value = 'expired';
      final repository = AuthRepository(
        tokenStorage: storage,
        api: DialbaseApi(
          client: MockClient((_) async => http.Response('{}', 401)),
        ),
      );
      expect(await repository.restoreSession(), isNull);
      expect(storage.value, isNull);
      storage.value = 'offline-token';
      final offline = AuthRepository(
        tokenStorage: storage,
        api: DialbaseApi(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
      );
      await expectLater(
        offline.restoreSession(),
        throwsA(isA<DialbaseApiException>()),
      );
      expect(storage.value, 'offline-token');
    },
  );
}
