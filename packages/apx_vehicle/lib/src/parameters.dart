// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';

import 'channel.dart';

/// One vehicle parameter. APX encodes values as a float cast
/// (MAV_PROTOCOL_CAPABILITY_PARAM_FLOAT), so integers arrive as whole floats.
final class Parameter {
  Parameter(this.name, this.value, this.type, this.index);

  final String name;
  double value;
  final int type; // MAV_PARAM_TYPE

  /// Index in this session's listing. APX lists from a hash map, so the
  /// order is only stable until the vehicle reboots — key by [name].
  int index;

  bool get isInteger => type != MavParamType.real32 && type != MavParamType.real64;

  String get display => isInteger ? value.round().toString() : _trim(value);

  static String _trim(double v) {
    var s = v.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.endsWith('.') ? '${s}0' : s;
  }
}

enum ParamLoadState { idle, loading, complete, failed }

final class ParamLoadProgress {
  const ParamLoadProgress(this.state, this.received, this.total, [this.message]);
  final ParamLoadState state;
  final int received;
  final int total;
  final String? message;

  double get fraction => total == 0 ? 0 : received / total;
}

enum ParamSetOutcome {
  /// The vehicle echoed the requested value.
  applied,

  /// The vehicle stored a different value (APX clamps to min/max silently).
  clamped,

  /// No echo: unknown name, or the link dropped.
  noReply,
}

final class ParamSetResult {
  const ParamSetResult(this.name, this.outcome, this.requested, [this.stored]);
  final String name;
  final ParamSetOutcome outcome;
  final double requested;
  final double? stored;
}

/// Parameter download, edit and verification.
final class ParameterService {
  ParameterService(
    this._channel, {
    this.listTimeout = const Duration(seconds: 5),
    this.listAttempts = 4,
    this.gapTimeout = const Duration(seconds: 3),
    this.gapAttempts = 5,
    this.setTimeout = const Duration(seconds: 1),
    this.setAttempts = 3,
  }) {
    _sub = _channel.messages.listen(_onMessage);
  }

  final VehicleChannel _channel;
  final Duration listTimeout, gapTimeout, setTimeout;
  final int listAttempts, gapAttempts, setAttempts;

  final _params = <String, Parameter>{};
  final _byIndex = <int, String>{};
  final progress = Signal(const ParamLoadProgress(ParamLoadState.idle, 0, 0));
  final _changes = StreamController<Parameter>.broadcast();
  late final StreamSubscription<MavMessage> _sub;

  int _expected = 0;
  DateTime _lastValueAt = DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, Parameter> get all => Map.unmodifiable(_params);
  Parameter? operator [](String name) => _params[name];
  Set<String> get names => _params.keys.toSet();

  /// Every PARAM_VALUE applied, solicited or not.
  Stream<Parameter> get changes => _changes.stream;

  void _onMessage(MavMessage m) {
    if (m is! ParamValue) return;
    final name = m.paramId;
    final p = _params[name];
    if (p == null) {
      _params[name] = Parameter(name, m.paramValue, m.paramType, m.paramIndex);
    } else {
      p
        ..value = m.paramValue
        ..index = m.paramIndex;
    }
    if (m.paramIndex != 0xFFFF) _byIndex[m.paramIndex] = name;
    if (m.paramCount > 0 && m.paramCount != 0xFFFF) _expected = m.paramCount;
    _lastValueAt = DateTime.now();
    if (progress.value.state == ParamLoadState.loading) {
      progress.value = ParamLoadProgress(ParamLoadState.loading, _byIndex.length, _expected);
    }
    _changes.add(_params[name]!);
  }

