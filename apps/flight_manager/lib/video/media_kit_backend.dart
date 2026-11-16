// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_backend.dart';
import 'video_settings.dart';

/// libmpv + FFmpeg through media_kit — one engine on Android, iOS, Windows,
/// macOS and Linux. Hardware decoding: MediaCodec (Android), VideoToolbox
/// (iOS/macOS), D3D11VA/DXVA2/NVDEC (Windows), VA-API/NVDEC/VDPAU (Linux).
///
/// Live-stream behaviour is set per open through mpv properties: no disk
/// cache, never pausing to buffer, frames shown as soon as decoded
/// (low-latency), and `stream-record` to save the encoded stream as received.
final class MediaKitVideoBackend implements VideoBackend {
  MediaKitVideoBackend._(this._player, this._controller) {
    _subs.addAll([
      _player.stream.log.listen(_onLog),
      _player.stream.width.listen((w) => _onSize()),
      _player.stream.height.listen((h) => _onSize()),
      _player.stream.position.listen((_) => _onProgress()),
    ]);
    // Observed as a plain string (format NONE), separate from media_kit's own
    // observation: "yes" after a load means it failed or the source ended.
    unawaited(_native.observeProperty('idle-active', _onIdle).catchError((Object _) {}));
  }

  static Player _newPlayer(VideoSettings s) {
    // Throws when libmpv can't be loaded (e.g. Linux without libmpv installed).
    MediaKit.ensureInitialized();
    return Player(
      configuration: PlayerConfiguration(
        title: 'APX Flight Manager',
        logLevel: MPVLogLevel.warn,
        muted: !s.audio,
        // Demuxer packet queue: a live stream never needs much.
        bufferSize: 8 * 1024 * 1024,
      ),
    );
  }

  /// A player with no picture output (`vo=null`), for connection tests.
  static Future<MediaKitVideoBackend> createHeadless(VideoSettings s) async =>
      MediaKitVideoBackend._(_newPlayer(s), null);

