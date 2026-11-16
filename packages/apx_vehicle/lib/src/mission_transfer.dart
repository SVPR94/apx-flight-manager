// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';

import 'channel.dart';

/// One mission item exactly as it goes over the wire.
final class WireMissionItem {
  const WireMissionItem({
    required this.seq,
    required this.command,
    this.frame = MavFrame.globalRelativeAltInt,
    this.param1 = 0,
    this.param2 = 0,
    this.param3 = 0,
    this.param4 = 0,
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.autocontinue = 1,
    this.current = 0,
  });

  factory WireMissionItem.fromMessage(MissionItemInt m) => WireMissionItem(
    seq: m.seq,
    command: m.command,
    frame: m.frame,
    param1: m.param1,
    param2: m.param2,
    param3: m.param3,
    param4: m.param4,
    x: m.x,
    y: m.y,
    z: m.z,
    autocontinue: m.autocontinue,
    current: m.current,
  );

  final int seq, command, frame;
  final double param1, param2, param3, param4;

  /// Latitude/longitude × 1e7.
  final int x, y;
  final double z;
  final int autocontinue, current;

  MissionItemInt toMessage(int targetSystem, int targetComponent, [int missionType = MavMissionType.mission]) => MissionItemInt(
    targetSystem: targetSystem,
    targetComponent: targetComponent,
    seq: seq,
    frame: frame,
    command: command,
    current: current,
    autocontinue: autocontinue,
    param1: param1,
    param2: param2,
    param3: param3,
    param4: param4,
    x: x,
    y: y,
    z: z,
    missionType: missionType,
  );

  @override
  String toString() =>
      '#$seq cmd=$command frame=$frame p=[$param1,$param2,$param3,$param4] '
      '(${x / 1e7}, ${y / 1e7}, $z)';
}

enum TransferState { idle, running, done, failed }

final class TransferProgress {
  const TransferProgress(this.state, this.done, this.total, [this.message]);
  final TransferState state;
  final int done, total;
  final String? message;
}

final class TransferException implements Exception {
  TransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// MAVLink mission protocol. Downloads are mission_type 0 only; [upload]
/// takes a mission_type.
///
/// TODO(APX-FW-1): APX answers fence/rally requests with the mission, and
/// builds without a fence store a fence upload as the mission. Only upload
/// a fence to builds that have one (FENCE_ENABLE, see FenceController).
final class MissionTransfer {
  MissionTransfer(
    this._channel, {
    this.ackTimeout = const Duration(milliseconds: 1500),
    this.itemTimeout = const Duration(milliseconds: 500),
    this.maxRetries = 5,
  });

  final VehicleChannel _channel;
  final Duration ackTimeout, itemTimeout;
  final int maxRetries;
  final progress = Signal(const TransferProgress(TransferState.idle, 0, 0));

  bool _busy = false;

  int get _ts => _channel.targetSystem;
  int get _tc => _channel.targetComponent;

  Future<T> _exclusive<T>(Future<T> Function() body) async {
    if (_busy) throw TransferException('Another mission transfer is running');
    _busy = true;
    try {
      return await body();
    } on TransferException catch (e) {
      progress.value = TransferProgress(TransferState.failed, progress.value.done, progress.value.total, e.message);
      rethrow;
    } finally {
      _busy = false;
    }
  }

