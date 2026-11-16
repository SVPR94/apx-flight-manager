// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../map/map_dialogs.dart';
import 'video_fullscreen.dart';
import 'video_manager.dart';
import 'video_settings.dart';

/// The live picture with its state drawn over it (connecting, reconnecting,
/// error, paused, recording). Any number of these can show the one stream —
/// main view, picture‑in‑picture, full screen — without restarting it.
class VideoSurface extends ConsumerWidget {
  const VideoSurface({super.key, this.compact = false, this.recordingBadge = true});

  /// Small window: shorter messages, no buttons inside.
  final bool compact;

  /// Draw "REC 00:12" in the corner (off where the page shows it elsewhere).
  final bool recordingBadge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rev = ref.watch(videoManagerProvider.select((s) => s.backendRevision));
    final status = ref.watch(videoManagerProvider.select((s) => s.status));
    final (fit, aspect) = ref.watch(videoSettingsProvider.select((s) => (s.fit, s.aspect)));
    final backend = ref.read(videoManagerProvider.notifier).backend;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (backend != null && status != VideoStatus.disabled)
            KeyedSubtree(
              key: ValueKey(rev),
              child: backend.buildView(
                fit: switch (fit) {
                  VideoFit.fit => BoxFit.contain,
                  VideoFit.fill => BoxFit.cover,
                  VideoFit.stretch => BoxFit.fill,
                },
                aspectRatio: aspect.ratio,
              ),
            ),
          _StatusOverlay(compact: compact),
          if (recordingBadge) Positioned(top: compact ? 6 : 12, left: compact ? 6 : 12, child: const RecordingBadge()),
        ],
      ),
    );
  }
}

class _StatusOverlay extends ConsumerWidget {
  const _StatusOverlay({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(videoManagerProvider);
    final mgr = ref.read(videoManagerProvider.notifier);
    final description = ref.watch(videoSettingsProvider.select((v) => VideoEndpoint.of(v).description));
    final (IconData? icon, String? title, String? detail, Widget? action) = switch (s.status) {
      VideoStatus.playing => (null, null, null, null),
      VideoStatus.paused => (LucideIcons.pause, 'Paused', 'Resume returns to live video', null),
      VideoStatus.disabled => (LucideIcons.videoOff, 'Video is off', 'Turn it on in Settings → Video', null),
      VideoStatus.unavailable => (LucideIcons.triangleAlert, 'Video engine unavailable', s.message, null),
      VideoStatus.idle => (
        LucideIcons.video,
        'Video stopped',
        s.message ?? description,
        _VideoActionButton(icon: LucideIcons.play, label: 'Start video', onPressed: mgr.connect),
      ),
      VideoStatus.connecting => (null, 'Connecting…', description, null),
      VideoStatus.reconnecting => (
        null,
        null,
        s.message,
        _VideoActionButton(icon: LucideIcons.refreshCw, label: 'Retry now', onPressed: mgr.retryNow),
      ),
      VideoStatus.error => (
        LucideIcons.triangleAlert,
        'No video',
        s.message,
        _VideoActionButton(icon: LucideIcons.refreshCw, label: 'Retry', onPressed: mgr.retryNow),
      ),
    };
    if (s.status == VideoStatus.playing) return const SizedBox.shrink();
    final busy = s.status == VideoStatus.connecting || s.status == VideoStatus.reconnecting;
    const fg = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.72);
    return ColoredBox(
      color: s.status == VideoStatus.paused ? const Color(0x55000000) : Colors.transparent,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: compact ? 4 : 8,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: compact ? 22 : 30,
                  child: const CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                )
              else if (icon != null)
                Icon(icon, size: compact ? 24 : 36, color: fg),
              if (s.status == VideoStatus.reconnecting)
                _Countdown(at: s.retryAt, attempt: s.attempt, compact: compact)
              else if (title != null)
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: compact ? 12 : 16),
                ),
              if (detail != null && detail.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(
                    detail,
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: dim, fontSize: compact ? 10.5 : 13),
                  ),
                ),
              if (action != null && !compact) Padding(padding: const EdgeInsets.only(top: 6), child: action),
            ],
          ),
        ),
      ),
    );
  }
}

/// High-contrast button used over dark/video surfaces.
class _VideoActionButton extends StatelessWidget {
  const _VideoActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.2,
        ),
      ),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        foregroundColor: const Color(0xFF111315),
        backgroundColor: Colors.white,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Alloy.radiusCapsule),
          side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.2),
        ),
      ),
    );
  }
}

