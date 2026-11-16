// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/tokens.dart';
import 'video_manager.dart';
import 'video_widgets.dart';

/// Opens the live video over everything. The stream keeps running — this is
/// one more view of it, not a new player.
Future<void> openVideoFullscreen(BuildContext context) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: Alloy.fast,
    reverseTransitionDuration: Alloy.fast,
    pageBuilder: (_, _, _) => const VideoFullscreenPage(),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ),
);

class VideoFullscreenPage extends ConsumerStatefulWidget {
  const VideoFullscreenPage({super.key});

  @override
  ConsumerState<VideoFullscreenPage> createState() => _VideoFullscreenPageState();
}

class _VideoFullscreenPageState extends ConsumerState<VideoFullscreenPage> {
  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _enterNative();
    _poke();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _exitNative();
    super.dispose();
  }

  /// Whether this page switched the OS window to full screen (and so must
  /// switch it back). The Linux runner starts the app full screen (F11
  /// toggles), and that state must survive leaving full-screen video.
  bool _nativeChanged = false;

  /// Desktop: the OS window goes full screen (media_kit_video's window
  /// helper) unless it already covers the display. Phones/tablets: hide the
  /// system bars; rotation stays free so the picture follows the device.
  Future<void> _enterNative() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _nativeChanged = true;
        return;
      }
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      final screen = view?.display.size, window = view?.physicalSize;
      final alreadyFull =
          screen != null && window != null && window.width >= screen.width - 2 && window.height >= screen.height - 2;
      if (alreadyFull) return;
      await _channel.invokeMethod('Utils.EnterNativeFullscreen');
      _nativeChanged = true;
    } catch (_) {
      // Not available (tests, unsupported window manager): stay in-window.
    }
  }

  Future<void> _exitNative() async {
    if (!_nativeChanged) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      } else {
        await _channel.invokeMethod('Utils.ExitNativeFullscreen');
      }
    } catch (_) {}
  }

  /// Show the controls, then hide them after a few idle seconds.
  void _poke() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final mgr = ref.read(videoManagerProvider.notifier);
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.keyF): _close,
          const SingleActivator(LogicalKeyboardKey.space): mgr.togglePause,
          const SingleActivator(LogicalKeyboardKey.keyR): mgr.toggleRecording,
          const SingleActivator(LogicalKeyboardKey.keyS): mgr.takeSnapshot,
        },
        child: Focus(
          autofocus: true,
          child: MouseRegion(
            onHover: (_) => _poke(),
            cursor: _controls ? SystemMouseCursors.basic : SystemMouseCursors.none,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _controls ? setState(() => _controls = false) : _poke(),
              onDoubleTap: _close,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const VideoSurface(),
                  AnimatedOpacity(
                    opacity: _controls ? 1 : 0,
                    duration: Alloy.fast,
                    child: IgnorePointer(
                      ignoring: !_controls,
                      child: _Controls(onClose: _close, onAction: _poke),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.onClose, required this.onAction});
  final VoidCallback onClose, onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(videoManagerProvider);
    final mgr = ref.read(videoManagerProvider.notifier);
    VoidCallback act(FutureOr<void> Function() f) => () {
      onAction();
      f();
    };
    final info = s.info?.summary;
    return SafeArea(
      child: Stack(
        children: [
          // Top bar: what is showing, and the way out.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xAA000000), Color(0x00000000)],
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 120),
                  Expanded(
                    child: Text(
                      info ?? '',
                      textAlign: TextAlign.center,
                      style: AlloyText.mono(12, weight: FontWeight.w500, color: Colors.white70),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _RoundButton(
                        icon: LucideIcons.minimize,
                        tooltip: 'Exit full screen (Esc)',
                        onPressed: onClose,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom: stream controls, centred and out of the picture's middle.
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(28)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    _RoundButton(
                      icon: s.isRecording ? LucideIcons.squareStop : LucideIcons.circleDot,
                      color: const Color(0xFFFF3B30),
                      tooltip: s.isRecording ? 'Stop recording (R)' : 'Record (R)',
                      onPressed: s.isRecording || s.status == VideoStatus.playing ? act(mgr.toggleRecording) : null,
                    ),
                    _RoundButton(
                      icon: LucideIcons.camera,
                      tooltip: 'Snapshot (S)',
                      onPressed: s.hasPicture ? act(mgr.takeSnapshot) : null,
                    ),
                    if (s.hasPicture)
                      _RoundButton(
                        icon: s.status == VideoStatus.paused ? LucideIcons.play : LucideIcons.pause,
                        tooltip: s.status == VideoStatus.paused ? 'Resume (Space)' : 'Pause (Space)',
                        onPressed: s.isRecording ? null : act(mgr.togglePause),
                      ),
                    if (s.isActive)
                      _RoundButton(icon: LucideIcons.squareStop, tooltip: 'Stop video', onPressed: act(mgr.disconnect))
                    else if (s.status != VideoStatus.disabled && s.status != VideoStatus.unavailable)
                      _RoundButton(icon: LucideIcons.play, tooltip: 'Start video', onPressed: act(mgr.connect)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, this.onPressed, this.color = Colors.white});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 22,
    color: color,
    disabledColor: Colors.white30,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    icon: Icon(icon),
  );
}