  /// Uploads [items] (for regular missions, seq 0 must be the home placeholder for APX).
  Future<void> upload(List<WireMissionItem> items, {int missionType = MavMissionType.mission}) => _exclusive(() async {
    for (var i = 0; i < items.length; i++) {
      if (items[i].seq != i) throw TransferException('Item $i has seq ${items[i].seq}');
    }
    progress.value = TransferProgress(TransferState.running, 0, items.length);
    final queue = _Inbox(
      _channel.messages.where((m) => m is MissionRequestInt || m is MissionRequest || m is MissionAck),
    );
    try {
      await _channel.send(
        MissionCount(targetSystem: _ts, targetComponent: _tc, count: items.length, missionType: missionType),
      );
      var highest = -1;
      var retries = 0;
      while (true) {
        final next = await queue.next(ackTimeout);
        if (next == null) {
          if (++retries > maxRetries) throw TransferException('Vehicle stopped responding during upload');
          // Nothing requested yet: re‑announce. Otherwise resend the last item.
          if (highest < 0) {
            await _channel.send(
              MissionCount(
                targetSystem: _ts,
                targetComponent: _tc,
                count: items.length,
                missionType: missionType,
              ),
            );
          } else {
            await _channel.send(items[highest].toMessage(_ts, _tc, missionType));
          }
          continue;
        }
        retries = 0;
        if (next is MissionAck) {
          if (next.missionType != missionType) continue;
          if (next.type != MavMissionResult.mavMissionAccepted) {
            throw TransferException('Vehicle rejected the mission: ${MavMissionResult.names[next.type] ?? next.type}');
          }
          if (highest < items.length - 1 && items.isNotEmpty) {
            throw TransferException('Vehicle acknowledged before receiving every item');
          }
          progress.value = TransferProgress(TransferState.done, items.length, items.length);
          return;
        }
        final seq = next is MissionRequestInt ? next.seq : (next as MissionRequest).seq;
        if (seq >= items.length) throw TransferException('Vehicle asked for item $seq of ${items.length}');
        await _channel.send(items[seq].toMessage(_ts, _tc, missionType));
        if (seq > highest) highest = seq;
        progress.value = TransferProgress(TransferState.running, highest + 1, items.length);
      }
    } finally {
      await queue.close();
    }
  });

  /// Downloads the vehicle's mission.
  Future<List<WireMissionItem>> download() => _exclusive(() async {
    progress.value = const TransferProgress(TransferState.running, 0, 0);
    MissionCount? count;
    for (var i = 0; i <= maxRetries && count == null; i++) {
      final c = Awaiter<MissionCount>(_channel.messages);
      await _channel.send(
        MissionRequestList(targetSystem: _ts, targetComponent: _tc, missionType: MavMissionType.mission),
      );
      count = await c.wait(ackTimeout);
      await c.cancel();
    }
    if (count == null) throw TransferException('Vehicle did not report its mission');

    final items = <WireMissionItem>[];
    for (var seq = 0; seq < count.count; seq++) {
      MissionItemInt? got;
      for (var i = 0; i <= maxRetries && got == null; i++) {
        final w = Awaiter<MissionItemInt>(_channel.messages, (m) => m.seq == seq);
        await _channel.send(
          MissionRequestInt(targetSystem: _ts, targetComponent: _tc, seq: seq, missionType: MavMissionType.mission),
        );
        got = await w.wait(itemTimeout);
        await w.cancel();
      }
      if (got == null) throw TransferException('Item $seq did not arrive');
      items.add(WireMissionItem.fromMessage(got));
      progress.value = TransferProgress(TransferState.running, seq + 1, count.count);
    }
    await _channel.send(
      MissionAck(
        targetSystem: _ts,
        targetComponent: _tc,
        type: MavMissionResult.mavMissionAccepted,
        missionType: MavMissionType.mission,
      ),
    );
    progress.value = TransferProgress(TransferState.done, items.length, items.length);
    return items;
  });

  /// Removes the vehicle's mission.
  Future<void> clear() => _exclusive(() async {
    for (var i = 0; i <= maxRetries; i++) {
      final ack = Awaiter<MissionAck>(_channel.messages);
      await _channel.send(
        MissionClearAll(targetSystem: _ts, targetComponent: _tc, missionType: MavMissionType.mission),
      );
      final got = await ack.wait(ackTimeout);
      await ack.cancel();
      if (got != null) {
        if (got.type != MavMissionResult.mavMissionAccepted) {
          throw TransferException('Vehicle refused to clear the mission');
        }
        return;
      }
    }
    throw TransferException('Vehicle did not confirm clearing the mission');
  });
}

/// Buffers messages so a timed‑out wait never loses or blocks the next one.
final class _Inbox {
  _Inbox(Stream<MavMessage> source) {
    _sub = source.listen((m) {
      final w = _waiter;
      if (w != null && !w.isCompleted) {
        _waiter = null;
        w.complete(m);
      } else {
        _buffer.add(m);
      }
    });
  }

  final _buffer = <MavMessage>[];
  Completer<MavMessage?>? _waiter;
  late final StreamSubscription<MavMessage> _sub;

  Future<MavMessage?> next(Duration timeout) {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeAt(0));
    final w = _waiter = Completer<MavMessage?>();
    return w.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_waiter, w)) _waiter = null;
        return null;
      },
    );
  }

  Future<void> close() => _sub.cancel();
}