  /// Downloads every parameter. Completes when all indices are present.
  Future<ParamLoadProgress> refresh() async {
    _params.clear();
    _byIndex.clear();
    _expected = 0;
    progress.value = const ParamLoadProgress(ParamLoadState.loading, 0, 0);

    // 1. Ask for the list until the first value arrives.
    var started = false;
    for (var i = 0; i < listAttempts && !started; i++) {
      final first = Awaiter<ParamValue>(_channel.messages);
      await _channel.send(
        ParamRequestList(targetSystem: _channel.targetSystem, targetComponent: _channel.targetComponent),
      );
      started = await first.wait(listTimeout) != null;
      await first.cancel();
    }
    if (!started) {
      return progress.value = const ParamLoadProgress(ParamLoadState.failed, 0, 0, 'Vehicle did not send parameters');
    }

    // 2. Let the stream run; when it goes quiet, fill gaps by index.
    final tries = <int, int>{};
    while (true) {
      await _quiet(const Duration(milliseconds: 300));
      if (_expected > 0 && _byIndex.length >= _expected) break;
      if (DateTime.now().difference(_lastValueAt) < gapTimeout && tries.isEmpty) continue;
      final missing = [
        for (var i = 0; i < _expected; i++)
          if (!_byIndex.containsKey(i)) i,
      ];
      final retry = missing.where((i) => (tries[i] ?? 0) < gapAttempts).take(10).toList();
      if (retry.isEmpty) {
        return progress.value = ParamLoadProgress(
          ParamLoadState.failed,
          _byIndex.length,
          _expected,
          '${missing.length} parameters could not be read',
        );
      }
      for (final i in retry) {
        tries[i] = (tries[i] ?? 0) + 1;
        await _channel.send(
          ParamRequestRead(
            targetSystem: _channel.targetSystem,
            targetComponent: _channel.targetComponent,
            paramIndex: i,
          ),
        );
      }
      await Future<void>.delayed(setTimeout);
    }
    return progress.value = ParamLoadProgress(ParamLoadState.complete, _byIndex.length, _expected);
  }

  Future<void> _quiet(Duration d) => Future<void>.delayed(d);

  /// Writes one parameter and confirms it from the vehicle's echo.
  Future<ParamSetResult> set(String name, double value) async {
    final type = _params[name]?.type ?? MavParamType.real32;
    final v = type == MavParamType.real32 ? value : value.roundToDouble();
    for (var i = 0; i < setAttempts; i++) {
      final echo = Awaiter<ParamValue>(_channel.messages, (p) => p.paramId == name);
      await _channel.send(
        ParamSet(
          targetSystem: _channel.targetSystem,
          targetComponent: _channel.targetComponent,
          paramId: name,
          paramValue: v,
          paramType: type,
        ),
      );
      final got = await echo.wait(setTimeout);
      await echo.cancel();
      if (got != null) {
        final same = (got.paramValue - v).abs() <= 1e-6 * (1 + v.abs());
        return ParamSetResult(name, same ? ParamSetOutcome.applied : ParamSetOutcome.clamped, v, got.paramValue);
      }
    }
    return ParamSetResult(name, ParamSetOutcome.noReply, v);
  }

  /// Re‑reads one parameter by name.
  Future<Parameter?> read(String name) async {
    final echo = Awaiter<ParamValue>(_channel.messages, (p) => p.paramId == name);
    await _channel.send(
      ParamRequestRead(
        targetSystem: _channel.targetSystem,
        targetComponent: _channel.targetComponent,
        paramId: name,
        paramIndex: -1,
      ),
    );
    final got = await echo.wait(setTimeout);
    await echo.cancel();
    return got == null ? null : _params[name];
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _changes.close();
    await progress.dispose();
  }
}

/// A named set of parameter values the user wants on the vehicle.
///
/// TODO(APX-FW-3): APX 0.1 forgets parameters on reboot; the session offers
/// to re‑apply a saved profile after reconnecting. Remove the automatic offer
/// once parameters persist.
final class ParameterProfile {
  const ParameterProfile(this.name, this.values);

  final String name;
  final Map<String, double> values;

  /// Parameters whose vehicle value differs from this profile.
  Map<String, (double vehicle, double wanted)> diff(Map<String, Parameter> onVehicle) => {
    for (final MapEntry(:key, :value) in values.entries)
      if (onVehicle[key] case final p? when (p.value - value).abs() > 1e-6 * (1 + value.abs())) key: (p.value, value),
  };

  Future<List<ParamSetResult>> applyTo(ParameterService service) async => [
    for (final MapEntry(:key, :value) in diff(service.all).map((k, v) => MapEntry(k, v.$2)).entries)
      await service.set(key, value),
  ];

  /// Plain `NAME,VALUE` lines (also accepts whitespace or tab separated).
  String toText() => [
    '# APX Flight Manager parameter profile: $name',
    for (final e in (values.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) '${e.key},${e.value}',
  ].join('\n');

  static ParameterProfile parse(String name, String text) {
    final values = <String, double>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'[,\s]+'));
      if (parts.length < 2) continue;
      final v = double.tryParse(parts[1]);
      if (v != null) values[parts[0]] = v;
    }
    return ParameterProfile(name, values);
  }
}
