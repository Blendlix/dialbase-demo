import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:dialabsetest/core/network/dialbase_api.dart';
import 'package:dialabsetest/features/auth/data/auth_session.dart';
import 'package:dialabsetest/features/calling/data/call_presence.dart';
import 'package:dialabsetest/features/calling/data/call_signaling.dart';
import 'package:dialabsetest/features/calling/data/call_ringtone.dart';

enum CallPhase {
  preparing,
  ringing,
  incoming,
  connecting,
  connected,
  canceling,
}

class ActiveCall {
  ActiveCall({
    required this.peerId,
    required this.peerName,
    required this.incoming,
    required this.phase,
    this.uuid,
  });
  final String peerId;
  final String peerName;
  final bool incoming;
  String? uuid;
  String? inviteRequestId;
  bool accepted = false;
  bool cancelRequested = false;
  bool answering = false;
  CallPhase phase;
  bool muted = false;
  bool speaker = false;
  final duration = Stopwatch();
  int? historyId;
  Future<void> historyQueue = Future.value();
}

class CallController extends ChangeNotifier {
  CallController({
    required this.session,
    DialbaseApi? api,
    CallRingtone? ringtone,
  }) : _api = api ?? dialbaseApi,
       _ringtone = ringtone ?? CallRingtone() {
    signaling = CallSignaling(
      token: session.token,
      api: _api,
      onMessage: _onMessage,
      onChange: _connectionChanged,
    );
    presence = CallPresence(
      token: session.token,
      userId: session.user['id'].toString(),
      api: _api,
      onChange: _notify,
    );
  }

  final AuthSession session;
  final DialbaseApi _api;
  late final CallSignaling signaling;
  late final CallPresence presence;
  ActiveCall? active;
  String? error;
  String? historyError;
  final users = <Map<String, dynamic>>[];
  RTCPeerConnection? _peer;
  MediaStream? _local;
  final _candidates = <RTCIceCandidate>[];
  bool _remoteDescriptionSet = false;
  bool _disposed = false;
  bool loadingUsers = false;
  Timer? _timer;
  Timer? _connectionDeadline;
  final CallRingtone _ringtone;
  final _requests = <String, ActiveCall>{};
  Future<void>? _preparing;
  ActiveCall? _preparingCall;

