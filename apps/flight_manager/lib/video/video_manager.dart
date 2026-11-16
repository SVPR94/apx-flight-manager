// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import 'media_kit_backend.dart';
import 'video_backend.dart';
import 'video_settings.dart';
import 'video_storage.dart';

enum VideoStatus {
  /// Video is switched off in Settings.
  disabled,

  /// The video engine could not be loaded on this machine.
  unavailable,

  /// Enabled but not connected (stopped by the user, or auto-connect off).
  idle,
  connecting,
  playing,
  paused,

  /// Lost; trying again after a delay.
  reconnecting,

  /// Gave up (or the settings are invalid). [VideoSessionState.message] says why.
  error,
}

enum RecordingStatus {
  idle,
  starting,
  recording,

  /// Recording, but the stream dropped: a new file part starts on reconnect.
  waiting,
  stopping,
}

enum NoticeLevel { info, warning, error }

/// A one-off message for the user (shown as a snackbar).
@immutable
final class VideoNotice {
  const VideoNotice(this.id, this.text, [this.level = NoticeLevel.info]);
  final int id;
  final String text;
  final NoticeLevel level;
}

@immutable
final class VideoSessionState {
  const VideoSessionState({
    this.status = VideoStatus.disabled,
    this.message,
    this.attempt = 0,
    this.retryAt,
    this.info,
    this.backendRevision = 0,
    this.recording = RecordingStatus.idle,
    this.recordingStartedAt,
    this.recordingFiles = const [],
    this.notice,
  });

  final VideoStatus status;
  final String? message;

  /// Consecutive failed attempts (0 while playing).
  final int attempt;
  final DateTime? retryAt;
  final VideoStreamInfo? info;

  /// Bumped when the decoder/renderer is recreated, so views re-attach.
  final int backendRevision;
  final RecordingStatus recording;
  final DateTime? recordingStartedAt;
  final List<String> recordingFiles;
  final VideoNotice? notice;

  bool get isRecording => recording != RecordingStatus.idle;

  /// Something to show (a picture, or a frozen frame while paused).
  bool get hasPicture => status == VideoStatus.playing || status == VideoStatus.paused;

  /// The manager is trying to show video (connecting, playing or retrying).
  bool get isActive =>
      status == VideoStatus.connecting ||
      status == VideoStatus.playing ||
      status == VideoStatus.paused ||
      status == VideoStatus.reconnecting;

  VideoSessionState copyWith({
    VideoStatus? status,
    String? Function()? message,
    int? attempt,
    DateTime? Function()? retryAt,
    VideoStreamInfo? Function()? info,
    int? backendRevision,
    RecordingStatus? recording,
    DateTime? Function()? recordingStartedAt,
    List<String>? recordingFiles,
    VideoNotice? notice,
  }) => VideoSessionState(
    status: status ?? this.status,
    message: message != null ? message() : this.message,
    attempt: attempt ?? this.attempt,
    retryAt: retryAt != null ? retryAt() : this.retryAt,
    info: info != null ? info() : this.info,
    backendRevision: backendRevision ?? this.backendRevision,
    recording: recording ?? this.recording,
    recordingStartedAt: recordingStartedAt != null ? recordingStartedAt() : this.recordingStartedAt,
    recordingFiles: recordingFiles ?? this.recordingFiles,
    notice: notice ?? this.notice,
  );
}

/// Result of "Test connection".
@immutable
final class VideoTestResult {
  const VideoTestResult.ok(this.info, this.elapsed) : ok = true, message = null;
  const VideoTestResult.failed(this.message, this.elapsed) : ok = false, info = null;
  final bool ok;
  final String? message;
  final VideoStreamInfo? info;
  final Duration elapsed;
}

/// Creates the decoder/renderer. [headless] = no picture (connection tests).
typedef VideoBackendCreator = Future<VideoBackend> Function(VideoSettings settings, {bool headless});

final videoBackendFactoryProvider = Provider<VideoBackendCreator>(
  (ref) =>
      (s, {headless = false}) async =>
          headless ? MediaKitVideoBackend.createHeadless(s) : MediaKitVideoBackend.create(s),
);

/// Free space needed to start recording, and the level at which a running
/// recording is stopped so the device never fills up completely.
const minFreeToStart = 500 * 1024 * 1024;
const minFreeWhileRecording = 150 * 1024 * 1024;

