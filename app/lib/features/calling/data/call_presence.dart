import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dialabsetest/core/network/dialbase_api.dart';

class PeerAvailability {
  PeerAvailability({required this.ready, required this.busy, DateTime? seenAt})
    : seenAt = seenAt ?? DateTime.now();
  final bool ready;
  final bool busy;
  final DateTime seenAt;
  bool get fresh => DateTime.now().difference(seenAt).inSeconds < 25;
}

// Reverb uses the Pusher wire protocol, including Echo's client whispers.
class CallPresence {
  CallPresence({
    required this.token,
    required this.userId,
    required this.onChange,
    DialbaseApi? api,
  }) : _api = api ?? dialbaseApi;

  final String token;
  final String userId;
  final void Function() onChange;
  final DialbaseApi _api;
  final members = <String, String>{};
  final availability = <String, PeerAvailability>{};
  WebSocket? _socket;
  Timer? _heartbeat;
  Timer? _retry;
  Timer? _authTimeout;
  DateTime _lastMessage = DateTime.now();
  bool connected = false;
  bool _stopped = false;
  bool _connecting = false;
  bool _ready = false;
  bool _busy = false;

  bool callable(String id) =>
      connected &&
      members.containsKey(id) &&
      availability[id]?.fresh == true &&
      availability[id]?.ready == true &&
      availability[id]?.busy == false;

  Future<void> connect() async {
    if (_stopped || _connecting || _socket != null) return;
    _connecting = true;
    try {
      final response = await _api.get('/calls/config', token: token);
      final config = response['data'] as Map<String, dynamic>;
      final uri = Uri(
        scheme: config['scheme'] as String,
        host: config['host'] as String,
        port: config['port'] as int,
        path: '/app/${config['key']}',
        queryParameters: {
          'protocol': '7',
          'client': 'dialbase-flutter',
          'version': '1.0',
          'flash': 'false',
        },
      );
      final socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 15));
      if (_stopped) {
        await socket.close();
        return;
      }
      _socket = socket;
      _lastMessage = DateTime.now();
      _authTimeout = Timer(const Duration(seconds: 20), () => socket.close());
      socket.listen(
        (raw) async {
          if (_socket != socket || _stopped) return;
          try {
            _lastMessage = DateTime.now();
            final message = jsonDecode(raw as String) as Map<String, dynamic>;
            final rawData = message['data'];
            final data =
                (rawData is String ? jsonDecode(rawData) : rawData)
                    as Map<String, dynamic>? ??
                {};
            switch (message['event']) {
              case 'pusher:connection_established':
                final auth = await _api.post(
                  '/broadcasting/auth',
                  token: token,
                  body: {
                    'socket_id': data['socket_id'],
                    'channel_name': 'presence-calls',
                  },
                );
                if (_socket != socket || _stopped) return;
                _send('pusher:subscribe', {
                  'channel': 'presence-calls',
                  ...auth,
                });
              case 'pusher_internal:subscription_succeeded':
                _authTimeout?.cancel();
                final presence = data['presence'] as Map<String, dynamic>;
                final hash = presence['hash'] as Map<String, dynamic>;
                members.clear();
                for (final entry in hash.entries) {
                  members[entry.key] =
                      (entry.value as Map)['name']?.toString() ??
                      'Dialbase user';
                }
                connected = true;
                _publish();
                _heartbeat?.cancel();
                _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
                  if (DateTime.now().difference(_lastMessage).inSeconds > 40) {
                    unawaited(socket.close());
                    return;
                  }
                  _send('pusher:ping', {});
                  availability.removeWhere((_, value) => !value.fresh);
                  _publish();
                  onChange();
                });
              case 'pusher_internal:member_added':
                members[data['user_id'].toString()] =
                    (data['user_info'] as Map)['name']?.toString() ??
                    'Dialbase user';
                _publish();
              case 'pusher_internal:member_removed':
                members.remove(data['user_id'].toString());
                availability.remove(data['user_id'].toString());
              case 'client-call.availability':
                final id = data['user_id'].toString();
                if (members.containsKey(id)) {
                  availability[id] = PeerAvailability(
                    ready: data['ready'] == true,
                    busy: data['busy'] == true,
                  );
                }
              case 'pusher:ping':
                _send('pusher:pong', {});
              case 'pusher:error':
                await socket.close();
            }
            onChange();
          } catch (_) {
            await socket.close();
          }
        },
        onError: (Object _) => _disconnect(socket),
        onDone: () => _disconnect(socket),
      );
    } catch (_) {
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void setAvailability({required bool ready, required bool busy}) {
    _ready = ready;
    _busy = busy;
    _publish();
  }

  void _publish() {
    if (connected) {
      _send('client-call.availability', {
        'user_id': userId,
        'ready': _ready,
        'busy': _busy,
      }, channel: 'presence-calls');
    }
  }

  void _send(String event, Map<String, dynamic> data, {String? channel}) {
    if (_socket?.readyState == WebSocket.open) {
      _socket!.add(
        jsonEncode({'event': event, 'data': data, 'channel': ?channel}),
      );
    }
  }

  void _disconnect(WebSocket socket) {
    if (_socket != socket) return;
    _socket = null;
    _authTimeout?.cancel();
    _heartbeat?.cancel();
    connected = false;
    members.clear();
    availability.clear();
    if (!_stopped) {
      onChange();
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_stopped && _retry?.isActive != true) {
      _retry = Timer(const Duration(seconds: 5), connect);
    }
  }

  void stop() {
    _stopped = true;
    _retry?.cancel();
    _heartbeat?.cancel();
    _authTimeout?.cancel();
    connected = false;
    members.clear();
    availability.clear();
    unawaited(_socket?.close());
    _socket = null;
  }
}