  static Future<MediaKitVideoBackend> create(VideoSettings s) async {
    final player = _newPlayer(s);
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(enableHardwareAcceleration: s.hardwareAcceleration, hwdec: s.hwdec),
    );
    return MediaKitVideoBackend._(player, controller);
  }

  final Player _player;
  final VideoController? _controller;
  final _events = StreamController<VideoBackendEvent>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];

  NativePlayer get _native => _player.platform as NativePlayer;

  /// True between [open] and [stop]/failure: idle/size changes count only then.
  bool _active = false;
  bool _sawBusy = false;
  bool _firstFrame = false;
  final _errors = <String>[];
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  File? _sdpFile;
  Completer<void>? _recordStopped;
  String? _recorderError;
  bool _disposed = false;

  /// Bumped on every open/stop, so a late callback can tell it is stale.
  int _openGen = 0;

  @override
  Stream<VideoBackendEvent> get events => _events.stream;

  void _emit(VideoBackendEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  /// Print every libmpv log line (diagnostics; `--dart-define=APX_VIDEO_LOG=true`).
  static bool logAll = const bool.fromEnvironment('APX_VIDEO_LOG');

  void _onLog(PlayerLog l) {
    if (logAll) debugPrint('mpv[${l.level}] ${l.prefix}: ${l.text.trim()}');
    final text = l.text.trim();
    if (text.isEmpty) return;
    if (l.prefix == 'recorder' || text.startsWith('Stopping recording')) {
      if (text.startsWith('Stopping recording')) {
        final c = _recordStopped;
        if (c != null && !c.isCompleted) c.complete();
      } else if (l.level == 'error' || l.level == 'fatal') {
        _recorderError = text;
      }
      return;
    }
    if (l.level != 'error' && l.level != 'fatal') return;
    // Decoder complaints on a lossy link (missing references until the next
    // keyframe) are expected and not a stream failure.
    if (l.prefix.startsWith('ffmpeg/video') || l.prefix == 'vd' || l.prefix.startsWith('ffmpeg/audio')) return;
    if (_active) {
      _errors.add(text);
      if (_errors.length > 20) _errors.removeAt(0);
    }
  }

  void _onSize() {
    final w = _player.state.width, h = _player.state.height;
    if (!_active || _firstFrame || w == null || h == null || w <= 0 || h <= 0) return;
    _firstFrame = true;
    _emit(VideoFirstFrame(w, h));
  }

  void _onProgress() {
    if (!_active || !_firstFrame) return;
    final now = DateTime.now();
    if (now.difference(_lastProgress) < const Duration(milliseconds: 250)) return;
    _lastProgress = now;
    _emit(const VideoFrameProgress());
  }

  Future<void> _onIdle(String value) async {
    if (!_active) return;
    if (value == 'no') {
      _sawBusy = true;
      return;
    }
    if (value != 'yes' || !_sawBusy) return;
    final gen = _openGen;
    // Property changes reach us before the log lines explaining them (the log
    // is an async stream): let those arrive so the reason is the real one.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!_active || gen != _openGen) return;
    _active = false;
    if (_firstFrame && _errors.isEmpty) {
      _emit(const VideoStreamEnded());
    } else {
      _emit(
        VideoBackendError(describeVideoError(_errors, playing: _firstFrame), generic: isGenericVideoError(_errors)),
      );
    }
  }

  Future<void> _set(Map<String, String> props) async {
    for (final e in props.entries) {
      try {
        await _native.setProperty(e.key, e.value);
      } catch (err) {
        // An option this libmpv build doesn't know (older/newer mpv): skip it.
        debugPrint('video: mpv option ${e.key}=${e.value} rejected: $err');
      }
    }
  }

  @override
  Future<void> open(VideoEndpoint endpoint, VideoTuning t) async {
    _openGen++;
    _active = false;
    _firstFrame = false;
    _sawBusy = false;
    _errors.clear();
    var url = endpoint.url;
    if (endpoint.sdp != null) {
      final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}apx_fm_video_$pid.sdp');
      await f.writeAsString(endpoint.sdp!, flush: true);
      _sdpFile = f;
      url = f.path;
    }
    const whitelist = 'file,udp,rtp,tcp,tls,http,https,httpproxy,crypto,data,rtmp,rtmps,srt';
    await _set({
      // Live: no disk cache, never stop to buffer, close on end so a lost
      // source is reported instead of freezing on the last frame.
      'keep-open': 'no',
      'cache-pause': 'no',
      'cache-on-disk': 'no',
      'cache': t.lowLatency ? 'no' : 'yes',
      'cache-secs': t.lowLatency ? '0' : '1',
      'demuxer-readahead-secs': t.lowLatency ? '0' : '1',
      'untimed': t.lowLatency ? 'yes' : 'no',
      'video-latency-hacks': t.lowLatency ? 'yes' : 'no',
      'demuxer-lavf-analyzeduration': t.lowLatency ? '1' : '0',
      'demuxer-lavf-o': [if (t.lowLatency) 'fflags=+nobuffer', 'protocol_whitelist=[$whitelist]'].join(','),
      'demuxer-lavf-format': '',
      'network-timeout': '${t.timeoutSec}',
      'load-unsafe-playlists': 'yes',
      'aid': t.audio ? 'auto' : 'no',
      'sid': 'no',
      // Without a VideoController media_kit leaves video off (vid=no); the
      // controller manages `vid` itself (Android toggles it with the surface).
      if (_controller == null) 'vid': 'auto',
      'rtsp-transport': 'tcp',
      ...endpoint.options,
    });
    _active = true;
    await _player.open(Media(url), play: true);
  }

  @override
  Future<void> stop() async {
    _openGen++;
    _active = false;
    await _player.stop();
    try {
      await _sdpFile?.delete();
    } catch (_) {}
    _sdpFile = null;
  }

  @override
  Future<void> setPaused(bool paused) => paused ? _player.pause() : _player.play();

  @override
  Future<VideoStreamInfo> info() async {
    Future<String> get(String p) async {
      try {
        return await _native.getProperty(p);
      } catch (_) {
        return '';
      }
    }

    final codec = (await get('video-format')).split(' ').first;
    final fps = double.tryParse(await get('container-fps')) ?? double.tryParse(await get('estimated-vf-fps'));
    final bitrate = double.tryParse(await get('video-bitrate'));
    final hw = await get('hwdec-current');
    return VideoStreamInfo(
      width: _player.state.width,
      height: _player.state.height,
      codec: codec.isEmpty ? null : codec,
      fps: fps,
      hwdec: hw.isEmpty ? null : hw,
      bitrateKbps: bitrate == null ? null : bitrate / 1000,
    );
  }

  @override
  Future<void> startRecording(String path) async {
    _recorderError = null;
    await _native.setProperty('stream-record', path);
    // The recorder opens its file on the demuxer thread; give it a moment to
    // complain (bad path, unsupported container for this codec).
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_recorderError != null) {
      final e = _recorderError!;
      await _native.setProperty('stream-record', '');
      throw FileSystemException('Recorder: $e', path);
    }
  }

  @override
  Future<void> stopRecording() async {
    final done = _recordStopped = Completer<void>();
    await _native.setProperty('stream-record', '');
    // Wait for the container to be finalised (MP4 writes its index last).
    await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    _recordStopped = null;
  }

  @override
  Future<Uint8List?> snapshot() => _player.screenshot(format: 'image/jpeg');

  @override
  Widget buildView({required BoxFit fit, double? aspectRatio}) => _controller == null
      ? const ColoredBox(color: Color(0xFF000000))
      : Video(
          controller: _controller,
          controls: NoVideoControls,
          fit: fit,
          aspectRatio: aspectRatio,
          fill: const Color(0xFF000000),
          // The stream manager decides what happens in the background, not each view.
          pauseUponEnteringBackgroundMode: false,
          resumeUponEnteringForegroundMode: false,
          wakelock: true,
        );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      await _sdpFile?.delete();
    } catch (_) {}
    await _player.dispose();
    await _events.close();
  }
}