/// Folder used for recordings; resolves the platform default once.
final recordingDirProvider = FutureProvider<Directory>((ref) async {
  final custom = ref.watch(videoSettingsProvider.select((s) => s.recordingDir));
  return custom != null ? Directory(custom) : defaultRecordingDir();
});

/// The single live stream of the app (video streaming pipeline):
/// owns the decoder, keeps it running across view changes (map ↔ video,
/// picture-in-picture, full screen), reconnects, records and snapshots.
final class VideoManager extends Notifier<VideoSessionState> {
  VideoBackend? _backend;
  List<Object?>? _backendKey;
  StreamSubscription<VideoBackendEvent>? _eventsSub;
  Timer? _watchdog, _retry, _settingsDebounce, _infoTimer;
  AppLifecycleListener? _lifecycle;

  /// Bumped on every open/stop so stale async work and events are dropped.
  int _gen = 0;
  DateTime _openedAt = DateTime.now();
  DateTime _lastFrame = DateTime.now();
  DateTime? _pausedAt;

  /// The user pressed Stop: don't reconnect or auto-connect until they press Start.
  bool _userStopped = false;

  /// Stopped because the app went to the background (mobile); resume on return.
  bool _suspended = false;
  int _noticeId = 0;

  String? _recordingStem;
  Directory? _recordingDir;
  int _segment = 0;
  DateTime _lastRecordCheck = DateTime.now();
  int _lastRecordedBytes = -1;
  DateTime _lastGrowth = DateTime.now();

  VideoBackend? get backend => _backend;
  VideoSettings get _settings => ref.read(videoSettingsProvider);

