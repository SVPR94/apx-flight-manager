// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio.dart';
import 'connection.dart';
import 'storage.dart';

/// Available actions when a failsafe condition triggers.
enum FailsafeAction {
  none('Disabled / Alert Only', 'Raises visual and auditory alerts; vehicle maintains current flight mode.'),
  rtl('Return to Launch (RTL)', 'Vehicle climbs to safe RTL altitude and flies directly home.'),
  land('Land Immediately', 'Vehicle descends vertically at controlled landing speed.'),
  brake('Brake & Hold', 'Vehicle halts horizontal flight and holds current 3D position.'),
  terminate('Disarm / Cut Motors', 'Emergency parachute deployment or motor kill for safety.');

  const FailsafeAction(this.label, this.description);
  final String label;
  final String description;
}

/// Failsafe configuration and active safety thresholds.
final class FailsafeSettings {
  const FailsafeSettings({
    this.batteryLowVoltage = 14.8,
    this.batteryLowAction = FailsafeAction.rtl,
    this.batteryCriticalVoltage = 14.0,
    this.batteryCriticalAction = FailsafeAction.land,
    this.gcsLossTimeoutSeconds = 5,
    this.gcsLossAction = FailsafeAction.rtl,
    this.rcLossTimeoutSeconds = 3,
    this.rcLossAction = FailsafeAction.rtl,
    this.geofenceMaxAltitudeMeters = 120.0,
    this.geofenceMaxRadiusMeters = 500.0,
    this.geofenceEnabled = true,
    this.geofenceAction = FailsafeAction.brake,
  });

  final double batteryLowVoltage;
  final FailsafeAction batteryLowAction;
  final double batteryCriticalVoltage;
  final FailsafeAction batteryCriticalAction;
  final int gcsLossTimeoutSeconds;
  final FailsafeAction gcsLossAction;
  final int rcLossTimeoutSeconds;
  final FailsafeAction rcLossAction;
  final double geofenceMaxAltitudeMeters;
  final double geofenceMaxRadiusMeters;
  final bool geofenceEnabled;
  final FailsafeAction geofenceAction;

  FailsafeSettings copyWith({
    double? batteryLowVoltage,
    FailsafeAction? batteryLowAction,
    double? batteryCriticalVoltage,
    FailsafeAction? batteryCriticalAction,
    int? gcsLossTimeoutSeconds,
    FailsafeAction? gcsLossAction,
    int? rcLossTimeoutSeconds,
    FailsafeAction? rcLossAction,
    double? geofenceMaxAltitudeMeters,
    double? geofenceMaxRadiusMeters,
    bool? geofenceEnabled,
    FailsafeAction? geofenceAction,
  }) => FailsafeSettings(
    batteryLowVoltage: batteryLowVoltage ?? this.batteryLowVoltage,
    batteryLowAction: batteryLowAction ?? this.batteryLowAction,
    batteryCriticalVoltage: batteryCriticalVoltage ?? this.batteryCriticalVoltage,
    batteryCriticalAction: batteryCriticalAction ?? this.batteryCriticalAction,
    gcsLossTimeoutSeconds: gcsLossTimeoutSeconds ?? this.gcsLossTimeoutSeconds,
    gcsLossAction: gcsLossAction ?? this.gcsLossAction,
    rcLossTimeoutSeconds: rcLossTimeoutSeconds ?? this.rcLossTimeoutSeconds,
    rcLossAction: rcLossAction ?? this.rcLossAction,
    geofenceMaxAltitudeMeters: geofenceMaxAltitudeMeters ?? this.geofenceMaxAltitudeMeters,
    geofenceMaxRadiusMeters: geofenceMaxRadiusMeters ?? this.geofenceMaxRadiusMeters,
    geofenceEnabled: geofenceEnabled ?? this.geofenceEnabled,
    geofenceAction: geofenceAction ?? this.geofenceAction,
  );

  Map<String, Object?> toJson() => {
    'batteryLowVoltage': batteryLowVoltage,
    'batteryLowAction': batteryLowAction.name,
    'batteryCriticalVoltage': batteryCriticalVoltage,
    'batteryCriticalAction': batteryCriticalAction.name,
    'gcsLossTimeoutSeconds': gcsLossTimeoutSeconds,
    'gcsLossAction': gcsLossAction.name,
    'rcLossTimeoutSeconds': rcLossTimeoutSeconds,
    'rcLossAction': rcLossAction.name,
    'geofenceMaxAltitudeMeters': geofenceMaxAltitudeMeters,
    'geofenceMaxRadiusMeters': geofenceMaxRadiusMeters,
    'geofenceEnabled': geofenceEnabled,
    'geofenceAction': geofenceAction.name,
  };