/// True when the log names no concrete cause. FFmpeg's own messages
/// ("Connection refused", "401", …) can be routed to another mpv instance in
/// the process (FFmpeg's log callback is global), so they may be missing.
@visibleForTesting
bool isGenericVideoError(List<String> errors) {
  final m = describeVideoError(errors);
  return m.startsWith('The stream could not be opened') || m.startsWith('No video in a recognised format');
}

/// Turns libmpv/FFmpeg log errors into something a pilot can act on.
@visibleForTesting
String describeVideoError(List<String> errors, {bool playing = false}) {
  final all = errors.join('\n').toLowerCase();
  bool has(String s) => all.contains(s);
  if (has('connection refused')) {
    return 'Connection refused — nothing is serving video at that address and port.';
  }
  if (has('401') || has('unauthorized')) {
    return 'The camera rejected the login — check the user name and password in the URL.';
  }
  if (has('404') || has('not found')) return 'The server has no stream at that path (404).';
  if (has('461') || has('unsupported transport')) {
    return 'The server does not support this RTSP transport — try UDP or Automatic.';
  }
  if (has('name or service not known') || has('failed to resolve') || has('nodename nor servname')) {
    return 'The host name could not be resolved.';
  }
  if (has('address already in use') || has('bind failed') || has('only one usage of each socket address')) {
    return 'The UDP port is already in use by another program (close other GCS or video viewers).';
  }
  if (has('network is unreachable') || has('no route to host') || has('host is unreachable')) {
    return 'Network unreachable — check the link to the vehicle/camera.';
  }
  if (has('timed out') || has('timeout')) return 'No answer from the camera (timed out).';
  if (has('invalid data found') || has('failed to recognize file format')) {
    return 'No video in a recognised format arrived at that address.';
  }
  if (playing) return 'The video stream stopped.';
  final last = errors.where((e) => e.trim().isNotEmpty).lastOrNull;
  return last == null ? 'The stream could not be opened.' : 'The stream could not be opened: $last';
}
