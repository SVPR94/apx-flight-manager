// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';

/// The two‑way path between the GCS and one vehicle (sysid, compid).
/// Services depend on this, not on a [Link], so tests can script a vehicle.
abstract interface class VehicleChannel {
  int get targetSystem;
  int get targetComponent;

  /// Messages from the target vehicle only.
  Stream<MavMessage> get messages;

  Future<void> send(MavMessage message);
}

/// [VehicleChannel] over a real [Link].
final class LinkChannel implements VehicleChannel {
  LinkChannel(this.link, this.writer, {required this.targetSystem, this.targetComponent = 1});

  final Link link;
  final MavFrameWriter writer;
  @override
  final int targetSystem;
  @override
  final int targetComponent;

  @override
  Stream<MavMessage> get messages => link.frames
      .where((f) => f.systemId == targetSystem && f.componentId == targetComponent)
      .map((f) => f.message)
      .where((m) => m != null)
      .cast<MavMessage>();

  @override
  Future<void> send(MavMessage message) => link.send(writer.encode(message));
}

/// Waits for the first message of type [T] that satisfies [test].
/// Subscribe *before* sending the request that triggers it.
final class Awaiter<T extends MavMessage> {
  Awaiter(Stream<MavMessage> source, [bool Function(T)? test]) {
    _sub = source.listen((m) {
      if (m is T && (test == null || test(m)) && !_c.isCompleted) _c.complete(m);
    });
  }

  final _c = Completer<T>();
  late final StreamSubscription<MavMessage> _sub;

  /// The match, or null after [timeout].
  Future<T?> wait(Duration timeout) async {
    try {
      return await _c.future.timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  Future<void> cancel() => _sub.cancel();
}