  factory FailsafeSettings.fromJson(Map<String, Object?> json) => FailsafeSettings(
    batteryLowVoltage: (json['batteryLowVoltage'] as num?)?.toDouble() ?? 14.8,
    batteryLowAction: FailsafeAction.values.byName(json['batteryLowAction'] as String? ?? FailsafeAction.rtl.name),
    batteryCriticalVoltage: (json['batteryCriticalVoltage'] as num?)?.toDouble() ?? 14.0,
    batteryCriticalAction: FailsafeAction.values.byName(
      json['batteryCriticalAction'] as String? ?? FailsafeAction.land.name,
    ),
    gcsLossTimeoutSeconds: (json['gcsLossTimeoutSeconds'] as num?)?.toInt() ?? 5,
    gcsLossAction: FailsafeAction.values.byName(json['gcsLossAction'] as String? ?? FailsafeAction.rtl.name),
    rcLossTimeoutSeconds: (json['rcLossTimeoutSeconds'] as num?)?.toInt() ?? 3,
    rcLossAction: FailsafeAction.values.byName(json['rcLossAction'] as String? ?? FailsafeAction.rtl.name),
    geofenceMaxAltitudeMeters: (json['geofenceMaxAltitudeMeters'] as num?)?.toDouble() ?? 120.0,
    geofenceMaxRadiusMeters: (json['geofenceMaxRadiusMeters'] as num?)?.toDouble() ?? 500.0,
    geofenceEnabled: json['geofenceEnabled'] as bool? ?? true,
    geofenceAction: FailsafeAction.values.byName(json['geofenceAction'] as String? ?? FailsafeAction.brake.name),
  );
}

final class FailsafeController extends Notifier<FailsafeSettings> {
  static const _key = 'failsafe_settings';
  Timer? _monitorTimer;
  bool _lastLowBattTripped = false;
  bool _lastCritBattTripped = false;
  bool _lastGeofenceTripped = false;

  @override
  FailsafeSettings build() {
    final raw = ref.read(settingsStoreProvider).get<Map<String, Object?>>(_key);
    final initial = raw == null
        ? const FailsafeSettings()
        : () {
            try {
              return FailsafeSettings.fromJson(raw);
            } catch (_) {
              return const FailsafeSettings();
            }
          }();

    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    ref.onDispose(() => _monitorTimer?.cancel());

    return initial;
  }

  void update(FailsafeSettings Function(FailsafeSettings current) fn) {
    state = fn(state);
    ref.read(settingsStoreProvider).set(_key, state.toJson());
  }

  /// Write current failsafe thresholds to APX flight controller parameters.
  Future<void> syncToVehicleParams() async {
    final conn = ref.read(connectionProvider);
    if (conn == null || !conn.session.isBound) return;

    final p = conn.session.parameters;
    await p.set('BATT_LOW_VOLT', state.batteryLowVoltage);
    await p.set('BATT_CRT_VOLT', state.batteryCriticalVoltage);

    final gcsVal = switch (state.gcsLossAction) {
      FailsafeAction.none => 0.0,
      FailsafeAction.rtl => 1.0,
      FailsafeAction.land => 2.0,
      _ => 1.0,
    };
    await p.set('FS_GCS_ENABLE', gcsVal);

    final rcVal = switch (state.rcLossAction) {
      FailsafeAction.none => 0.0,
      FailsafeAction.rtl => 1.0,
      FailsafeAction.land => 3.0,
      _ => 1.0,
    };
    await p.set('FS_THR_ENABLE', rcVal);
  }

  void _tick() {
    final conn = ref.read(connectionProvider);
    if (conn == null || !conn.session.isBound) {
      _lastLowBattTripped = false;
      _lastCritBattTripped = false;
      _lastGeofenceTripped = false;
      return;
    }

    final s = conn.session.telemetry.snapshot;
    if (!s.armed) {
      _lastLowBattTripped = false;
      _lastCritBattTripped = false;
      _lastGeofenceTripped = false;
      return;
    }

    final v = s.batteryVoltage;
    if (!v.isNaN && v > 0) {
      if (v <= state.batteryCriticalVoltage) {
        if (!_lastCritBattTripped) {
          _lastCritBattTripped = true;
          _triggerFailsafe('Critical Battery: ${v.toStringAsFixed(1)}V', state.batteryCriticalAction, conn);
        }
      } else if (v <= state.batteryLowVoltage) {
        if (!_lastLowBattTripped) {
          _lastLowBattTripped = true;
          _triggerFailsafe('Low Battery: ${v.toStringAsFixed(1)}V', state.batteryLowAction, conn);
        }
      }
    }

    if (state.geofenceEnabled) {
      final alt = s.altRel;
      if (!alt.isNaN && alt > state.geofenceMaxAltitudeMeters) {
        if (!_lastGeofenceTripped) {
          _lastGeofenceTripped = true;
          _triggerFailsafe('Geofence altitude breach (${alt.toStringAsFixed(0)}m)', state.geofenceAction, conn);
        }
      }
    }
  }

  void _triggerFailsafe(String reason, FailsafeAction action, Connection conn) {
    ref.read(audioAnnouncerProvider).speak('Warning! Failsafe: $reason');

    switch (action) {
      case FailsafeAction.rtl:
        conn.session.commands.setMode(6);
        break;
      case FailsafeAction.land:
        conn.session.commands.land();
        break;
      case FailsafeAction.brake:
        conn.session.commands.setMode(17);
        break;
      case FailsafeAction.terminate:
        conn.session.commands.disarm(force: true);
        break;
      case FailsafeAction.none:
        break;
    }
  }
}

final failsafeProvider = NotifierProvider<FailsafeController, FailsafeSettings>(FailsafeController.new);