  @override
  VideoSessionState build() {
    ref.listen(videoSettingsProvider, _onSettingsChanged);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle, onExitRequested: _onExitRequested);
    ref.onDispose(_teardown);
    final s = _settings;
    if (s.enabled && s.autoConnect) scheduleMicrotask(connect);
    return VideoSessionState(status: s.enabled ? VideoStatus.idle : VideoStatus.disabled);
  }

  // ---------------------------------------------------------------- control

  /// Starts (or restarts) the stream.
  Future<void> connect() async {
    if (!ref.mounted) return;
    _userStopped = false;
    _suspended = false;
    final s = _settings;
    if (!s.enabled) return;
    final problems = validateVideoSettings(s);
    if (problems.isNotEmpty) {
      _cancelTimers();
      state = state.copyWith(
        status: VideoStatus.error,
        message: () => 'Check the video settings: ${problems.values.first}',
        retryAt: () => null,
      );
      return;
    }
    await _open(resetAttempts: true);
  }

  /// Stops the stream (and any recording) until [connect].
  Future<void> disconnect() async {
    _userStopped = true;
    if (state.isRecording) await stopRecording();
    await _close(VideoStatus.idle, message: null);
  }

  /// Pause/resume. A live stream can't be paused for long without falling
  /// behind, so resuming after more than 2 s jumps back to live (reconnects).
  Future<void> togglePause() async {
    final b = _backend;
    if (b == null) return;
    if (state.status == VideoStatus.playing) {
      if (state.isRecording) {
        _notice('Stop recording before pausing the video.', NoticeLevel.warning);
        return;
      }
      await b.setPaused(true);
      _pausedAt = DateTime.now();
      state = state.copyWith(status: VideoStatus.paused);
    } else if (state.status == VideoStatus.paused) {
      final pausedFor = DateTime.now().difference(_pausedAt ?? DateTime.now());
      _pausedAt = null;
      if (pausedFor > const Duration(seconds: 2)) {
        await _open(resetAttempts: true);
      } else {
        await b.setPaused(false);
        _lastFrame = DateTime.now();
        state = state.copyWith(status: VideoStatus.playing);
      }
    }
  }

  /// Skips the reconnect countdown, or retries after an error.
  Future<void> retryNow() => connect();

  // ------------------------------------------------------------- open/close

  Future<bool> _ensureBackend() async {
    final s = _settings;
    if (_backend != null && listEquals(_backendKey, s.backendKey)) return true;
    await _disposeBackend();
    try {
      final b = await ref.read(videoBackendFactoryProvider)(s);
      if (!ref.mounted) {
        await b.dispose();
        return false;
      }
      _backend = b;
      _backendKey = s.backendKey;
      _eventsSub = b.events.listen(_onEvent);
      state = state.copyWith(backendRevision: state.backendRevision + 1);
      return true;
    } catch (e) {
      debugPrint('video: engine unavailable: $e');
      state = state.copyWith(
        status: VideoStatus.unavailable,
        message: () => 'The video engine (libmpv) could not be loaded: $e',
      );
      return false;
    }
  }

  Future<void> _open({required bool resetAttempts}) async {
    _cancelTimers();
    final gen = ++_gen;
    if (!await _ensureBackend() || gen != _gen || !ref.mounted) return;
    final s = _settings;
    final b = _backend!;
    _openedAt = DateTime.now();
    state = state.copyWith(
      status: VideoStatus.connecting,
      message: () => null,
      retryAt: () => null,
      info: () => null,
      attempt: resetAttempts ? 0 : state.attempt,
    );
    try {
      await b.stop();
      if (gen != _gen) return;
      await b.open(VideoEndpoint.of(s), VideoTuning.of(s));
    } catch (e) {
      if (gen == _gen) await _fail('Could not open the stream: $e');
      return;
    }
    if (gen != _gen || !ref.mounted) return;
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _close(VideoStatus status, {String? message}) async {
    _cancelTimers();
    _gen++;
    _pausedAt = null;
    try {
      await _backend?.stop();
    } catch (_) {}
    if (!ref.mounted) return;
    state = state.copyWith(status: status, message: () => message, retryAt: () => null, info: () => null, attempt: 0);
  }

  Future<void> _fail(String reason) async {
    if (!ref.mounted) return;
    _cancelTimers();
    final gen = ++_gen;
    try {
      await _backend?.stop();
    } catch (_) {}
    if (gen != _gen || !ref.mounted) return;
    if (state.recording == RecordingStatus.recording) {
      // The stream is gone, so is the recorder's input: close this part.
      await _closeSegment();
      state = state.copyWith(recording: RecordingStatus.waiting);
    }
    final s = _settings;
    final attempt = state.attempt + 1;
    final canRetry =
        s.autoReconnect && !_userStopped && (s.maxReconnectAttempts == 0 || attempt <= s.maxReconnectAttempts);
    if (!canRetry) {
      state = state.copyWith(status: VideoStatus.error, message: () => reason, attempt: attempt, retryAt: () => null);
      if (state.isRecording) await stopRecording();
      return;
    }
    // Back off: delay, 2×, 4×, … capped at 30 s.
    final delay = Duration(milliseconds: math.min(30000, s.reconnectDelaySec * 1000 * (1 << math.min(attempt - 1, 4))));
    final at = DateTime.now().add(delay);
    state = state.copyWith(
      status: VideoStatus.reconnecting,
      message: () => reason,
      attempt: attempt,
      retryAt: () => at,
    );
    _retry = Timer(delay, () {
      if (gen == _gen && ref.mounted) _open(resetAttempts: false);
    });
  }

  void _onEvent(VideoBackendEvent e) {
    if (!ref.mounted) return;
    switch (e) {
      case VideoFirstFrame():
        if (state.status != VideoStatus.connecting) return;
        _lastFrame = DateTime.now();
        state = state.copyWith(status: VideoStatus.playing, attempt: 0, message: () => null, retryAt: () => null);
        _refreshInfo();
        _infoTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshInfo());
        if (state.recording == RecordingStatus.waiting) unawaited(_startSegment());
      case VideoFrameProgress():
        _lastFrame = DateTime.now();
      case VideoBackendError(:final message, :final generic):
        if (state.status == VideoStatus.connecting && generic) {
          unawaited(_diagnoseAndFail(message));
        } else if (state.status == VideoStatus.connecting || state.status == VideoStatus.playing) {
          _fail(message);
        }
      case VideoStreamEnded():
        if (state.status == VideoStatus.playing || state.status == VideoStatus.connecting) {
          _fail('The video stream ended (the camera or server stopped sending).');
        }
    }
  }

  /// The engine couldn't say why a stream didn't open: try a plain TCP
  /// connection to the server to tell the pilot something actionable.
  Future<void> _diagnoseAndFail(String fallback) async {
    final gen = _gen;
    final reason = await diagnoseStreamServer(VideoEndpoint.of(_settings).url) ?? fallback;
    if (gen == _gen && ref.mounted && state.status == VideoStatus.connecting) await _fail(reason);
  }

  Future<void> _refreshInfo() async {
    final gen = _gen;
    try {
      final info = await _backend?.info();
      if (gen != _gen || !ref.mounted || info == null || !state.hasPicture) return;
      state = state.copyWith(info: () => info);
    } catch (_) {}
  }

  void _tick() {
    if (!ref.mounted) return;
    final t = Duration(seconds: _settings.timeoutSec);
    final now = DateTime.now();
    if (state.status == VideoStatus.connecting && now.difference(_openedAt) > t) {
      _fail('No video received within ${t.inSeconds} s — check the address/port and that the camera is streaming.');
    } else if (state.status == VideoStatus.playing && now.difference(_lastFrame) > t) {
      _fail('The video stalled — no new frames for ${t.inSeconds} s.');
    }
    if (state.recording == RecordingStatus.recording &&
        now.difference(_lastRecordCheck) >= const Duration(seconds: 5)) {
      _lastRecordCheck = now;
      _checkRecording();
    }
  }

  void _cancelTimers() {
    _watchdog?.cancel();
    _retry?.cancel();
    _infoTimer?.cancel();
    _watchdog = _retry = _infoTimer = null;
  }

  // -------------------------------------------------------------- recording

  Future<void> toggleRecording() => state.isRecording ? stopRecording() : startRecording();

  Future<void> startRecording() async {
    if (state.isRecording) return;
    if (state.status != VideoStatus.playing) {
      _notice('Recording starts once the video is playing.', NoticeLevel.warning);
      return;
    }
    state = state.copyWith(recording: RecordingStatus.starting);
    final s = _settings;
    try {
      final dir = await ref.read(recordingDirProvider.future);
      await dir.create(recursive: true);
      // Writable? (A folder on a removed drive, or without permission.)
      final probe = File('${dir.path}${Platform.pathSeparator}.apx_write_test');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      final free = freeBytes(dir.path);
      if (free != null && free < minFreeToStart) {
        throw _RecordingError(
          'Not enough free space to record: ${formatBytes(free)} free, ${formatBytes(minFreeToStart)} needed.',
        );
      }
      if (s.storageLimitMb > 0) {
        final removed = enforceStorageLimit(dir, s.storageLimitMb * 1024 * 1024, reserveBytes: 200 * 1024 * 1024);
        if (removed.isNotEmpty) {
          _notice('Storage limit: deleted ${removed.length} old recording${removed.length == 1 ? '' : 's'}.');
        }
      }
      _recordingDir = dir;
      _recordingStem = recordingStem(DateTime.now());
      _segment = 0;
      state = state.copyWith(recordingFiles: const []);
      await _startSegment(throwOnError: true);
      state = state.copyWith(recordingStartedAt: () => DateTime.now());
    } on _RecordingError catch (e) {
      _abortRecording(e.message);
    } on FileSystemException catch (e) {
      _abortRecording('Cannot record to that folder: ${e.osError?.message ?? e.message} (${e.path ?? ''})');
    } catch (e) {
      _abortRecording('Recording failed to start: $e');
    }
  }

  void _abortRecording(String why) {
    if (!ref.mounted) return;
    state = state.copyWith(recording: RecordingStatus.idle, recordingStartedAt: () => null);
    _notice(why, NoticeLevel.error);
  }

  Future<void> _startSegment({bool throwOnError = false}) async {
    final b = _backend, dir = _recordingDir, stem = _recordingStem;
    if (b == null || dir == null || stem == null) return;
    _segment++;
    final ext = _settings.recordingFormat.extension;
    final name = _segment == 1 ? '$stem.$ext' : '${stem}_part$_segment.$ext';
    final path = '${dir.path}${Platform.pathSeparator}$name';
    try {
      await b.startRecording(path);
    } catch (e) {
      if (throwOnError) rethrow;
      _notice('Recording could not resume after reconnecting: $e', NoticeLevel.error);
      return;
    }
    if (!ref.mounted) return;
    _lastRecordCheck = DateTime.now();
    _lastRecordedBytes = -1;
    _lastGrowth = DateTime.now();
    state = state.copyWith(recording: RecordingStatus.recording, recordingFiles: [...state.recordingFiles, path]);
  }

  Future<void> _closeSegment() async {
    try {
      await _backend?.stopRecording();
    } catch (_) {}
  }

  /// Every few seconds while recording: is the file growing, is there room?
  void _checkRecording() {
    final files = state.recordingFiles;
    if (files.isEmpty) return;
    final f = File(files.last);
    final size = f.existsSync() ? f.lengthSync() : 0;
    if (size > _lastRecordedBytes) {
      _lastRecordedBytes = size;
      _lastGrowth = DateTime.now();
    } else if (DateTime.now().difference(_lastGrowth) > const Duration(seconds: 10)) {
      _notice('The recording file is not growing — the disk may be full or removed.', NoticeLevel.warning);
      _lastGrowth = DateTime.now();
    }
    final free = freeBytes(f.parent.path);
    if (free != null && free < minFreeWhileRecording) {
      stopRecording(reason: 'Recording stopped: storage almost full (${formatBytes(free)} left).');
    }
  }

  Future<void> stopRecording({String? reason}) async {
    if (!state.isRecording || state.recording == RecordingStatus.stopping) return;
    final wasWriting = state.recording == RecordingStatus.recording;
    state = state.copyWith(recording: RecordingStatus.stopping);
    if (wasWriting) await _closeSegment();
    if (!ref.mounted) return;
    final kept = <File>[];
    for (final p in state.recordingFiles) {
      final f = File(p);
      if (!f.existsSync()) continue;
      if (f.lengthSync() == 0) {
        try {
          f.deleteSync();
        } catch (_) {}
        continue;
      }
      kept.add(f);
    }
    state = state.copyWith(recording: RecordingStatus.idle, recordingStartedAt: () => null, recordingFiles: const []);
    _recordingStem = null;
    if (kept.isEmpty) {
      _notice(reason ?? 'Nothing was recorded (no video data arrived).', NoticeLevel.warning);
      return;
    }
    final size = kept.fold<int>(0, (s, f) => s + f.lengthSync());
    final where = kept.length == 1 ? kept.first.path : '${kept.length} parts in ${kept.first.parent.path}';
    _notice(
      '${reason != null ? '$reason ' : ''}Recording saved (${formatBytes(size)}): $where',
      reason != null ? NoticeLevel.warning : NoticeLevel.info,
    );
    if (_settings.saveToGallery) await _toGallery(kept, video: true);
  }

  /// Saves the current frame as a JPEG next to the recordings.
  Future<String?> takeSnapshot() async {
    final b = _backend;
    if (b == null || !state.hasPicture) {
      _notice('No picture to capture yet.', NoticeLevel.warning);
      return null;
    }
    try {
      final bytes = await b.snapshot();
      if (bytes == null || bytes.isEmpty) throw StateError('the decoder returned no image');
      final dir = await ref.read(recordingDirProvider.future);
      await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}${recordingStem(DateTime.now())}_snapshot.jpg');
      await f.writeAsBytes(bytes, flush: true);
      _notice('Snapshot saved: ${f.path}');
      if (_settings.saveToGallery) await _toGallery([f], video: false);
      return f.path;
    } catch (e) {
      _notice('Snapshot failed: $e', NoticeLevel.error);
      return null;
    }
  }

  Future<void> _toGallery(List<File> files, {required bool video}) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    try {
      if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
        _notice('Gallery access was denied — the files stay in the app folder.', NoticeLevel.warning);
        return;
      }
      for (final f in files) {
        video
            ? await Gal.putVideo(f.path, album: 'APX Flight Manager')
            : await Gal.putImage(f.path, album: 'APX Flight Manager');
      }
      _notice(video ? 'Copied to the gallery (APX Flight Manager album).' : 'Snapshot copied to the gallery.');
    } on GalException catch (e) {
      _notice(switch (e.type) {
        GalExceptionType.notSupportedFormat =>
          'The gallery does not accept this file type — choose MP4 in Settings → Video to save recordings there.',
        GalExceptionType.notEnoughSpace => 'Not enough space to copy to the gallery.',
        GalExceptionType.accessDenied => 'Gallery access was denied.',
        GalExceptionType.unexpected => 'Could not copy to the gallery: ${e.platformException.message}',
      }, NoticeLevel.warning);
    } catch (e) {
      _notice('Could not copy to the gallery: $e', NoticeLevel.warning);
    }
  }

  /// Copies an existing recording/snapshot to the gallery (Android/iOS).
  Future<void> exportToGallery(File f) => _toGallery([f], video: !f.path.toLowerCase().endsWith('.jpg'));

  // ---------------------------------------------------------- test connection

  /// Opens [s] once, headless, and reports what arrived. When the live stream
  /// already shows this source, reports from it instead (a UDP port can only
  /// be bound once).
  Future<VideoTestResult> testConnection(VideoSettings s) async {
    final sw = Stopwatch()..start();
    final problems = validateVideoSettings(s);
    if (problems.isNotEmpty) return VideoTestResult.failed(problems.values.first, sw.elapsed);
    if (listEquals(s.streamKey, _settings.streamKey) && state.hasPicture && _backend != null) {
      return VideoTestResult.ok(await _backend!.info(), sw.elapsed);
    }
    if (s.source.isUdp && state.isActive && _settings.source.isUdp && _settings.udpPort == s.udpPort) {
      return VideoTestResult.failed(
        'The live stream is using UDP port ${s.udpPort}; stop it first to test a different setup.',
        sw.elapsed,
      );
    }
    VideoBackend? b;
    StreamSubscription<VideoBackendEvent>? sub;
    try {
      b = await ref.read(videoBackendFactoryProvider)(s, headless: true);
      final done = Completer<VideoTestResult>();
      sub = b.events.listen((e) async {
        if (done.isCompleted) return;
        switch (e) {
          case VideoFirstFrame():
            // Let the decoder settle so codec/fps are filled in.
            await Future<void>.delayed(const Duration(milliseconds: 600));
            if (!done.isCompleted) done.complete(VideoTestResult.ok(await b!.info(), sw.elapsed));
          case VideoBackendError(:final message, :final generic):
            final why = generic ? await diagnoseStreamServer(VideoEndpoint.of(s).url) ?? message : message;
            if (!done.isCompleted) done.complete(VideoTestResult.failed(why, sw.elapsed));
          case VideoStreamEnded():
            done.complete(VideoTestResult.failed('The stream ended right after opening.', sw.elapsed));
          case VideoFrameProgress():
            break;
        }
      });
      await b.open(VideoEndpoint.of(s), VideoTuning.of(s));
      return await done.future.timeout(
        Duration(seconds: s.timeoutSec),
        onTimeout: () => VideoTestResult.failed(
          'No video within ${s.timeoutSec} s. Check the address/port, the network, and that the camera is streaming.',
          sw.elapsed,
        ),
      );
    } catch (e) {
      return VideoTestResult.failed('$e', sw.elapsed);
    } finally {
      await sub?.cancel();
      await b?.dispose();
    }
  }

  // ------------------------------------------------------- settings/lifecycle

  void _onSettingsChanged(VideoSettings? prev, VideoSettings next) {
    if (prev == null) return;
    if (!next.enabled) {
      if (prev.enabled) unawaited(_turnOff());
      return;
    }
    if (!prev.enabled) {
      state = state.copyWith(status: VideoStatus.idle, message: () => null);
      if (next.autoConnect) unawaited(connect());
      return;
    }
    final restart = !listEquals(prev.streamKey, next.streamKey) || !listEquals(prev.backendKey, next.backendKey);
    if (restart && (state.isActive || state.status == VideoStatus.error || state.status == VideoStatus.unavailable)) {
      // Debounced: several fields often change together.
      _settingsDebounce?.cancel();
      _settingsDebounce = Timer(const Duration(milliseconds: 500), () async {
        if (!ref.mounted) return;
        if (!listEquals(_backendKey, _settings.backendKey) && state.isRecording) {
          await stopRecording(reason: 'Recording stopped: the decoder settings changed.');
        }
        await connect();
      });
    } else if (!prev.autoConnect && next.autoConnect && state.status == VideoStatus.idle && !_userStopped) {
      unawaited(connect());
    }
  }

  Future<void> _turnOff() async {
    _userStopped = false;
    if (state.isRecording) await stopRecording();
    await _close(VideoStatus.disabled);
    await _disposeBackend();
    if (ref.mounted) state = state.copyWith(backendRevision: state.backendRevision + 1);
  }

  /// Phones/tablets: a stream in the background costs battery and data and
  /// nobody sees it — stop it, unless it is being recorded, and resume on return.
  void _onLifecycle(AppLifecycleState s) {
    if (!(Platform.isAndroid || Platform.isIOS) || !ref.mounted) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      if (state.isActive && !state.isRecording && !_suspended) {
        _suspended = true;
        unawaited(_close(VideoStatus.idle, message: 'Paused while the app is in the background.'));
      }
    } else if (s == AppLifecycleState.resumed && _suspended) {
      _suspended = false;
      unawaited(connect());
    }
  }

  /// Desktop window closing: finish the recording so the file is complete.
  Future<AppExitResponse> _onExitRequested() async {
    await shutdown();
    return AppExitResponse.exit;
  }

  /// Ends any recording cleanly and releases the decoder (app exit).
  Future<void> shutdown() async {
    if (!ref.mounted) return;
    if (state.isRecording) await stopRecording();
    _cancelTimers();
    _gen++;
    await _disposeBackend();
  }

  Future<void> _disposeBackend() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    final b = _backend;
    _backend = null;
    _backendKey = null;
    await b?.dispose();
  }

  void _teardown() {
    _cancelTimers();
    _settingsDebounce?.cancel();
    _lifecycle?.dispose();
    _gen++;
    // Fire and forget: the provider is going away (tests, app exit).
    _eventsSub?.cancel();
    final b = _backend;
    _backend = null;
    if (b != null) {
      if (_recordingStem != null) unawaited(b.stopRecording().catchError((Object _) {}));
      unawaited(b.dispose());
    }
  }

  void _notice(String text, [NoticeLevel level = NoticeLevel.info]) {
    if (!ref.mounted) return;
    debugPrint('video: $text');
    state = state.copyWith(notice: VideoNotice(++_noticeId, text, level));
  }
}

