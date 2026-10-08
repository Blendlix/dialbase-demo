import 'dart:io';

import 'package:dialabsetest/features/calling/presentation/screens/call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Flutter's test font replaces letters with blocks; load SDK fonts for visual QA.
    final cache = File(Platform.resolvedExecutable)
        .parent
        .parent
        .parent
        .parent
        .path;
    for (final family in ['Roboto', 'MaterialIcons']) {
      final files = family == 'Roboto'
          ? ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']
          : ['MaterialIcons-Regular.otf'];
      final loader = FontLoader(family);
      for (final name in files) {
        loader.addFont(
          File('$cache/artifacts/material_fonts/$name')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      }
      await loader.load();
    }
  });
  Widget screen({
    String name = 'Test Contact',
    bool incoming = false,
    double scale = 1,
    VoidCallback? onMute,
    VoidCallback? onAnswer,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: CallScreenView(
        name: name,
        status: incoming ? 'Incoming audio call' : '00:03',
        incoming: incoming,
        connected: !incoming,
        onAnswer: onAnswer ?? () {},
        onEnd: () {},
        onMute: onMute ?? () {},
        onSpeaker: () {},
        onMinimize: () {},
      ),
    ),
  );

  testWidgets(
    'connected call matches the reference layout and mute is interactive',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var muted = false;
      await tester.pumpWidget(screen(onMute: () => muted = true));
      expect(find.text('Test Contact'), findsOneWidget);
      expect(find.text('00:03'), findsOneWidget);
      await tester.tap(find.byTooltip('mute'));
      expect(muted, isTrue);
      await tester.pump();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/connected_call.png'),
      );
    },
  );

  testWidgets('incoming call offers answer and decline', (tester) async {
    var answered = false;
    await tester.pumpWidget(
      screen(incoming: true, onAnswer: () => answered = true),
    );
    expect(find.text('ANSWER'), findsOneWidget);
    expect(find.text('DECLINE'), findsOneWidget);
    expect(find.text('MUTE'), findsNothing);
    await tester.tap(find.byTooltip('answer'));
    expect(answered, isTrue);
  });

  for (final size in [const Size(320, 568), const Size(852, 393)]) {
    testWidgets('call controls remain usable at $size with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        screen(name: 'A Very Long Contact Name For Testing', scale: 1.6),
      );
      await tester.ensureVisible(find.byTooltip('end'));
      expect(tester.takeException(), isNull);
    });
  }
}
