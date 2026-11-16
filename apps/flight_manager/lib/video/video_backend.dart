// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'video_settings.dart';

/// What the decoder reports about the stream it is showing.
@immutable
final class VideoStreamInfo {
  const VideoStreamInfo({this.width, this.height, this.codec, this.fps, this.hwdec, this.bitrateKbps});

  final int? width, height;
  final String? codec;
  final double? fps;

  /// Hardware decoder in use, or null/"no" for software.
  final String? hwdec;
  final double? bitrateKbps;

  bool get hardwareDecoding => hwdec != null && hwdec!.isNotEmpty && hwdec != 'no';

  String get summary => [
    if (codec != null && codec!.isNotEmpty) codec!.toUpperCase(),
    if (width != null && height != null) '$width×$height',
    if (fps != null && fps! > 0) '${fps!.toStringAsFixed(fps! % 1 == 0 ? 0 : 1)} fps',
    if (bitrateKbps != null && bitrateKbps! > 0) '${(bitrateKbps! / 1000).toStringAsFixed(1)} Mbit/s',
    hardwareDecoding ? 'HW decode ($hwdec)' : 'SW decode',
  ].join(' · ');
}

/// Events a backend raises while a stream is open.
sealed class VideoBackendEvent {
  const VideoBackendEvent();
}

/// A new frame was presented (sent at most a few times a second).
final class VideoFrameProgress extends VideoBackendEvent {
  const VideoFrameProgress();
}

/// The picture size is known: the first decodable frame has arrived.
final class VideoFirstFrame extends VideoBackendEvent {
  const VideoFirstFrame(this.width, this.height);
  final int width, height;
}

/// The stream could not be opened or failed while playing.
final class VideoBackendError extends VideoBackendEvent {
  const VideoBackendError(this.message, {this.generic = false});
  final String message;

  /// The engine gave no specific reason (the manager then probes the server
  /// itself to tell "refused" from "unreachable" from "wrong path").
  final bool generic;
}

/// The source ended (sender stopped, server closed the session).
final class VideoStreamEnded extends VideoBackendEvent {
  const VideoStreamEnded();
}

/// Tuning applied on every open; derived from [VideoSettings].
@immutable
final class VideoTuning {
  const VideoTuning({required this.lowLatency, required this.audio, required this.timeoutSec});
  factory VideoTuning.of(VideoSettings s) =>
      VideoTuning(lowLatency: s.lowLatency, audio: s.audio, timeoutSec: s.timeoutSec);

  final bool lowLatency, audio;
  final int timeoutSec;
}

/// One decoder/renderer pipeline. The app talks only to this interface, so
/// the stream logic (reconnects, recording, timeouts) is the same on every
/// platform and testable without native code.
///
/// Implementations: [MediaKitVideoBackend] (libmpv + FFmpeg on Android, iOS,
/// Windows, macOS and Linux).
abstract interface class VideoBackend {
  Stream<VideoBackendEvent> get events;

  /// Starts loading [endpoint]. Completes once the request is issued; the
  /// outcome arrives as [VideoFirstFrame] or [VideoBackendError].
  Future<void> open(VideoEndpoint endpoint, VideoTuning tuning);

  /// Closes the stream and releases the network/decoder; the backend stays
  /// usable for another [open].
  Future<void> stop();

  Future<void> setPaused(bool paused);

  Future<VideoStreamInfo> info();

  /// Writes the incoming (still encoded) stream to [path] without re-encoding.
  /// The container follows the extension. Throws if recording can't start.
  Future<void> startRecording(String path);
  Future<void> stopRecording();

  /// The current frame as JPEG, or null if no frame is available.
  Future<Uint8List?> snapshot();

  /// The picture, sized by its parent.
  Widget buildView({required BoxFit fit, double? aspectRatio});

  Future<void> dispose();
}

/// Creates the platform backend for the given settings. Overridden in tests.
typedef VideoBackendFactory = Future<VideoBackend> Function(VideoSettings settings);
