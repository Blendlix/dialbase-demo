import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class CallRingtone {
  AudioPlayer? _audioPlayer;
  AudioPlayer get _player => _audioPlayer ??= AudioPlayer();
  Future<void> _operations = Future.value();
  bool _disposed = false;

  void start() => _enqueue(() async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('audio/incoming.wav'), volume: .6);
  });

  Future<void> stop() {
    _enqueue(() async {
      await _audioPlayer?.stop();
    });
    return _operations;
  }

  void _enqueue(Future<void> Function() operation) {
    if (_disposed) return;
    _operations = _operations.then((_) => operation()).catchError((
      Object failure,
    ) {
      debugPrint('Call ringtone unavailable: $failure');
    });
  }

  void dispose() {
    _disposed = true;
    unawaited(
      _operations.then((_) async {
        await _audioPlayer?.dispose();
      }),
    );
  }
}
