import 'dart:convert';
import 'dart:io';

import 'package:dialabsetest/core/network/dialbase_api.dart';
import 'package:dialabsetest/features/auth/data/auth_session.dart';
import 'package:dialabsetest/features/calling/data/call_controller.dart';
import 'package:dialabsetest/features/calling/data/call_presence.dart';
import 'package:dialabsetest/features/calling/data/call_ringtone.dart';
import 'package:dialabsetest/features/calling/data/call_signaling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class SilentRingtone extends CallRingtone {
  bool ringing = false;
  @override
  void start() {
    ringing = true;
  }

  @override
  Future<void> stop() async {
    ringing = false;
  }

  @override
  void dispose() {}
}

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the local test connection.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class CallTestServer {
  late final HttpServer server;
  final sockets = <WebSocket>[];
  final signals = <Map<String, dynamic>>[];
  final apiRequests = <http.Request>[];
  WebSocket? dialbase;
  int sessions = 0;
  String? protocols;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (offered) => offered.contains('jwt') ? 'jwt' : null,
      );
      sockets.add(socket);
      if (request.uri.path == '/signal') {
        protocols = request.headers.value('sec-websocket-protocol');
        dialbase = socket;
        send('auth.ok', {});
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          signals.add(message);
          if (message['event'] == 'session.refresh') {
            send('session.refreshed', {
              'expires_at': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .toIso8601String(),
            });
          }
        });
      } else {
        socket.add(
          jsonEncode({
            'event': 'pusher:connection_established',
            'data': jsonEncode({'socket_id': '123.456'}),
          }),
        );
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          if (message['event'] == 'pusher:subscribe') {
            socket.add(
              jsonEncode({
                'event': 'pusher_internal:subscription_succeeded',
                'data': {
                  'presence': {
                    'hash': {
                      '1': {'name': 'Amina'},
                      '2': {'name': 'Juma'},
                    },
                  },
                },
              }),
            );
            socket.add(
              jsonEncode({
                'event': 'client-call.availability',
                'data': {'user_id': '2', 'ready': true, 'busy': false},
              }),
            );
          } else if (message['event'] == 'pusher:ping') {
            socket.add(jsonEncode({'event': 'pusher:pong', 'data': {}}));
          }
        });
      }
    });
  }

  DialbaseApi get api => DialbaseApi(
    client: MockClient((request) async {
      apiRequests.add(request);
      final path = request.url.path;
      Map<String, dynamic> response;
      if (path.endsWith('/calls/session')) {
        sessions++;
        response = {
          'token': 'rtc-token-$sessions',
          'ws_url': 'ws://127.0.0.1:${server.port}/signal',
          'expires_at': DateTime.now()
              .add(const Duration(minutes: 15))
              .toIso8601String(),
          'ice_servers': [],
          'role': 'user',
          'context_type': 'application',
          'context_id': 'dialbase-global',
        };
      } else if (path.endsWith('/calls/config')) {
        response = {
          'data': {
            'host': '127.0.0.1',
            'port': server.port,
            'scheme': 'ws',
            'key': 'test',
          },
        };
      } else if (path.endsWith('/broadcasting/auth')) {
        response = {'auth': 'public:signature', 'channel_data': '{}'};
      } else if (path.endsWith('/users')) {
        response = {
          'data': [
            {'id': 2, 'name': 'Juma'},
          ],
          'last_page': 1,
        };
      } else {
        response = {
          'data': {'id': 9},
        };
      }
      return http.Response(
        jsonEncode(response),
        request.method == 'POST' && path.endsWith('/history') ? 201 : 200,
      );
    }),
  );

  void send(String event, Map<String, dynamic> data) =>
      dialbase!.add(jsonEncode({'event': event, 'data': data}));

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

