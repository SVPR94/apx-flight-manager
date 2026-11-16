// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:apx_flight_manager/video/video_backend.dart';
import 'package:apx_flight_manager/video/video_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scriptable [VideoBackend]: the test decides when frames, errors and
/// stream ends happen. Recording writes real bytes so file handling is real.
class FakeVideoBackend implements VideoBackend {
  FakeVideoBackend({this.autoFirstFrame = true});

  /// Send [VideoFirstFrame] right after [open].
  bool autoFirstFrame;

  final _events = StreamController<VideoBackendEvent>.broadcast();
  final opened = <VideoEndpoint>[];
  int stops = 0;
  bool paused = false;
  bool disposed = false;
  String? recordingPath;
  final recorded = <String>[];
  Timer? _writer;

  @override
  Stream<VideoBackendEvent> get events => _events.stream;

  void emit(VideoBackendEvent e) => _events.add(e);

  @override
  Future<void> open(VideoEndpoint endpoint, VideoTuning tuning) async {
    opened.add(endpoint);
    if (autoFirstFrame) scheduleMicrotask(() => emit(const VideoFirstFrame(1280, 720)));
  }

  @override
  Future<void> stop() async {
    stops++;
    _writer?.cancel();
    recordingPath = null;
  }

  @override
  Future<void> setPaused(bool p) async => paused = p;

  @override
  Future<VideoStreamInfo> info() async =>
      const VideoStreamInfo(width: 1280, height: 720, codec: 'h264', fps: 30, hwdec: 'no');

  @override
  Future<void> startRecording(String path) async {
    final f = File(path)..writeAsBytesSync(List.filled(1024, 1));
    recordingPath = path;
    recorded.add(path);
    _writer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (f.existsSync()) f.writeAsBytesSync(List.filled(1024, 2), mode: FileMode.append);
    });
  }

  @override
  Future<void> stopRecording() async {
    _writer?.cancel();
    recordingPath = null;
  }

  @override
  Future<Uint8List?> snapshot() async => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  @override
  Widget buildView({required BoxFit fit, double? aspectRatio}) =>
      const ColoredBox(key: ValueKey('fake-video'), color: Color(0xFF102030));

  @override
  Future<void> dispose() async {
    disposed = true;
    _writer?.cancel();
    await _events.close();
  }
}

/// Settings for a test stream that is valid and recording into [dir].
VideoSettings testVideoSettings(Directory dir, {bool autoConnect = true}) => VideoSettings(
  enabled: true,
  source: VideoSourceKind.rtsp,
  rtspUrl: 'rtsp://192.168.144.25:8554/main',
  autoConnect: autoConnect,
  reconnectDelaySec: 1,
  timeoutSec: 2,
  recordingDir: dir.path,
);

/// Waits (real time) until [cond] holds.
Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 8), String? what}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) fail('timed out waiting for ${what ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
