// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/fields.dart';
import '../design/tokens.dart';
import '../map/map_dialogs.dart';
import '../video/video_manager.dart';
import '../video/video_settings.dart';
import '../video/video_storage.dart';

/// Settings → Video: source, connection, decoding/display and recording.
/// Every change is saved at once and applied to the running stream.
class VideoSettingsSection extends ConsumerWidget {
  const VideoSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(videoSettingsProvider);
    final ctl = ref.read(videoSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Video streaming',
          subtitle: 'Live camera video in the Fly view: RTSP, RTP/UDP (H.264, H.265), MPEG‑TS and other URLs.',
          trailing: Switch(
            value: s.enabled,
            onChanged: (v) => ctl.update((s) => s.copyWith(enabled: v)),
          ),
          child: s.enabled ? const _StreamStatus() : const _OffNote(),
        ),
        if (s.enabled) ...[
          const _SourceCard(),
          _ConnectionCard(s: s),
          _DisplayCard(s: s),
          const _RecordingCard(),
          Align(
            alignment: Alignment.centerLeft,
            child: AlloyButton(
              icon: LucideIcons.rotateCcw,
              label: 'Reset video settings',
              onPressed: () async {
                if (await confirm(
                  context,
                  'Reset video settings?',
                  'Source, connection, display and recording '
                      'options go back to their defaults.',
                  action: 'Reset',
                )) {
                  ctl.reset();
                }
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _OffNote extends StatelessWidget {
  const _OffNote();
  @override
  Widget build(BuildContext context) => Text(
    'Turn on to show a camera stream in the Fly view, as a floating window over the map or full screen, '
    'and to record it.',
    style: TextStyle(fontSize: 12, color: context.alloy.ink2),
  );
}

/// Live state, stream details and start/stop.
class _StreamStatus extends ConsumerWidget {
  const _StreamStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(videoManagerProvider);
    final mgr = ref.read(videoManagerProvider.notifier);
    final (tone, icon, text) = switch (st.status) {
      VideoStatus.playing => (Tone.ok, LucideIcons.video, 'Streaming'),
      VideoStatus.paused => (Tone.neutral, LucideIcons.pause, 'Paused'),
      VideoStatus.connecting => (Tone.caution, LucideIcons.loaderCircle, 'Connecting…'),
      VideoStatus.reconnecting => (Tone.caution, LucideIcons.refreshCw, 'Reconnecting (attempt ${st.attempt})'),
      VideoStatus.error => (Tone.warning, LucideIcons.triangleAlert, 'No video'),
      VideoStatus.unavailable => (Tone.warning, LucideIcons.triangleAlert, 'Video engine unavailable'),
      VideoStatus.idle => (Tone.neutral, LucideIcons.videoOff, 'Stopped'),
      VideoStatus.disabled => (Tone.neutral, LucideIcons.videoOff, 'Off'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill(icon: icon, tone: tone, children: [Text(text)]),
            if (st.isRecording)
              const Pill(icon: LucideIcons.circleDot, tone: Tone.critical, children: [Text('Recording')]),
            if (st.info != null && st.hasPicture)
              Text(
                st.info!.summary,
                style: AlloyText.mono(12, weight: FontWeight.w500, color: context.alloy.ink2),
              ),
          ],
        ),
        if (st.message != null && st.status != VideoStatus.playing)
          Text(st.message!, style: TextStyle(fontSize: 12, color: context.alloy.ink2)),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (st.isActive)
              AlloyButton(icon: LucideIcons.squareStop, label: 'Stop', onPressed: mgr.disconnect)
            else
              AlloyButton(
                icon: LucideIcons.play,
                label: 'Start',
                primary: true,
                onPressed: st.status == VideoStatus.unavailable ? null : mgr.connect,
              ),
            if (st.status == VideoStatus.error || st.status == VideoStatus.reconnecting)
              AlloyButton(icon: LucideIcons.refreshCw, label: 'Retry now', onPressed: mgr.retryNow),
          ],
        ),
      ],
    );
  }
}

class _SourceCard extends ConsumerStatefulWidget {
  const _SourceCard();

