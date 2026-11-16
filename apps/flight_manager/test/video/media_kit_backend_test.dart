// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
@Tags(['media'])
library;

import 'dart:io';

import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_flight_manager/video/media_kit_backend.dart';
import 'package:apx_flight_manager/video/video_manager.dart';
import 'package:apx_flight_manager/video/video_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../support.dart';
import 'fake_backend.dart' show until;

/// End-to-end through the real engine (libmpv + FFmpeg), headless (no GPU
/// texture in `flutter test`), with ffmpeg as the camera.
///
/// Needs libmpv loadable (Linux: `apt install libmpv-dev`, or LD_LIBRARY_PATH)
/// and `ffmpeg` with libx264/libx265 (or FFMPEG=/path/to/ffmpeg); skips
/// otherwise. Optional: VIDEO_TEST_RTSP_URL=rtsp://… for a live RTSP server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? skip;
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    skip = 'libmpv not available: $e';
  }
  final ffmpeg = Platform.environment['FFMPEG'] ?? 'ffmpeg';
  if (skip == null) {
    try {
      Process.runSync(ffmpeg, ['-version']);
    } catch (_) {
      skip = 'ffmpeg not found';
    }
  }

  final senders = <Process>[];
  tearDown(() {
    for (final p in senders) {
      p.kill();
    }
    senders.clear();
  });

  Future<int> freeUdpPort() async {
    final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    s.close();
    return port;
  }

  /// A test-pattern camera: [codec] `h264`/`h265`, [format] `rtp`/`mpegts`.
  Future<Process> camera(String codec, String format, int port) async {
    final enc = codec == 'h264'
        ? ['-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency', '-x264-params', 'repeat-headers=1']
        : ['-c:v', 'libx265', '-preset', 'ultrafast', '-x265-params', 'repeat-headers=1:log-level=error'];
    final p = await Process.start(ffmpeg, [
      '-hide_banner', '-loglevel', 'error', '-re', //
      '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30',
      ...enc, '-g', '15', '-pix_fmt', 'yuv420p',
      if (format == 'rtp') ...[
        '-f',
        'rtp',
        'rtp://127.0.0.1:$port',
      ] else ...[
        '-f',
        'mpegts',
        'udp://127.0.0.1:$port?pkt_size=1316',
      ],
    ]);
    senders.add(p);
    p.stderr.drain<void>();
    p.stdout.drain<void>();
    return p;
  }

  late ProviderContainer c;
  late Directory rec;

  ProviderContainer make(VideoSettings s) {
    final container = ProviderContainer(
      overrides: [
        dataDirProvider.overrideWithValue(tempDataDir()),
        // Headless: decode and record, no picture (no Flutter engine in tests).
        videoBackendFactoryProvider.overrideWithValue(
          (s, {headless = false}) => MediaKitVideoBackend.createHeadless(s),
        ),
      ],
    );
    container.read(videoSettingsProvider.notifier).update((_) => s);
    addTearDown(() async {
      await container.read(videoManagerProvider.notifier).shutdown();
      container.dispose();
    });
    return container;
  }

  VideoSessionState st() => c.read(videoManagerProvider);
  VideoManager mgr() => c.read(videoManagerProvider.notifier);

  Future<Map<String, String>> probe(String path) async {
    final ffprobe = ffmpeg.endsWith('ffmpeg') ? '${ffmpeg.substring(0, ffmpeg.length - 6)}ffprobe' : 'ffprobe';
    final r = await Process.run(ffprobe, [
      '-v', 'error', '-show_entries', 'format=duration:stream=codec_name,width,height', '-of', 'default=nw=1', path, //
    ]);
    return {
      for (final l in (r.stdout as String).split('\n'))
        if (l.contains('=')) l.split('=').first: l.split('=').last,
    };
  }

  setUp(() => rec = tempDataDir());

  VideoSettings udp(VideoSourceKind k, int port) => VideoSettings(
    enabled: true,
    source: k,
    udpPort: port,
    timeoutSec: 6,
    reconnectDelaySec: 1,
    recordingDir: rec.path,
  );

  test('RTP H.264 over UDP: plays, records a valid MKV without re-encoding', () async {
    final port = await freeUdpPort();
    await camera('h264', 'rtp', port);
    c = make(udp(VideoSourceKind.udpH264, port));
    await until(() => st().status == VideoStatus.playing, timeout: const Duration(seconds: 15), what: 'playing');
    await until(() => st().info?.codec != null, what: 'info');
    expect(st().info!.codec, 'h264');
    expect(st().info!.width, 640);

    await mgr().startRecording();
    expect(st().recording, RecordingStatus.recording);
    await Future<void>.delayed(const Duration(seconds: 3));
    final file = st().recordingFiles.single;
    await mgr().stopRecording();
    final info = await probe(file);
    expect(info['codec_name'], 'h264');
    expect(info['width'], '640');
    expect(double.parse(info['duration']!), greaterThan(1.5));
  }, skip: skip);

  test('RTP H.265 over UDP: plays, records a valid MP4', () async {
    final port = await freeUdpPort();
    await camera('h265', 'rtp', port);
    c = make(udp(VideoSourceKind.udpH265, port).copyWith(recordingFormat: RecordingFormat.mp4));
    await until(() => st().status == VideoStatus.playing, timeout: const Duration(seconds: 15), what: 'playing');
    await until(() => st().info?.codec != null, what: 'info');
    expect(st().info!.codec, 'hevc');
    await mgr().startRecording();
    await Future<void>.delayed(const Duration(seconds: 3));
    final file = st().recordingFiles.single;
    await mgr().stopRecording();
    expect(file, endsWith('.mp4'));
    final info = await probe(file);
    expect(info['codec_name'], 'hevc');
    expect(double.parse(info['duration']!), greaterThan(1.5));
  }, skip: skip);

  test('MPEG-TS over UDP plays; losing the camera reconnects when it returns', () async {
    final port = await freeUdpPort();
    final cam = await camera('h264', 'mpegts', port);
    c = make(udp(VideoSourceKind.udpMpegTs, port).copyWith(timeoutSec: 3));
    await until(() => st().status == VideoStatus.playing, timeout: const Duration(seconds: 15), what: 'playing');

    cam.kill();
    await until(
      () => st().status == VideoStatus.reconnecting || st().status == VideoStatus.connecting,
      timeout: const Duration(seconds: 10),
      what: 'loss detected',
    );
    await camera('h264', 'mpegts', port);
    await until(() => st().status == VideoStatus.playing, timeout: const Duration(seconds: 25), what: 'recovered');
  }, skip: skip);

  test('RTSP with nothing listening reports "refused" and retries', () async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    c = make(VideoSettings(enabled: true, rtspUrl: 'rtsp://127.0.0.1:$port/live', timeoutSec: 5, reconnectDelaySec: 5));
    await until(() => st().status == VideoStatus.reconnecting, timeout: const Duration(seconds: 10), what: 'retry');
    expect(st().message, contains('refused'));
  }, skip: skip);

  test('Test connection: silent UDP port times out with a clear message', () async {
    c = make(udp(VideoSourceKind.udpH264, 1).copyWith(enabled: false));
    final port = await freeUdpPort();
    final r = await mgr().testConnection(udp(VideoSourceKind.udpH264, port).copyWith(timeoutSec: 3));
    expect(r.ok, isFalse);
    expect(r.message, contains('No video within 3 s'));
  }, skip: skip);

  test('Test connection: working source reports codec and size', () async {
    c = make(udp(VideoSourceKind.udpH264, 1).copyWith(enabled: false));
    final port = await freeUdpPort();
    await camera('h264', 'rtp', port);
    final r = await mgr().testConnection(udp(VideoSourceKind.udpH264, port));
    expect(r.ok, isTrue, reason: r.message);
    expect(r.info!.summary, contains('640×360'));
  }, skip: skip);

  test('RTSP server (VIDEO_TEST_RTSP_URL)', () async {
    final url = Platform.environment['VIDEO_TEST_RTSP_URL']!;
    final transport = Platform.environment['VIDEO_TEST_RTSP_TRANSPORT'] == 'udp'
        ? RtspTransport.udp
        : RtspTransport.tcp;
    c = make(
      VideoSettings(enabled: true, rtspUrl: url, rtspTransport: transport, timeoutSec: 8, recordingDir: rec.path),
    );
    await until(() => st().status == VideoStatus.playing, timeout: const Duration(seconds: 15), what: 'playing');
    await mgr().startRecording();
    await Future<void>.delayed(const Duration(seconds: 3));
    final file = st().recordingFiles.single;
    await mgr().stopRecording();
    expect(double.parse((await probe(file))['duration']!), greaterThan(1.5));
  }, skip: skip ?? (Platform.environment['VIDEO_TEST_RTSP_URL'] == null ? 'VIDEO_TEST_RTSP_URL not set' : null));
}