  bool get ready => signaling.ready;
  String get duration {
    final seconds = active?.duration.elapsed.inSeconds ?? 0;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void start() {
    unawaited(loadUsers());
    unawaited(signaling.connect());
    unawaited(presence.connect());
  }

  Future<void> loadUsers() async {
    if (loadingUsers || _disposed) return;
    loadingUsers = true;
    _notify();
    try {
      final fetched = <Map<String, dynamic>>[];
      var page = 1;
      var lastPage = 1;
      do {
        final response = await _api.get(
          '/users?per_page=100&page=$page',
          token: session.token,
        );
        fetched.addAll((response['data'] as List).cast<Map<String, dynamic>>());
        lastPage = response['last_page'] as int? ?? 1;
        page++;
      } while (page <= lastPage && !_disposed);
      if (!_disposed) {
        users
          ..clear()
          ..addAll(fetched);
        error = null;
      }
    } catch (failure) {
      error = failure.toString();
    } finally {
      loadingUsers = false;
      _notify();
    }
  }

  void _connectionChanged() {
    presence.setAvailability(ready: ready, busy: active != null);
    if (!ready && active != null) _finish(active!, 'failed');
    _notify();
  }

  Future<void> call(Map<String, dynamic> user) async {
    final id = user['id'].toString();
    if (!ready || active != null || !presence.callable(id)) return;
    final call = ActiveCall(
      peerId: id,
      peerName: user['name'] as String,
      incoming: false,
      phase: CallPhase.preparing,
    );
    _activate(call);
    try {
      await signaling.ensureFresh();
      if (!_current(call)) return;
      await _prepare(call);
      if (!_current(call)) return;
      call.phase = CallPhase.ringing;
      call.inviteRequestId = signaling.send('call.invite', {
        'callee_user_id': id,
        'callee_role': signaling.session['role'],
        'context_type': signaling.session['context_type'],
        'context_id': signaling.session['context_id'],
      });
      _requests[call.inviteRequestId!] = call;
      _notify();
    } catch (failure) {
      if (_current(call)) {
        error = failure.toString();
        _finish(call, 'failed');
      }
    }
  }

  void _activate(ActiveCall call) {
    active = call;
    error = null;
    historyError = null;
    if (call.incoming) _ringtone.start();
    call.historyQueue = _api
        .post(
          '/calls/history',
          token: session.token,
          body: {
            'peer_user_id': int.parse(call.peerId),
            'direction': call.incoming ? 'incoming' : 'outgoing',
            if (call.uuid != null) 'call_uuid': call.uuid,
          },
        )
        .then((result) {
          call.historyId = (result['data'] as Map)['id'] as int;
        })
        .catchError((Object failure) {
          historyError = 'Call history could not be saved: $failure';
          _notify();
        });
    presence.setAvailability(ready: ready, busy: true);
    _connectionDeadline?.cancel();
    _connectionDeadline = Timer(const Duration(seconds: 60), () {
      if (active != call || call.phase == CallPhase.connected) return;
      error = 'The call timed out.';
      end();
    });
    _notify();
  }

  bool _current(ActiveCall call) =>
      !_disposed && active == call && !call.cancelRequested;

  Future<void> _prepare(ActiveCall call) {
    if (_peer != null) return Future.value();
    if (_preparingCall == call && _preparing != null) return _preparing!;
    _preparingCall = call;
    return _preparing = _prepareMedia(call).whenComplete(() {
      if (_preparingCall == call) {
        _preparingCall = null;
        _preparing = null;
      }
    });
  }

  Future<void> _prepareMedia(ActiveCall call) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    if (!_current(call)) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      return;
    }
    final peer = await createPeerConnection({
      'iceServers': signaling.session['ice_servers'],
      'sdpSemantics': 'unified-plan',
    });
    if (!_current(call)) {
      await peer.close();
      await peer.dispose();
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      return;
    }
    _local = stream;
    _peer = peer;
    for (final track in stream.getAudioTracks()) {
      await peer.addTrack(track, stream);
    }
    if (!_current(call)) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await Helper.setAppleAudioConfiguration(
        AppleAudioConfiguration(
          appleAudioCategory: AppleAudioCategory.playAndRecord,
          appleAudioMode: AppleAudioMode.voiceChat,
          appleAudioCategoryOptions: {AppleAudioCategoryOption.allowBluetooth},
        ),
      );
      if (!_current(call)) return;
      await Helper.ensureAudioSession();
    }
    await Helper.setSpeakerphoneOn(false);
    peer.onIceCandidate = (candidate) {
      if (!_current(call) || call.uuid == null || candidate.candidate == null) {
        return;
      }
      _sendFor(call, 'webrtc.ice_candidate', {'candidate': candidate.toMap()});
    };
    peer.onConnectionState = (state) {
      if (!_current(call)) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          !call.duration.isRunning) {
        call.phase = CallPhase.connected;
        call.duration.start();
        _connectionDeadline?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
        _history(call, 'connected');
        _sendFor(call, 'call.connected');
        _notify();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        error = 'The audio connection failed.';
        _sendFor(call, 'call.end');
        _finish(call, 'failed');
      }
    };
  }

  Future<void> answer() async {
    final call = active;
    if (call == null || !call.incoming || call.accepted || call.answering) {
      return;
    }
    call.answering = true;
    await _ringtone.stop();
    _notify();
    try {
      await signaling.ensureFresh();
      if (!_current(call)) return;
      await _prepare(call);
      if (!_current(call)) return;
      final request = signaling.send('call.accept', {'call_uuid': call.uuid});
      _requests[request] = call;
      call.accepted = true;
      call.phase = CallPhase.connecting;
      _history(call, 'accepted');
      _notify();
    } catch (failure) {
      if (_current(call)) {
        error = failure.toString();
        _sendFor(call, 'call.reject');
        _finish(call, 'failed');
      }
    } finally {
      call.answering = false;
      _notify();
    }
  }

  void end() {
    final call = active;
    if (call == null || call.cancelRequested) return;
    if (call.incoming && !call.accepted) {
      _sendFor(call, 'call.reject');
      _finish(call, 'rejected');
    } else if (!call.incoming && !call.accepted) {
      if (call.uuid == null && call.inviteRequestId != null) {
        // The invite acknowledgement owns the UUID needed to cancel remotely.
        call.cancelRequested = true;
        call.phase = CallPhase.canceling;
        unawaited(_releaseMedia());
        _connectionDeadline?.cancel();
        _connectionDeadline = Timer(const Duration(seconds: 15), () {
          if (active == call) {
            signaling.reconnect();
            _finish(call, 'canceled');
          }
        });
        _notify();
        return;
      }
      _sendFor(call, 'call.cancel');
      _finish(call, 'canceled');
    } else {
      _sendFor(call, 'call.end');
      _finish(call, 'ended');
    }
  }

  Future<void> toggleMute() async {
    final call = active;
    if (call == null || _local == null || !call.accepted) return;
    final muted = !call.muted;
    try {
      for (final track in _local!.getAudioTracks()) {
        await Helper.setMicrophoneMute(muted, track);
      }
      if (_current(call)) call.muted = muted;
    } catch (failure) {
      error = failure.toString();
    }
    _notify();
  }

  Future<void> toggleSpeaker() async {
    final call = active;
    if (call == null || _local == null) return;
    try {
      await Helper.setSpeakerphoneOn(!call.speaker);
      if (_current(call)) call.speaker = !call.speaker;
    } catch (failure) {
      error = failure.toString();
    }
    _notify();
  }

  void _sendFor(
    ActiveCall call,
    String event, [
    Map<String, dynamic> data = const {},
  ]) {
    if (call.uuid == null || !ready) return;
    try {
      final request = signaling.send(event, {'call_uuid': call.uuid, ...data});
      if (!event.startsWith('webrtc.')) _requests[request] = call;
    } catch (failure) {
      error = failure.toString();
    }
  }

  Future<void> _onMessage(SignalMessage message) async {
    final event = message['event']?.toString() ?? '';
    final data = message['data'] as Map<String, dynamic>? ?? {};
    var call = active;
    final requestCall = _requests.remove(message['request_id']);
    if ((event == 'error' ||
            event == 'call.error' ||
            message['success'] == false) &&
        call != null &&
        (requestCall == call ||
            (call.uuid != null && data['call_uuid'] == call.uuid))) {
      error =
          (message['error'] as Map?)?['message']?.toString() ??
          data['message']?.toString() ??
          'The call failed.';
      _sendFor(call, 'call.end');
      _finish(call, 'failed');
      return;
    }
    if (call != null &&
        message['request_id'] == call.inviteRequestId &&
        call.inviteRequestId != null) {
      if (message['success'] == false ||
          event == 'error' ||
          event == 'call.error') {
        error =
            (message['error'] as Map?)?['message']?.toString() ??
            'The call could not be started.';
        _finish(call, 'failed');
        return;
      }
      if (data['call_uuid'] != null) {
        call.uuid = data['call_uuid'].toString();
        _history(call, 'ringing');
        if (call.cancelRequested) {
          _sendFor(call, 'call.cancel');
          _finish(call, 'canceled');
          return;
        }
      }
    }
    if (event == 'call.ringing') {
      if (call != null) {
        if (call.uuid != data['call_uuid']) {
          signaling.send('call.reject', {'call_uuid': data['call_uuid']});
        }
        return;
      }
      final id = data['caller_user_id']?.toString();
      if (id == null || data['call_uuid'] == null) return;
      final name = users
          .where((user) => user['id'].toString() == id)
          .firstOrNull?['name']
          ?.toString();
      call = ActiveCall(
        peerId: id,
        peerName: name ?? data['display_name']?.toString() ?? 'Unknown caller',
        incoming: true,
        phase: CallPhase.incoming,
        uuid: data['call_uuid'].toString(),
      );
      _activate(call);
      return;
    }
    if (call == null ||
        call.uuid == null ||
        data['call_uuid']?.toString() != call.uuid) {
      return;
    }
    // Dialbase echoes forwarding receipts to the sender without media payloads.
    if (event.startsWith('webrtc.') && data['forwarded'] == true) return;
    try {
      switch (event) {
        case 'call.accepted':
          if (call.incoming || call.accepted) return;
          call.accepted = true;
          call.phase = CallPhase.connecting;
          _history(call, 'accepted');
          final peer = _peer;
          if (peer == null) {
            throw StateError('The audio connection is not ready.');
          }
          final offer = await peer.createOffer();
          if (!_current(call)) return;
          await peer.setLocalDescription(offer);
          if (_current(call)) {
            _sendFor(call, 'webrtc.offer', {'sdp': offer.toMap()});
          }
        case 'webrtc.offer':
          if (!call.incoming || !call.accepted) return;
          final sdp = data['sdp'];
          if (sdp is! Map) return;
          await _prepare(call);
          if (!_current(call)) return;
          final peer = _peer!;
          await _setRemote(peer, sdp, call);
          if (!_current(call)) return;
          final answer = await peer.createAnswer();
          if (!_current(call)) return;
          await peer.setLocalDescription(answer);
          if (_current(call)) {
            _sendFor(call, 'webrtc.answer', {'sdp': answer.toMap()});
          }
        case 'webrtc.answer':
          final sdp = data['sdp'];
          if (sdp is! Map) return;
          if (_peer != null && call.accepted && !call.incoming) {
            await _setRemote(_peer!, sdp, call);
          }
        case 'webrtc.ice_candidate':
          final candidate = data['candidate'];
          if (candidate is! Map) return;
          final ice = RTCIceCandidate(
            candidate['candidate'] as String?,
            candidate['sdpMid'] as String?,
            candidate['sdpMLineIndex'] as int?,
          );
          if (_peer != null && _remoteDescriptionSet) {
            await _peer!.addCandidate(ice);
          } else {
            _candidates.add(ice);
          }
        case 'call.rejected':
          _finish(call, 'rejected');
        case 'call.missed':
          _finish(call, 'missed');
        case 'call.ended':
          _finish(call, 'ended');
        case 'call.canceled':
        case 'call.cancelled':
          _finish(call, 'canceled');
        case 'call.error':
        case 'call.failed':
          error = data['message']?.toString() ?? 'The call failed.';
          _finish(call, 'failed');
      }
    } catch (failure) {
      if (_current(call)) {
        error = failure.toString();
        _sendFor(call, 'call.end');
        _finish(call, 'failed');
      }
    }
    _notify();
  }

  Future<void> _setRemote(
    RTCPeerConnection peer,
    Map sdp,
    ActiveCall call,
  ) async {
    await peer.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String),
    );
    if (!_current(call)) return;
    _remoteDescriptionSet = true;
    final candidates = List<RTCIceCandidate>.of(_candidates);
    _candidates.clear();
    for (final candidate in candidates) {
      if (!_current(call)) return;
      await peer.addCandidate(candidate);
    }
  }

  void _history(ActiveCall call, String status) {
    final uuid = call.uuid;
    call.historyQueue = call.historyQueue
        .then((_) async {
          if (call.historyId == null) return;
          await _api.patch(
            '/calls/history/${call.historyId}',
            token: session.token,
            body: {'status': status, 'call_uuid': ?uuid},
          );
        })
        .catchError((Object failure) {
          historyError = 'Call history could not be updated: $failure';
          _notify();
        });
  }

  void _finish(ActiveCall call, String status) {
    if (active != call) return;
    call.duration.stop();
    _history(call, status);
    active = null;
    _requests.clear();
    _ringtone.stop();
    _timer?.cancel();
    _connectionDeadline?.cancel();
    unawaited(_releaseMedia());
    presence.setAvailability(ready: ready, busy: false);
    _notify();
  }

  Future<void> _releaseMedia() async {
    final peer = _peer;
    final stream = _local;
    _peer = null;
    _local = null;
    _remoteDescriptionSet = false;
    _candidates.clear();
    Future<void> release(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (failure) {
        debugPrint('Call audio cleanup failed: $failure');
      }
    }

    if (peer != null) {
      await release(peer.close);
      await release(peer.dispose);
    }
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await release(track.stop);
      }
      await release(stream.dispose);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    final call = active;
    if (call != null) {
      _sendFor(
        call,
        call.accepted
            ? 'call.end'
            : call.incoming
            ? 'call.reject'
            : 'call.cancel',
      );
      _history(
        call,
        call.accepted
            ? 'ended'
            : call.incoming
            ? 'rejected'
            : 'canceled',
      );
    }
    _disposed = true;
    active = null;
    _timer?.cancel();
    _connectionDeadline?.cancel();
    signaling.stop();
    presence.stop();
    _ringtone.dispose();
    unawaited(_releaseMedia());
    super.dispose();
  }
}