/// "Reconnecting in 4 s (attempt 3)", ticking.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.at, required this.attempt, required this.compact});
  final DateTime? at;
  final int attempt;
  final bool compact;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.at == null ? 0 : (widget.at!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    final text = left > 0 ? 'Reconnecting in $left s' : 'Reconnecting…';
    return Text(
      widget.compact ? text : '$text  ·  attempt ${widget.attempt}',
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: widget.compact ? 12 : 16),
    );
  }
}

/// Red "REC 03:12" while recording (ticks every second).
class RecordingBadge extends ConsumerStatefulWidget {
  const RecordingBadge({super.key});

  @override
  ConsumerState<RecordingBadge> createState() => _RecordingBadgeState();
}

class _RecordingBadgeState extends ConsumerState<RecordingBadge> {
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (rec, started) = ref.watch(videoManagerProvider.select((s) => (s.recording, s.recordingStartedAt)));
    if (rec == RecordingStatus.idle) {
      _t?.cancel();
      _t = null;
      return const SizedBox.shrink();
    }
    _t ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final label = switch (rec) {
      RecordingStatus.starting => 'REC …',
      RecordingStatus.waiting => 'REC · waiting for video',
      RecordingStatus.stopping => 'Saving…',
      _ => 'REC ${formatRecordingTime(started == null ? Duration.zero : DateTime.now().difference(started))}',
    };
    return Semantics(
      label: 'Recording',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Blinks once a second while writing.
                color: rec == RecordingStatus.recording && DateTime.now().second.isOdd
                    ? const Color(0x66FF3B30)
                    : const Color(0xFFFF3B30),
              ),
            ),
            Text(label, style: AlloyText.mono(12, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

String formatRecordingTime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// The video's actions, as glass icon buttons (Fly view tool column).
class VideoToolButtons extends ConsumerWidget {
  const VideoToolButtons({super.key, this.onSwap});

  /// Swap back to the map (shown when video fills the view).
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(videoManagerProvider);
    final mgr = ref.read(videoManagerProvider.notifier);
    final rec = s.isRecording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onSwap != null) GlassIconButton(icon: LucideIcons.map, tooltip: 'Show the map', onPressed: onSwap),
        _RecordButton(recording: rec, enabled: rec || s.status == VideoStatus.playing, onPressed: mgr.toggleRecording),
        GlassIconButton(
          icon: LucideIcons.camera,
          tooltip: 'Snapshot',
          onPressed: s.hasPicture ? mgr.takeSnapshot : null,
        ),
        if (s.status == VideoStatus.playing || s.status == VideoStatus.paused)
          GlassIconButton(
            icon: s.status == VideoStatus.paused ? LucideIcons.play : LucideIcons.pause,
            tooltip: s.status == VideoStatus.paused ? 'Resume (back to live)' : 'Pause',
            onPressed: rec ? null : mgr.togglePause,
          ),
        if (s.isActive)
          GlassIconButton(icon: LucideIcons.squareStop, tooltip: 'Stop video', onPressed: mgr.disconnect)
        else if (s.status != VideoStatus.disabled && s.status != VideoStatus.unavailable)
          GlassIconButton(icon: LucideIcons.play, tooltip: 'Start video', onPressed: mgr.connect),
        GlassIconButton(
          icon: LucideIcons.maximize,
          tooltip: 'Full‑screen video',
          onPressed: () => openVideoFullscreen(context),
        ),
      ],
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recording, required this.enabled, required this.onPressed});
  final bool recording, enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: recording ? 'Stop recording' : (enabled ? 'Record' : 'Record (needs live video)'),
    onPressed: enabled ? onPressed : null,
    constraints: const BoxConstraints.tightFor(width: Alloy.touch, height: Alloy.touch),
    icon: recording
        ? const Icon(LucideIcons.squareStop, size: 19, color: Color(0xFFFF3B30))
        : Icon(LucideIcons.circleDot, size: 19, color: enabled ? const Color(0xFFE5483E) : null),
  );
}

/// Shows the manager's one-off messages (recording saved, errors) as
/// snackbars. Put once under a Scaffold.
class VideoNoticeListener extends ConsumerWidget {
  const VideoNoticeListener({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(videoManagerProvider.select((s) => s.notice), (prev, n) {
      if (n == null || n.id == prev?.id) return;
      notify(context, n.text);
    });
    return child;
  }
}
