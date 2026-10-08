import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dialabsetest/core/network/dialbase_api.dart';

typedef SignalMessage = Map<String, dynamic>;

String newRequestId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class CallSignaling {
  CallSignaling({
    required this.token,
    required this.onMessage,
    required this.onChange,
    DialbaseApi? api,
  }) : _api = api ?? dialbaseApi;

  final String token;
  final Future<void> Function(SignalMessage) onMessage;
  final VoidCallback onChange;
  final DialbaseApi _api;
  WebSocket? _socket;
  Map<String, dynamic> session = {};
  bool ready = false;
  bool _stopped = false;
  bool _connecting = false;
  String? error;
  Timer? _retry;
  Timer? _refreshTimer;
  Timer? _authTimer;
  Completer<void>? _refreshAck;
  Future<void>? _refreshing;
  DateTime? _requestedAt;
  int _retrySeconds = 1;
  Future<void> _messages = Future.value();

  Future<void> connect() async {
    if (_stopped || _connecting || ready || _socket != null) return;
    _connecting = true;
    try {
      final next = await _api.post('/calls/session', token: token);
      if (_stopped) return;
      session = next;
      _requestedAt = DateTime.now();
      final socket = await WebSocket.connect(
        next['ws_url'] as String,
        protocols: ['jwt', next['token'] as String],
      ).timeout(const Duration(seconds: 15));
      if (_stopped) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 15);
      _authTimer = Timer(const Duration(seconds: 15), () => socket.close());
      socket.listen(
        (raw) {
          _messages = _messages
              .then((_) async {
                if (_socket != socket || _stopped) return;
                final message = jsonDecode(raw as String) as SignalMessage;
                switch (message['event']) {
                  case 'auth.ok':
                    _authTimer?.cancel();
                    ready = true;
                    error = null;
                    _retrySeconds = 1;
                    _scheduleRefresh();
                    onChange();
                  case 'session.refreshed':
                    final data = message['data'] as Map<String, dynamic>? ?? {};
                    session['expires_at'] =
                        data['expires_at'] ?? session['expires_at'];
                    if (_refreshAck?.isCompleted == false) {
                      _refreshAck!.complete();
                    }
                    _scheduleRefresh();
                  case 'session.error':
                    await socket.close();
                  default:
                    await onMessage(message);
                }
              })
              .catchError((Object failure) {
                error = failure.toString();
                onChange();
              });
        },
        onError: (Object failure) => _disconnected(socket, failure),
        onDone: () =>
            _disconnected(socket, 'Call connection lost. Reconnecting...'),
      );
    } catch (failure) {
      error = failure.toString();
      onChange();
      _reconnect();
    } finally {
      _connecting = false;
    }
  }

  String send(String event, Map<String, dynamic> data) {
    if (!ready || _socket?.readyState != WebSocket.open) {
      throw StateError('Call connection is not ready.');
    }
    final id = newRequestId();
    _socket!.add(jsonEncode({'event': event, 'request_id': id, 'data': data}));
    return id;
  }

  Future<void> ensureFresh() async {
    if (!ready) throw StateError('Call connection is not ready.');
    final expires = DateTime.tryParse(session['expires_at']?.toString() ?? '');
    if ((expires != null &&
            expires.difference(DateTime.now()).inSeconds <= 120) ||
        (_requestedAt != null &&
            DateTime.now().difference(_requestedAt!).inMinutes >= 8)) {
      await refresh();
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final socket = _socket;
    try {
      final next = await _api.post('/calls/session', token: token);
      if (_stopped || !ready || socket != _socket) {
        throw StateError('Call connection changed.');
      }
      _refreshAck = Completer<void>();
      send('session.refresh', {'token': next['token']});
      session = next;
      _requestedAt = DateTime.now();
      await _refreshAck!.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      await socket?.close();
      rethrow;
    } finally {
      _refreshAck = null;
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final expires = DateTime.tryParse(session['expires_at']?.toString() ?? '');
    if (expires == null) return;
    final seconds = max(1, expires.difference(DateTime.now()).inSeconds - 120);
    _refreshTimer = Timer(Duration(seconds: seconds), () async {
      try {
        await refresh();
      } catch (failure) {
        if (!_stopped) {
          error = failure.toString();
          onChange();
        }
      }
    });
  }

  void _disconnected(WebSocket socket, Object failure) {
    if (_socket != socket || _stopped) return;
    _socket = null;
    ready = false;
    _authTimer?.cancel();
    _refreshTimer?.cancel();
    if (_refreshAck?.isCompleted == false) {
      _refreshAck!.completeError(StateError('Call connection lost.'));
    }
    error = failure.toString();
    onChange();
    _reconnect();
  }

  void _reconnect() {
    if (_stopped || _retry?.isActive == true) return;
    _retry = Timer(Duration(seconds: _retrySeconds), connect);
    _retrySeconds = min(30, _retrySeconds * 2);
  }

  void stop() {
    _stopped = true;
    ready = false;
    _retry?.cancel();
    _refreshTimer?.cancel();
    _authTimer?.cancel();
    if (_refreshAck?.isCompleted == false) {
      _refreshAck!.completeError(StateError('Calling stopped.'));
    }
    unawaited(_socket?.close());
    _socket = null;
  }

  void reconnect() {
    final socket = _socket;
    if (socket != null) {
      unawaited(socket.close());
    } else {
      unawaited(connect());
    }
  }
}

typedef VoidCallback = void Function();
