// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';

import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_flight_manager/video/video_backend.dart';
import 'package:apx_flight_manager/video/video_manager.dart';
import 'package:apx_flight_manager/video/video_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory recDir;
  late List<FakeVideoBackend> backends;
  late ProviderContainer c;
  bool autoFrame = true;
  Object? factoryError;

  ProviderContainer make(VideoSettings s) {
    final data = tempDataDir();
    final container = ProviderContainer(
      overrides: [
        dataDirProvider.overrideWithValue(data),
        videoBackendFactoryProvider.overrideWithValue((s, {headless = false}) async {
          if (factoryError != null) throw factoryError!;
          final b = FakeVideoBackend(autoFirstFrame: autoFrame);
          backends.add(b);
          return b;
        }),
      ],
    );
    container.read(videoSettingsProvider.notifier).update((_) => s);
    addTearDown(container.dispose);
    return container;
  }

  VideoSessionState st() => c.read(videoManagerProvider);
  VideoManager mgr() => c.read(videoManagerProvider.notifier);

  setUp(() {
    recDir = tempDataDir();
    backends = [];
    autoFrame = true;
    factoryError = null;
  });

  test('auto-connects and plays; reports stream details', () async {
    c = make(testVideoSettings(recDir));
    expect(st().status, VideoStatus.idle);
    await until(() => st().status == VideoStatus.playing, what: 'playing');
    expect(backends.single.opened.single.url, 'rtsp://192.168.144.25:8554/main');
    await until(() => st().info != null, what: 'info');
    expect(st().info!.summary, contains('1280×720'));
  });

  test('a failure reconnects after the delay and recovers', () async {
    c = make(testVideoSettings(recDir));
    await until(() => st().status == VideoStatus.playing);
    final b = backends.single;
    b.emit(const VideoBackendError('Connection refused — nothing is serving video at that address and port.'));
    await until(() => st().status == VideoStatus.reconnecting, what: 'reconnecting');
    expect(st().attempt, 1);
    expect(st().message, contains('refused'));
    expect(st().retryAt!.difference(DateTime.now()).inMilliseconds, inInclusiveRange(500, 1100));
    await until(() => st().status == VideoStatus.playing, what: 'recovered');
    expect(st().attempt, 0);
    expect(b.opened, hasLength(2), reason: 'same backend reused, no new decoder');
  });

  test('gives up after the maximum number of attempts', () async {
    c = make(testVideoSettings(recDir).copyWith(maxReconnectAttempts: 1));
    await until(() => st().status == VideoStatus.playing);
    autoFrame = false;
    backends.single.autoFirstFrame = false;
    backends.single.emit(const VideoBackendError('boom'));
    await until(() => st().status == VideoStatus.reconnecting);
    await until(() => st().status == VideoStatus.connecting, what: 'retry');
    backends.single.emit(const VideoBackendError('boom again'));
    await until(() => st().status == VideoStatus.error, what: 'error');
    expect(st().message, 'boom again');
  });

  test('no first frame within the timeout counts as a failure', () async {
    autoFrame = false;
    c = make(testVideoSettings(recDir));
    await until(() => st().status == VideoStatus.connecting);
    await until(() => st().status == VideoStatus.reconnecting, timeout: const Duration(seconds: 5));
    expect(st().message, contains('No video received within 2 s'));
  });

  test('a stalled picture is detected and reconnected', () async {
    c = make(testVideoSettings(recDir));
    await until(() => st().status == VideoStatus.playing);
    // No VideoFrameProgress from here on.
    await until(() => st().status == VideoStatus.reconnecting, timeout: const Duration(seconds: 5));
    expect(st().message, contains('stalled'));
  });

  test('frames keep a playing stream alive', () async {
    c = make(testVideoSettings(recDir));
    await until(() => st().status == VideoStatus.playing);
    final t = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => backends.single.emit(const VideoFrameProgress()),
    );
    addTearDown(t.cancel);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(st().status, VideoStatus.playing);
  });

  test('Stop is honoured: no reconnect until Start', () async {
    c = make(testVideoSettings(recDir));
    await until(() => st().status == VideoStatus.playing);
    await mgr().disconnect();
    expect(st().status, VideoStatus.idle);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(st().status, VideoStatus.idle);
    expect(backends.single.opened, hasLength(1));
    await mgr().connect();
    await until(() => st().status == VideoStatus.playing);
  });

  test('pause and resume; a long pause rejoins live', () async {
    c = make(testVideoSettings(recDir).copyWith(timeoutSec: 20));
    await until(() => st().status == VideoStatus.playing);
    await mgr().togglePause();
    expect(st().status, VideoStatus.paused);
    expect(backends.single.paused, isTrue);
    await mgr().togglePause();
    expect(st().status, VideoStatus.playing);
    expect(backends.single.paused, isFalse);
    expect(backends.single.opened, hasLength(1));

    await mgr().togglePause();
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await mgr().togglePause();
    await until(() => st().status == VideoStatus.playing);
    expect(backends.single.opened, hasLength(2), reason: 'reopened at the live edge');
  });

  test('recording: start, survive a drop-out as a new part, stop', () async {
    c = make(testVideoSettings(recDir).copyWith(timeoutSec: 20));
    await until(() => st().status == VideoStatus.playing);
    await mgr().startRecording();
    expect(st().recording, RecordingStatus.recording);
    expect(st().recordingStartedAt, isNotNull);
    final first = st().recordingFiles.single;
    expect(first, endsWith('.mkv'));
    expect(File(first).existsSync(), isTrue);
    expect(mgr().togglePause, returnsNormally);
    await mgr().togglePause();
    expect(st().status, VideoStatus.playing, reason: 'no pausing while recording');

    backends.single.emit(const VideoBackendError('link lost'));
    await until(() => st().recording == RecordingStatus.waiting, what: 'waiting');
    await until(() => st().recording == RecordingStatus.recording, what: 'resumed');
    expect(st().recordingFiles, hasLength(2));
    expect(st().recordingFiles.last, endsWith('_part2.mkv'));

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await mgr().stopRecording();
    expect(st().recording, RecordingStatus.idle);
    expect(st().notice!.text, contains('Recording saved'));
    expect(st().notice!.text, contains('2 parts'));
    expect(backends.single.recorded, hasLength(2));
    for (final p in backends.single.recorded) {
      expect(File(p).lengthSync(), greaterThan(0));
    }
  });

  test('recording needs live video; MP4 when chosen', () async {
    autoFrame = false;
    c = make(testVideoSettings(recDir).copyWith(recordingFormat: RecordingFormat.mp4, timeoutSec: 20));
    await until(() => st().status == VideoStatus.connecting);
    await mgr().startRecording();
    expect(st().recording, RecordingStatus.idle);
    expect(st().notice!.text, contains('once the video is playing'));
    backends.single.emit(const VideoFirstFrame(640, 480));
    await until(() => st().status == VideoStatus.playing);
    await mgr().startRecording();
    expect(st().recordingFiles.single, endsWith('.mp4'));
    await mgr().stopRecording();
  });

  test('recording into an unwritable folder fails clearly', () async {
    final file = File('${recDir.path}/not_a_folder')..writeAsStringSync('x');
    c = make(testVideoSettings(recDir).copyWith(recordingDir: () => '${file.path}/sub', timeoutSec: 20));
    await until(() => st().status == VideoStatus.playing);
    await mgr().startRecording();
    expect(st().recording, RecordingStatus.idle);
    expect(st().notice!.level, NoticeLevel.error);
    expect(st().notice!.text, contains('Cannot record'));
  });

  test('storage limit removes the oldest recordings first', () async {
    for (var i = 0; i < 3; i++) {
      final f = File('${recDir.path}/APX_2020-01-0${i + 1}_00-00-00.mkv')
        ..writeAsBytesSync(List.filled(1024 * 1024, 0));
      f.setLastModifiedSync(DateTime(2020, 1, i + 1));
    }
    final unrelated = File('${recDir.path}/holiday.mkv')..writeAsBytesSync(List.filled(4 * 1024 * 1024, 0));
    // 1 MB limit with 200 MB reserved: every APX recording must go, nothing else.
    c = make(testVideoSettings(recDir).copyWith(storageLimitMb: 1, timeoutSec: 20));
    await until(() => st().status == VideoStatus.playing);
    await mgr().startRecording();
    expect(File('${recDir.path}/APX_2020-01-01_00-00-00.mkv').existsSync(), isFalse);
    expect(File('${recDir.path}/APX_2020-01-03_00-00-00.mkv').existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
    expect(st().recording, RecordingStatus.recording);
    await mgr().stopRecording();
  });

  test('snapshot is written next to the recordings', () async {
    c = make(testVideoSettings(recDir));
    await until(() => st().status == VideoStatus.playing);
    final path = await mgr().takeSnapshot();
    expect(path, isNotNull);
    expect(path, endsWith('_snapshot.jpg'));
    expect(File(path!).readAsBytesSync(), [0xFF, 0xD8, 0xFF, 0xD9]);
  });

  test('settings changes: new source reconnects, hardware toggle rebuilds the decoder, off releases it', () async {
    c = make(testVideoSettings(recDir));
    await until(() => st().status == VideoStatus.playing);
    final rev = st().backendRevision;
    c.read(videoSettingsProvider.notifier).update((s) => s.copyWith(rtspUrl: 'rtsp://10.0.0.9/other'));
    await until(() => backends.single.opened.length == 2, what: 'reopen');
    expect(backends.single.opened.last.url, 'rtsp://10.0.0.9/other');

    c.read(videoSettingsProvider.notifier).update((s) => s.copyWith(hardwareAcceleration: false));
    await until(() => backends.length == 2, what: 'new backend');
    expect(backends.first.disposed, isTrue);
    await until(() => st().status == VideoStatus.playing);
    expect(st().backendRevision, greaterThan(rev));

    // Display-only change: nothing restarts.
    c.read(videoSettingsProvider.notifier).update((s) => s.copyWith(fit: VideoFit.fill));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(backends.last.opened, hasLength(1));

    c.read(videoSettingsProvider.notifier).update((s) => s.copyWith(enabled: false));
    await until(() => st().status == VideoStatus.disabled);
    expect(backends.last.disposed, isTrue);
  });

  test('invalid settings are reported instead of connecting', () async {
    c = make(testVideoSettings(recDir).copyWith(rtspUrl: 'http://nope'));
    await until(() => st().status == VideoStatus.error);
    expect(st().message, contains('Check the video settings'));
    expect(backends, isEmpty);
  });

  test('a missing video engine is reported, not thrown', () async {
    factoryError = Exception('Cannot find libmpv');
    c = make(testVideoSettings(recDir));
    await until(() => st().status == VideoStatus.unavailable);
    expect(st().message, contains('libmpv'));
  });

  test('test connection uses a separate headless player', () async {
    c = make(testVideoSettings(recDir, autoConnect: false));
    final r = await mgr().testConnection(testVideoSettings(recDir).copyWith(rtspUrl: 'rtsp://10.9.9.9/t'));
    expect(r.ok, isTrue);
    expect(r.info!.width, 1280);
    expect(backends.single.disposed, isTrue);
    expect(st().status, VideoStatus.idle);

    autoFrame = false;
    final bad = await mgr().testConnection(testVideoSettings(recDir).copyWith(timeoutSec: 2));
    expect(bad.ok, isFalse);
    expect(bad.message, contains('No video within 2 s'));
  });

  test('shutdown finishes the recording', () async {
    c = make(testVideoSettings(recDir).copyWith(timeoutSec: 20));
    await until(() => st().status == VideoStatus.playing);
    await mgr().startRecording();
    final b = backends.single;
    await mgr().shutdown();
    expect(b.recordingPath, isNull);
    expect(b.disposed, isTrue);
    expect(st().recording, RecordingStatus.idle);
  });

  group('server diagnosis for unexplained failures', () {
    test('refused, answered, and non-TCP URLs', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = closed.port;
      await closed.close();
      expect(await diagnoseStreamServer('rtsp://127.0.0.1:$deadPort/live'), contains('refused'));

      final open = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(open.close);
      open.listen((s) => s.destroy());
      expect(await diagnoseStreamServer('rtsp://127.0.0.1:${open.port}/wrong'), contains('/wrong'));

      expect(await diagnoseStreamServer('udp://0.0.0.0:5600'), isNull);
      expect(await diagnoseStreamServer('/tmp/x.sdp'), isNull);
    });

    test('a generic engine error while connecting is explained by probing the server', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      autoFrame = false;
      c = make(testVideoSettings(recDir).copyWith(rtspUrl: 'rtsp://127.0.0.1:$port/main', timeoutSec: 20));
      await until(() => st().status == VideoStatus.connecting);
      backends.single.emit(const VideoBackendError('No video in a recognised format arrived.', generic: true));
      await until(() => st().status == VideoStatus.reconnecting);
      expect(st().message, contains('Connection refused'));
    });
  });
}
