import 'package:dialabsetest/core/network/dialbase_api.dart';

class CallHistoryRepository {
  CallHistoryRepository({DialbaseApi? api}) : _api = api ?? dialbaseApi;

  final DialbaseApi _api;

  Future<List<Map<String, dynamic>>> fetchCalls({required String token}) async {
    final response = await _api.get('/calls/history', token: token);
    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map<String, dynamic>>().toList();
  }
}
