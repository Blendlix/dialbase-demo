import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dialabsetest/features/calling/data/call_controller.dart';

class CallScreen extends StatelessWidget {
  const CallScreen({super.key, required this.controller});
  final CallController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final call = controller.active;
      if (call == null) {
        return const Scaffold(backgroundColor: Color(0xFF898989));
      }
      final status = switch (call.phase) {
        CallPhase.preparing => 'Preparing call...',
        CallPhase.ringing => 'Calling...',
        CallPhase.incoming =>
          call.answering ? 'Answering...' : 'Incoming audio call',
        CallPhase.connecting => 'Connecting...',
        CallPhase.connected => controller.duration,
        CallPhase.canceling => 'Canceling...',
      };
      return CallScreenView(
        name: call.peerName,
        status: status,
        connected: call.phase == CallPhase.connected,
        incoming: call.phase == CallPhase.incoming,
        muted: call.muted,
        speaker: call.speaker,
        answering: call.answering,
        controlsEnabled: call.phase != CallPhase.canceling,
        audioControlsEnabled: call.accepted,
        onAnswer: controller.answer,
        onEnd: controller.end,
        onMute: controller.toggleMute,
        onSpeaker: controller.toggleSpeaker,
        onMinimize: () => Navigator.of(context).pop(),
      );
    },
  );
}

class CallScreenView extends StatelessWidget {
  const CallScreenView({
    super.key,
    required this.name,
    required this.status,
    required this.onAnswer,
    required this.onEnd,
    required this.onMute,
    required this.onSpeaker,
    required this.onMinimize,
    this.incoming = false,
    this.connected = false,
    this.muted = false,
    this.speaker = false,
    this.answering = false,
    this.controlsEnabled = true,
    this.audioControlsEnabled = true,
  });

  final String name;
  final String status;
  final bool incoming;
  final bool connected;
  final bool muted;
  final bool speaker;
  final bool answering;
  final bool controlsEnabled;
  final bool audioControlsEnabled;
  final VoidCallback onAnswer;
  final VoidCallback onEnd;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF898989),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = max(
                constraints.maxHeight,
                700 * MediaQuery.textScalerOf(context).scale(1),
              );
              final avatar = (constraints.maxWidth * .415).clamp(120.0, 180.0);
              final button = (constraints.maxWidth * .197).clamp(56.0, 82.0);
              return SingleChildScrollView(
                child: SizedBox(
                  height: height,
                  child: Stack(
                    children: [
                      Positioned(
                        top: height * .09,
                        left: 30,
                        child: IconButton.filled(
                          onPressed: onMinimize,
                          tooltip: 'Minimize call',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: .19,
                            ),
                            foregroundColor: Colors.white,
                            fixedSize: const Size(54, 54),
                          ),
                          icon: const Icon(
                            Icons.close_fullscreen_rounded,
                            size: 22,
                          ),
                        ),
                      ),
                      Positioned(
                        top: height * .265,
                        left: 24,
                        right: 24,
                        child: Column(
                          children: [
                            Container(
                              width: avatar,
                              height: avatar,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF242424),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 58,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(height: height < 600 ? 20 : 34),
                            Text(
                              name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (connected) ...[
                                  const Icon(
                                    Icons.graphic_eq_rounded,
                                    color: Color(0xFFE8E8E8),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Flexible(
                                  child: Text(
                                    status,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFE8E8E8),
                                      fontSize: 23,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: height * .10,
                        left: 26,
                        right: 26,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: incoming
                              ? [
                                  _CallControl(
                                    label: 'DECLINE',
                                    icon: Icons.call_end_rounded,
                                    size: button,
                                    background: const Color(0xFFFF4038),
                                    onPressed: controlsEnabled ? onEnd : null,
                                  ),
                                  _CallControl(
                                    label: answering ? 'ANSWERING' : 'ANSWER',
                                    icon: Icons.call_rounded,
                                    size: button,
                                    background: const Color(0xFF30B86B),
                                    onPressed: controlsEnabled && !answering
                                        ? onAnswer
                                        : null,
                                  ),
                                ]
                              : [
                                  _CallControl(
                                    label: 'SPEAKER',
                                    icon: Icons.volume_up_rounded,
                                    size: button,
                                    background: speaker
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: .19),
                                    foreground: speaker
                                        ? Colors.black
                                        : Colors.white,
                                    selected: speaker,
                                    onPressed:
                                        controlsEnabled && audioControlsEnabled
                                        ? onSpeaker
                                        : null,
                                  ),
                                  _CallControl(
                                    label: 'MUTE',
                                    icon: muted
                                        ? Icons.mic_off_rounded
                                        : Icons.mic_rounded,
                                    size: button,
                                    background: muted
                                        ? const Color(0xFF242424)
                                        : Colors.white,
                                    foreground: muted
                                        ? Colors.white
                                        : Colors.black,
                                    selected: muted,
                                    onPressed:
                                        controlsEnabled && audioControlsEnabled
                                        ? onMute
                                        : null,
                                  ),
                                  _CallControl(
                                    label: 'END',
                                    icon: Icons.call_end_rounded,
                                    size: button,
                                    background: const Color(0xFFFF4038),
                                    onPressed: controlsEnabled ? onEnd : null,
                                  ),
                                ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.label,
    required this.icon,
    required this.size,
    required this.background,
    required this.onPressed,
    this.foreground = Colors.white,
    this.selected = false,
  });
  final String label;
  final IconData icon;
  final double size;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 18,
    child: Column(
      children: [
        Semantics(
          toggled: selected,
          button: true,
          label: label.toLowerCase(),
          child: IconButton.filled(
            onPressed: onPressed,
            tooltip: label.toLowerCase(),
            style: IconButton.styleFrom(
              backgroundColor: background,
              foregroundColor: foreground,
              disabledBackgroundColor: background.withValues(alpha: .6),
              disabledForegroundColor: foreground.withValues(alpha: .6),
              fixedSize: Size(size, size),
            ),
            icon: Icon(icon, size: 36),
          ),
        ),
        const SizedBox(height: 13),
        Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: Color(0xFFF0F0F0),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    ),
  );
}
