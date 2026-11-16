// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';

/// A scripted vehicle that behaves like APX 0.1 at the protocol level,
/// with switches to drop replies so retry paths get exercised.
final class FakeApx implements VehicleChannel {
  FakeApx({Map<String, (double, int, double, double)>? params}) : params = params ?? _defaultParams();

  @override
  int get targetSystem => 1;
  @override
  int get targetComponent => 1;

  /// name → (value, MAV_PARAM_TYPE, min, max)
  final Map<String, (double, int, double, double)> params;
  final mission = <WireMissionItem>[];

  /// Indices left out of the first PARAM_REQUEST_LIST burst.
  Set<int> dropOnList = {};

  /// Sequence numbers whose first MISSION_REQUEST_INT (upload) is lost.
  Set<int> dropUploadRequest = {};

  /// Sequence numbers whose first MISSION_ITEM_INT reply (download) is lost.
  Set<int> dropDownloadItem = {};

  /// COMMAND_ACKs to swallow before answering.
  int dropAcks = 0;

  final sent = <MavMessage>[]; // what the GCS sent us
  final _out = StreamController<MavMessage>.broadcast();
  List<WireMissionItem> _upload = [];
  int _expected = 0;

  @override
  Stream<MavMessage> get messages => _out.stream;

  List<String> get _names => params.keys.toList();

  void _emit(MavMessage m) => scheduleMicrotask(() => _out.add(m));

  ParamValue _value(String name) {
    final (v, t, _, _) = params[name]!;
    return ParamValue(
      paramId: name,
      paramValue: v,
      paramType: t,
      paramCount: params.length,
      paramIndex: _names.indexOf(name),
    );
  }

  @override
  Future<void> send(MavMessage m) async {
    sent.add(m);
    switch (m) {
      case ParamRequestList():
        for (final n in _names) {
          if (!dropOnList.contains(_names.indexOf(n))) _emit(_value(n));
        }
        dropOnList = {};
      case ParamRequestRead(:final paramIndex, :final paramId):
        final name = paramIndex >= 0 ? (paramIndex < params.length ? _names[paramIndex] : null) : paramId;
        if (name != null && params.containsKey(name)) _emit(_value(name));
      case ParamSet(:final paramId, :final paramValue):
        final p = params[paramId];
        if (p == null) return; // APX: silence
        params[paramId] = (paramValue.clamp(p.$3, p.$4).toDouble(), p.$2, p.$3, p.$4);
        _emit(_value(paramId));
      case MissionCount(:final count):
        _upload = [];
        _expected = count;
        _request(0);
      case MissionItemInt():
        // APX: an out‑of‑order item makes it re‑request the one it needs.
        if (m.seq != _upload.length) {
          _request(_upload.length);
          return;
        }
        _upload.add(WireMissionItem.fromMessage(m));
        if (_upload.length < _expected) {
          _request(_upload.length);
        } else {
          mission
            ..clear()
            ..addAll(_upload);
          _emit(const MissionAck(targetSystem: 255, targetComponent: 190));
        }
      case MissionRequestList():
        _emit(MissionCount(targetSystem: 255, targetComponent: 190, count: mission.length));
      case MissionRequestInt(:final seq):
        if (dropDownloadItem.remove(seq)) return;
        if (seq < mission.length) _emit(mission[seq].toMessage(255, 190));
      case MissionClearAll():
        mission.clear();
        _emit(const MissionAck(targetSystem: 255, targetComponent: 190));
      case CommandLong(:final command) || CommandInt(:final command):
        if (dropAcks > 0) {
          dropAcks--;
          return;
        }
        _emit(CommandAck(command: command, result: MavResult.accepted));
      default:
        break;
    }
  }

  void _request(int seq) {
    if (dropUploadRequest.remove(seq)) return;
    _emit(MissionRequestInt(targetSystem: 255, targetComponent: 190, seq: seq));
  }

  static Map<String, (double, int, double, double)> _defaultParams() => {
    for (var i = 0; i < 40; i++) 'TEST_P$i': (i.toDouble(), MavParamType.int32, 0, 1000),
    'WPNAV_SPEED': (500, MavParamType.real32, 20, 2000),
    'WPNAV_BLEND': (1, MavParamType.int32, 0, 1),
    'SPRAY_PUMP_RATE': (10, MavParamType.real32, 0, 100),
  };
}