  @override
  ConsumerState<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends ConsumerState<_SourceCard> {
  bool _testing = false;
  VideoTestResult? _result;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final r = await ref.read(videoManagerProvider.notifier).testConnection(ref.read(videoSettingsProvider));
    if (mounted) {
      setState(() {
        _testing = false;
        _result = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(videoSettingsProvider);
    final ctl = ref.read(videoSettingsProvider.notifier);
    final errors = validateVideoSettings(s);
    final p = context.alloy;
    // A changed source makes an earlier test result stale.
    ref.listen(videoSettingsProvider.select((s) => s.streamKey), (_, _) {
      if (_result != null) setState(() => _result = null);
    });
    return SectionCard(
      title: 'Source',
      subtitle: 'Where the camera stream comes from. APX does not announce video over MAVLink, so enter it here.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ChoiceField<VideoSourceKind>(
            label: 'Video source',
            value: s.source,
            options: {for (final k in VideoSourceKind.values) k: k.label},
            onChanged: (v) => ctl.update((s) => s.copyWith(source: v)),
          ),
          ...switch (s.source) {
            VideoSourceKind.rtsp => [
              FieldGrid(
                children: [
                  _CommitField(
                    label: 'RTSP URL',
                    value: s.rtspUrl,
                    hint: 'rtsp://192.168.144.25:8554/main.264',
                    error: errors['rtspUrl'],
                    onCommit: (v) => ctl.update((s) => s.copyWith(rtspUrl: v)),
                  ),
                  ChoiceField<RtspTransport>(
                    label: 'Transport',
                    value: s.rtspTransport,
                    options: {for (final t in RtspTransport.values) t: t.label},
                    onChanged: (v) => ctl.update((s) => s.copyWith(rtspTransport: v)),
                  ),
                ],
              ),
              _Hint(
                'User name and password go in the URL: rtsp://user:pass@host:554/path. '
                'TCP is the most reliable over Wi‑Fi and through routers; UDP has slightly less delay.',
              ),
            ],
            VideoSourceKind.udpH264 || VideoSourceKind.udpH265 || VideoSourceKind.udpMpegTs => [
              FieldGrid(
                children: [
                  NumField(
                    label: 'UDP port',
                    value: s.udpPort.toDouble(),
                    integer: true,
                    min: 1,
                    max: 65535,
                    onChanged: (v) => ctl.update((s) => s.copyWith(udpPort: v.round())),
                  ),
                  _CommitField(
                    label: 'Listen address (optional)',
                    value: s.udpAddress,
                    hint: 'Any interface, or a multicast group',
                    error: errors['udpAddress'],
                    onCommit: (v) => ctl.update((s) => s.copyWith(udpAddress: v)),
                  ),
                ],
              ),
              _Hint(switch (s.source) {
                VideoSourceKind.udpMpegTs =>
                  'MPEG‑TS over UDP, e.g. from ffmpeg: ffmpeg … -f mpegts udp://<this device>:${s.udpPort}',
                _ =>
                  'Raw RTP, payload type 96 (APX Flight Manager\'s "UDP h.26x" sources). Sender example: '
                      'gst-launch-1.0 … ! ${s.source == VideoSourceKind.udpH264 ? 'rtph264pay' : 'rtph265pay'} '
                      'config-interval=1 pt=96 ! udpsink host=<this device> port=${s.udpPort}',
              }),
            ],
            VideoSourceKind.tcpMpegTs => [
              _CommitField(
                label: 'TCP URL',
                value: s.tcpUrl,
                hint: 'tcp://192.168.1.10:5600',
                error: errors['tcpUrl'],
                onCommit: (v) => ctl.update((s) => s.copyWith(tcpUrl: v)),
              ),
            ],
            VideoSourceKind.customUrl => [
              _CommitField(
                label: 'Stream URL',
                value: s.customUrl,
                hint: 'http://…/stream.m3u8, rtmp://…, srt://…:9000',
                error: errors['customUrl'],
                onCommit: (v) => ctl.update((s) => s.copyWith(customUrl: v)),
              ),
            ],
          },
          Row(
            spacing: 12,
            children: [
              AlloyButton(
                icon: LucideIcons.plugZap,
                label: _testing ? 'Testing…' : 'Test connection',
                onPressed: _testing || errors.isNotEmpty ? null : _test,
              ),
              if (_testing) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (_result case final r?)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: r.ok ? p.okBg : p.warningBg,
                borderRadius: BorderRadius.circular(Alloy.radiusControl),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Icon(
                    r.ok ? LucideIcons.circleCheck : LucideIcons.triangleAlert,
                    size: 18,
                    color: r.ok ? p.okInk : p.warningInk,
                  ),
                  Expanded(
                    child: Text(
                      r.ok
                          ? 'Video received in ${(r.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s — '
                                '${r.info?.summary ?? ''}'
                          : r.message ?? 'Failed',
                      style: TextStyle(fontSize: 13, color: r.ok ? p.okInk : p.warningInk),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard({required this.s});
  final VideoSettings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(videoSettingsProvider.notifier);
    return SectionCard(
      title: 'Connection',
      subtitle: 'Starting the stream and recovering from drop-outs.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Connect automatically', style: TextStyle(fontSize: 13)),
            subtitle: _sub(context, 'Start the stream when the app starts or the settings change'),
            value: s.autoConnect,
            onChanged: (v) => ctl.update((s) => s.copyWith(autoConnect: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reconnect when the stream is lost', style: TextStyle(fontSize: 13)),
            subtitle: _sub(context, 'Waits the delay below, doubling up to 30 s between attempts'),
            value: s.autoReconnect,
            onChanged: (v) => ctl.update((s) => s.copyWith(autoReconnect: v)),
          ),
          const SizedBox(height: 8),
          FieldGrid(
            columns: 3,
            children: [
              NumField(
                label: 'Reconnect delay',
                unit: 's',
                integer: true,
                min: 1,
                max: 60,
                value: s.reconnectDelaySec.toDouble(),
                enabled: s.autoReconnect,
                onChanged: (v) => ctl.update((s) => s.copyWith(reconnectDelaySec: v.round())),
              ),
              NumField(
                label: 'Max attempts (0 = no limit)',
                integer: true,
                min: 0,
                max: 1000,
                value: s.maxReconnectAttempts.toDouble(),
                enabled: s.autoReconnect,
                onChanged: (v) => ctl.update((s) => s.copyWith(maxReconnectAttempts: v.round())),
              ),
              NumField(
                label: 'Stream timeout',
                unit: 's',
                integer: true,
                min: 2,
                max: 60,
                value: s.timeoutSec.toDouble(),
                help: 'No first frame (or no new frame) for this long counts as lost',
                onChanged: (v) => ctl.update((s) => s.copyWith(timeoutSec: v.round())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DisplayCard extends ConsumerWidget {
  const _DisplayCard({required this.s});
  final VideoSettings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(videoSettingsProvider.notifier);
    return SectionCard(
      title: 'Decoding & display',
      subtitle: 'Hardware decoding keeps the CPU free for the map and telemetry.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Low latency', style: TextStyle(fontSize: 13)),
            subtitle: _sub(context, 'Show frames as soon as they arrive, with no buffer. Off: ~1 s buffer, smoother'),
            value: s.lowLatency,
            onChanged: (v) => ctl.update((s) => s.copyWith(lowLatency: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hardware acceleration', style: TextStyle(fontSize: 13)),
            subtitle: _sub(context, 'GPU decoding and rendering. Turn off if the picture is green, black or corrupt'),
            value: s.hardwareAcceleration,
            onChanged: (v) => ctl.update((s) => s.copyWith(hardwareAcceleration: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Play audio', style: TextStyle(fontSize: 13)),
            subtitle: _sub(context, 'Most drone cameras send no audio; off saves decoding work'),
            value: s.audio,
            onChanged: (v) => ctl.update((s) => s.copyWith(audio: v)),
          ),
          const SizedBox(height: 8),
          FieldGrid(
            columns: 3,
            children: [
              if (s.hardwareAcceleration)
                ChoiceField<String>(
                  label: 'Decoder',
                  value: s.decoder,
                  options: {for (final d in decoderOptions()) d.id: d.label},
                  onChanged: (v) => ctl.update((s) => s.copyWith(decoder: v)),
                )
              else
                const InputDecorator(
                  decoration: InputDecoration(labelText: 'Decoder', isDense: true),
                  child: Text('Software (FFmpeg)'),
                ),
              ChoiceField<VideoFit>(
                label: 'Fit',
                value: s.fit,
                options: {for (final f in VideoFit.values) f: f.label},
                onChanged: (v) => ctl.update((s) => s.copyWith(fit: v)),
              ),
              ChoiceField<VideoAspect>(
                label: 'Aspect ratio',
                value: s.aspect,
                options: {for (final a in VideoAspect.values) a: a.label},
                onChanged: (v) => ctl.update((s) => s.copyWith(aspect: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordingCard extends ConsumerStatefulWidget {
  const _RecordingCard();

  @override
  ConsumerState<_RecordingCard> createState() => _RecordingCardState();
}

class _RecordingCardState extends ConsumerState<_RecordingCard> {
  static final _desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  static final _mobile = Platform.isAndroid || Platform.isIOS;

  Future<void> _chooseFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Record here');
    if (dir == null) return;
    ref.read(videoSettingsProvider.notifier).update((s) => s.copyWith(recordingDir: () => dir));
  }

  Future<void> _open(String path) async {
    try {
      final (exe, args) = Platform.isWindows
          ? ('explorer', [path])
          : Platform.isMacOS
          ? ('open', [path])
          : ('xdg-open', [path]);
      await Process.start(exe, args, mode: ProcessStartMode.detached);
    } catch (e) {
      if (mounted) notify(context, 'Could not open $path: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(videoSettingsProvider);
    final ctl = ref.read(videoSettingsProvider.notifier);
    final dirAsync = ref.watch(recordingDirProvider);
    // Refresh the list when a recording finishes.
    ref.watch(videoManagerProvider.select((v) => (v.recording, v.notice?.id)));
    final p = context.alloy;
    final dir = dirAsync.value;
    final free = dir == null ? null : freeBytes(dir.existsSync() ? dir.path : dir.parent.path);
    final files = dir == null ? const <File>[] : listMedia(dir);
    return SectionCard(
      title: 'Recording',
      subtitle:
          'Recordings are the camera\'s own stream saved without re-encoding, so resolution and quality are '
          'those set on the camera/encoder, and recording costs almost no CPU.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          InputDecorator(
            decoration: InputDecoration(
              labelText: s.recordingDir == null ? 'Folder (default)' : 'Folder',
              isDense: true,
              helperText: free == null ? null : '${formatBytes(free)} free',
            ),
            child: SelectableText(dir?.path ?? '…', style: AlloyText.mono(12, weight: FontWeight.w500)),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_desktop) AlloyButton(icon: LucideIcons.folder, label: 'Choose folder…', onPressed: _chooseFolder),
              if (_desktop && dir != null)
                AlloyButton(
                  icon: LucideIcons.folderOpen,
                  label: 'Open folder',
                  onPressed: () async {
                    await dir.create(recursive: true);
                    await _open(dir.path);
                  },
                ),
              if (s.recordingDir != null)
                AlloyButton(
                  label: 'Use default folder',
                  onPressed: () => ctl.update((s) => s.copyWith(recordingDir: () => null)),
                ),
            ],
          ),
          if (Platform.isIOS)
            const _Hint('Recordings are in the Files app: On My iPhone/iPad → APX Flight Manager → Video.'),
          if (Platform.isAndroid)
            const _Hint(
              'Recordings are kept in the app\'s Movies folder (Android/data/…/files/Movies); '
              'turn on "Copy to gallery" to find them in Photos/Gallery.',
            ),
          FieldGrid(
            children: [
              ChoiceField<RecordingFormat>(
                label: 'File format',
                value: s.recordingFormat,
                options: {for (final f in RecordingFormat.values) f: f.label},
                onChanged: (v) => ctl.update((s) => s.copyWith(recordingFormat: v)),
              ),
              NumField(
                label: 'Storage limit (0 = none)',
                unit: 'MB',
                integer: true,
                min: 0,
                max: 10 * 1024 * 1024,
                value: s.storageLimitMb.toDouble(),
                help: 'Oldest recordings in the folder are deleted to stay under this',
                onChanged: (v) => ctl.update((s) => s.copyWith(storageLimitMb: v.round())),
              ),
            ],
          ),
          if (_mobile)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Copy to gallery', style: TextStyle(fontSize: 13)),
              subtitle: _sub(
                context,
                Platform.isIOS
                    ? 'Adds finished recordings and snapshots to Photos (MP4/MOV only)'
                    : 'Adds finished recordings and snapshots to the gallery (APX Flight Manager album)',
              ),
              value: s.saveToGallery,
              onChanged: (v) => ctl.update((s) => s.copyWith(saveToGallery: v)),
            ),
          if (files.isNotEmpty) ...[
            Caption('Recent (${files.length})'),
            for (final f in files.take(8))
              _MediaRow(
                file: f,
                onOpen: _desktop ? () => _open(f.path) : null,
                onGallery: _mobile ? () => ref.read(videoManagerProvider.notifier).exportToGallery(f) : null,
                onDelete: () async {
                  if (await confirm(
                    context,
                    'Delete ${f.uri.pathSegments.last}?',
                    'The file is removed from disk.',
                    action: 'Delete',
                  )) {
                    try {
                      f.deleteSync();
                    } catch (e) {
                      if (context.mounted) notify(context, 'Could not delete: $e');
                    }
                    setState(() {});
                  }
                },
              ),
          ] else
            Text('No recordings yet.', style: TextStyle(fontSize: 12, color: p.ink2)),
        ],
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.file, required this.onDelete, this.onOpen, this.onGallery});
  final File file;
  final VoidCallback onDelete;
  final VoidCallback? onOpen, onGallery;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final name = file.uri.pathSegments.last;
    int size = 0;
    DateTime? when;
    try {
      size = file.lengthSync();
      when = file.lastModifiedSync();
    } catch (_) {}
    final isImage = name.toLowerCase().endsWith('.jpg');
    return Row(
      spacing: 6,
      children: [
        Icon(isImage ? LucideIcons.image : LucideIcons.film, size: 16, color: p.ink2),
        Expanded(
          child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        ),
        Text(
          '${formatBytes(size)}${when == null ? '' : '  ·  ${_ago(when)}'}',
          style: AlloyText.mono(11, weight: FontWeight.w500, color: p.ink2),
        ),
        if (onOpen != null) GlassIconButton(icon: LucideIcons.externalLink, tooltip: 'Open', onPressed: onOpen),
        if (onGallery != null)
          GlassIconButton(icon: LucideIcons.images, tooltip: 'Copy to gallery', onPressed: onGallery),
        GlassIconButton(icon: LucideIcons.trash2, tooltip: 'Delete', onPressed: onDelete),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

/// A text field that saves on Enter or when it loses focus (not per keystroke,
/// so the stream isn't restarted while typing a URL).
class _CommitField extends StatefulWidget {
  const _CommitField({required this.label, required this.value, required this.onCommit, this.hint, this.error});
  final String label, value;
  final String? hint, error;
  final ValueChanged<String> onCommit;

  @override
  State<_CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<_CommitField> {
  late final _c = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_CommitField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _c.text.trim();
    if (v != widget.value) widget.onCommit(v);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    focusNode: _focus,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.url,
    onSubmitted: (_) => _commit(),
    style: AlloyText.mono(13, weight: FontWeight.w500),
    decoration: InputDecoration(labelText: widget.label, hintText: widget.hint, errorText: widget.error, isDense: true),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 11.5, color: context.alloy.ink2));
}

Widget _sub(BuildContext context, String text) => Text(text, style: TextStyle(fontSize: 11, color: context.alloy.ink2));
