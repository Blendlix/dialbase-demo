import 'dart:convert';

import 'package:http/http.dart' as http;

class DialbaseApiException implements Exception {
  const DialbaseApiException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class DialbaseApi {
  DialbaseApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? _defaultBaseUrl).replaceFirst(RegExp(r'/$'), '');

  static const _defaultBaseUrl = String.fromEnvironment(
    'DIALBASE_API_URL',
    defaultValue: 'https://dialbase.test/api/v1',
  );

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> get(String path, {String? token}) {
    return _send('GET', path, token: token);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) {
    return _send('POST', path, body: body, token: token);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    required Map<String, dynamic> body,
    required String token,
  }) => _send('PATCH', path, body: body, token: token);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    late final http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      response = await (() async {
        final streamedResponse = await _client.send(request);
        return http.Response.fromStream(streamedResponse);
      })().timeout(const Duration(seconds: 20));
    } on Exception {
      throw const DialbaseApiException(
        message:
            'Could not reach Dialbase. Check your connection and try again.',
      );
    }

    final payload = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final validationErrors = payload['errors'];
      final firstValidationError = validationErrors is Map
          ? validationErrors.values
                .whereType<List>()
                .expand((messages) => messages)
                .whereType<String>()
                .firstOrNull
          : null;
      final message = response.statusCode == 429
          ? 'Too many attempts. Wait a moment and try again.'
          : firstValidationError ??
                payload['message'] as String? ??
                'The request could not be completed.';
      throw DialbaseApiException(
        message: message,
        statusCode: response.statusCode,
      );
    }

    return payload;
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }
}

final dialbaseApi = DialbaseApi();
