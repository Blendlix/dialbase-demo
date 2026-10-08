import 'dart:convert';

import 'package:dialabsetest/core/network/dialbase_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends JSON and bearer authorization to the configured API', () async {
    late http.Request capturedRequest;
    final api = DialbaseApi(
      baseUrl: 'https://api.example.test/api/v1/',
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'data': {'token': 'test-token'}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final response = await api.post(
      '/auth/login',
      body: {'email': 'user@example.test'},
      token: 'existing-token',
    );

    expect(capturedRequest.url.toString(), 'https://api.example.test/api/v1/auth/login');
    expect(capturedRequest.headers['authorization'], 'Bearer existing-token');
    expect(capturedRequest.headers['content-type'], 'application/json');
    expect(jsonDecode(capturedRequest.body), {'email': 'user@example.test'});
    expect(response['data'], {'token': 'test-token'});
  });

  test('surfaces the first validation error from the API', () async {
    final api = DialbaseApi(
      baseUrl: 'https://api.example.test/api/v1',
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'message': 'The given data was invalid.',
              'errors': {
                'email': ['The email field is required.'],
              },
            }),
            422,
            headers: {'content-type': 'application/json'},
          )),
    );

    await expectLater(
      api.post('/auth/login', body: const {}),
      throwsA(
        isA<DialbaseApiException>().having(
          (error) => error.message,
          'message',
          'The email field is required.',
        ),
      ),
    );
  });
}