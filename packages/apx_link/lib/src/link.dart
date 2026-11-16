// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:typed_data';

import 'package:apx_mavlink/apx_mavlink.dart';

import 'signal.dart';

enum LinkKind { udp, tcp, serial, replay }

/// Transport state. Vehicle‑level "lost" (no heartbeat) is decided by the
/// vehicle session, not here.
enum LinkState { idle, connecting, up, reconnecting, closed, failed }

/// What a link is, for display and for saved connection profiles.
final class LinkDescriptor {
  const LinkDescriptor(this.kind, this.label, this.address);

  final LinkKind kind;

  /// e.g. "SITL", "Telemetry radio".
  final String label;

  /// e.g. "udp:0.0.0.0:14550", "tcp:127.0.0.1:5760", "serial:/dev/ttyACM0@115200".
  final String address;

  @override
  String toString() => '$label ($address)';
}

/// Rolling transport counters, sampled once per second.
final class LinkStatistics {
  int bytesIn = 0;
  int bytesOut = 0;
  int framesIn = 0;
  int framesOut = 0;
  double bytesInPerSecond = 0;
  double framesInPerSecond = 0;
  DateTime? lastFrameAt;

  /// False until the first one‑second sample, when the rates are still 0.
  bool hasRates = false;

  int _lastBytes = 0;
  int _lastFrames = 0;
  DateTime _lastSample = DateTime.now();

  void sample(DateTime now) {
    final dt = now.difference(_lastSample).inMicroseconds / 1e6;
    if (dt <= 0) return;
    bytesInPerSecond = (bytesIn - _lastBytes) / dt;
    framesInPerSecond = (framesIn - _lastFrames) / dt;
    _lastBytes = bytesIn;
    _lastFrames = framesIn;
    _lastSample = now;
    hasRates = true;
  }
}

/// A MAVLink transport. Each link owns its own [MavParser].
abstract class Link {
  Link(this.descriptor);

  final LinkDescriptor descriptor;
  final Signal<LinkState> state = Signal(LinkState.idle);
  final LinkStatistics stats = LinkStatistics();
  final MavParser parser = MavParser();

  /// Last transport error, for the connection sheet.
  String? lastError;

  final _frames = StreamController<MavlinkFrame>.broadcast(sync: true);
  Timer? _statsTimer;

  /// Validated frames received on this link.
  Stream<MavlinkFrame> get frames => _frames.stream;

  Future<void> open() async {
    _statsTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => stats.sample(DateTime.now()));
    await openTransport();
  }

  Future<void> close() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    await closeTransport();
    state.value = LinkState.closed;
  }

  /// Sends one encoded frame. Silently dropped while the link is not up.
  Future<void> send(Uint8List frame) async {
    if (state.value != LinkState.up) return;
    stats.bytesOut += frame.length;
    stats.framesOut++;
    await writeTransport(frame);
  }

  /// Subclasses call this with every received chunk.
  void onBytes(List<int> data) {
    stats.bytesIn += data.length;
    for (final f in parser.add(data)) {
      stats.framesIn++;
      stats.lastFrameAt = DateTime.now();
      _frames.add(f);
    }
  }

  Future<void> dispose() async {
    await close();
    await _frames.close();
    await state.dispose();
  }

  // Transport hooks.
  Future<void> openTransport();
  Future<void> closeTransport();
  Future<void> writeTransport(Uint8List frame);
}