final class _RecordingError implements Exception {
  const _RecordingError(this.message);
  final String message;
}

final videoManagerProvider = NotifierProvider<VideoManager, VideoSessionState>(VideoManager.new);

/// For TCP-based URLs (RTSP, TCP, HTTP, RTMP): connects to the server and
/// explains a failure — refused, unknown host, unreachable, no answer. Null
/// when the server accepts connections (the problem is the path/stream) or
/// the URL is not TCP-based.
Future<String?> diagnoseStreamServer(String url, {Duration timeout = const Duration(seconds: 3)}) async {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return null;
  const ports = {'rtsp': 554, 'rtsps': 322, 'tcp': 0, 'http': 80, 'https': 443, 'rtmp': 1935, 'rtmps': 443};
  final scheme = u.scheme.toLowerCase();
  if (!ports.containsKey(scheme)) return null;
  final port = u.hasPort ? u.port : ports[scheme]!;
  if (port <= 0) return null;
  final where = '${u.host}:$port';
  try {
    final s = await Socket.connect(u.host, port, timeout: timeout);
    s.destroy();
    return 'The server at $where answered, but sent no playable video — check the stream path '
        '(${u.path.isEmpty ? '/' : u.path}) and the camera\'s streaming settings.';
  } on SocketException catch (e) {
    final msg = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    final code = e.osError?.errorCode;
    if (msg.contains('refused') || code == 111 || code == 61 || code == 10061) {
      return 'Connection refused — nothing is serving video at $where.';
    }
    if (msg.contains('host lookup') || msg.contains('nodename') || msg.contains('no address associated')) {
      return 'The host name "${u.host}" could not be resolved.';
    }
    if (msg.contains('unreachable') || code == 101 || code == 113 || code == 51 || code == 65 || code == 10051) {
      return 'Network unreachable — no route to $where. Check the link to the vehicle/camera.';
    }
    if (msg.contains('timed out') || code == 110 || code == 60 || code == 10060) {
      return 'No answer from $where (timed out) — check the camera\'s IP address and the network.';
    }
    return 'Cannot reach $where: ${e.osError?.message ?? e.message}';
  } catch (e) {
    return null;
  }
}