void main() {
  test('sessions authenticate with JWT subprotocol and refresh on the existing socket', () async {
    final server = CallTestServer();
    await server.start();
    final signaling = CallSignaling(
      token: 'app-token',
      api: server.api,
      onChange: () {},
      onMessage: (_) async {},
    );
    addTearDown(() async {
      signaling.stop();
      await server.close();
    });
    await signaling.connect();
    await waitFor(() => signaling.ready);
    expect(server.protocols, contains('jwt'));
    expect(server.protocols, contains('rtc-token-1'));
    await signaling.refresh();
    expect(server.sessions, 2);
    expect(signaling.session['token'], 'rtc-token-2');
    expect(server.signals.single['event'], 'session.refresh');
    expect(server.sockets.length, 1);
  });

  test('incoming calls use shared presence, reject cleanly and ignore stale call events', () async {
    final server = CallTestServer();
    await server.start();
    final ringtone = SilentRingtone();
    final calls = CallController(
      session: const AuthSession(token: 'app-token', user: {'id': 1}),
      api: server.api,
      ringtone: ringtone,
    );
    addTearDown(() async {
      calls.dispose();
      await server.close();
    });
    calls.start();
    await waitFor(() => calls.ready && calls.presence.callable('2'));
    expect(calls.users.single['name'], 'Juma');
    final authRequest = server.apiRequests.firstWhere(
      (request) => request.url.path.endsWith('/broadcasting/auth'),
    );
    expect(authRequest.headers['authorization'], 'Bearer app-token');
    expect(jsonDecode(authRequest.body)['channel_name'], 'presence-calls');
    const uuid = '11111111-1111-4111-8111-111111111111';
    server.send('call.ringing', {'caller_user_id': '2', 'call_uuid': uuid});
    await waitFor(() => calls.active != null);
    expect(calls.active!.peerName, 'Juma');
    expect(calls.active!.phase, CallPhase.incoming);
    expect(ringtone.ringing, isTrue);
    server.send('call.ended', {'call_uuid': 'old-call'});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls.active!.uuid, uuid);
    final call = calls.active!;
    calls.end();
    await call.historyQueue;
    await waitFor(
      () => server.signals.any((message) => message['event'] == 'call.reject'),
    );
    expect(calls.active, isNull);
    expect(ringtone.ringing, isFalse);
    final patch = server.apiRequests.lastWhere(
      (request) => request.method == 'PATCH',
    );
    expect(jsonDecode(patch.body)['status'], 'rejected');
    expect(jsonDecode(patch.body)['call_uuid'], uuid);
  });

  test('stale availability never marks a user callable', () {
    final peer = PeerAvailability(
      ready: true,
      busy: false,
      seenAt: DateTime.now().subtract(const Duration(seconds: 26)),
    );
    expect(peer.fresh, isFalse);
  });

  test(
    'forwarded WebRTC acknowledgements do not end the active call',
    () async {
      final server = CallTestServer();
      await server.start();
      final calls = CallController(
        session: const AuthSession(token: 'app-token', user: {'id': 1}),
        api: server.api,
        ringtone: SilentRingtone(),
      );
      addTearDown(() async {
        calls.dispose();
        await server.close();
      });
      calls.start();
      await waitFor(() => calls.ready);
      const uuid = '22222222-2222-4222-8222-222222222222';
      server.send('call.ringing', {'caller_user_id': '2', 'call_uuid': uuid});
      await waitFor(() => calls.active != null);
      final call = calls.active!;
      call.accepted = true;
      call.phase = CallPhase.connecting;
      for (final event in [
        'webrtc.ice_candidate',
        'webrtc.offer',
        'webrtc.answer',
      ]) {
        server.send(event, {'call_uuid': uuid, 'forwarded': true});
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls.active, same(call));
      expect(calls.error, isNull);
      expect(calls.signaling.error, isNull);
      expect(
        server.signals.where((message) => message['event'] == 'call.end'),
        isEmpty,
      );
      calls.end();
      await call.historyQueue;
    },
  );
}
