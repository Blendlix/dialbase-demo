import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// Two soft telephone tones, followed by silence, ready for seamless looping.
void main() {
  const sampleRate = 22050;
  const seconds = 3;
  final bytes = ByteData(44 + sampleRate * seconds * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, sampleRate * seconds * 2, Endian.little);
  for (var i = 0; i < sampleRate * seconds; i++) {
    final time = i / sampleRate;
    final local = time < .55
        ? time
        : time >= .75 && time < 1.3
        ? time - .75
        : -1.0;
    final envelope = local < 0
        ? 0.0
        : min(1.0, min(local / .02, (.55 - local) / .02));
    final sample =
        (sin(2 * pi * 440 * time) + sin(2 * pi * 480 * time)) * .18 * envelope;
    bytes.setInt16(44 + i * 2, (sample * 32767).round(), Endian.little);
  }
  final file = File('assets/audio/incoming.wav');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes.buffer.asUint8List());
}
