// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:math' as math;

import 'package:apx_mavlink/apx_mavlink.dart';

import 'profile.dart';
import 'session.dart';
import 'telemetry.dart';

enum AlertSeverity { info, caution, warning, critical }

final class Alert {
  Alert(this.key, this.severity, this.text, this.time);

  /// Identifies the condition, for repeat suppression (e.g. "battery.low").
  final String key;
  final AlertSeverity severity;
  final String text;
  final DateTime time;

  @override
  String toString() => '[${severity.name}] $text';
}

/// Turns vehicle state into pilot‑facing alerts.
///
/// Thresholds come from the vehicle's own parameters where APX defines them
/// (BATT_LOW_VOLT, BATT_CRT_VOLT). APX 0.1 doesn't act on those itself, so
/// these alerts are the only warning the pilot gets.
final class AlertsEngine {
  AlertsEngine({this.repeatAfter = const Duration(seconds: 15), DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final Duration repeatAfter;
  final DateTime Function() _now;

  final _alerts = StreamController<Alert>.broadcast();
  final history = <Alert>[];
  final _lastRaised = <String, DateTime>{};

  Stream<Alert> get alerts => _alerts.stream;

  // Previous‑sample state for edge detection.
  bool? _armed;
  int? _mode;
  bool _had3d = false;
  int _lastReached = -1;
  String _battLevel = 'ok';

  final _subs = <StreamSubscription<Object?>>[];
  Timer? _poll;

  /// Watches [session] until [dispose].
  void attach(VehicleSession session) {
    _subs
      ..add(
        session.state.changes.listen((s) {
          if (s == SessionState.lost)
            raise('link', AlertSeverity.critical, 'Link lost — no heartbeat from the vehicle');
          if (s == SessionState.ready && _armed != null)
            raise('link', AlertSeverity.info, 'Link restored', force: true);
        }),
      )
      ..add(session.telemetry.statusMessages.listen(onStatusText));
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (session.state.value == SessionState.waiting || !session.isBound) return;
      evaluate(
        session.telemetry.snapshot,
        session.profile,
        lowVolt: session.parameters['BATT_LOW_VOLT']?.value,
        criticalVolt: session.parameters['BATT_CRT_VOLT']?.value,
      );
    });
  }

  void onStatusText(StatusMessage m) {
    final sev = switch (m.severity) {
      <= MavSeverity.critical => AlertSeverity.critical,
      MavSeverity.error => AlertSeverity.warning,
      MavSeverity.warning => AlertSeverity.caution,
      _ => AlertSeverity.info,
    };
    raise('statustext:${m.text}', sev, m.text);
  }

  /// One evaluation pass over the latest snapshot.
  void evaluate(VehicleSnapshot s, FirmwareProfile profile, {double? lowVolt, double? criticalVolt}) {
    if (_armed != null && s.armed != _armed) {
      raise('arm', s.armed ? AlertSeverity.caution : AlertSeverity.info, s.armed ? 'Armed' : 'Disarmed', force: true);
    }
    _armed = s.armed;

    if (_mode != null && s.customMode != _mode) {
      raise('mode', AlertSeverity.info, 'Mode ${profile.modeName(s.customMode)}', force: true);
    }
    _mode = s.customMode;

    final g = s.gps[0];
    if (_had3d && !g.has3dFix && g.updated != null) {
      raise('gps.fix', AlertSeverity.warning, 'GPS fix lost');
    }
    if (g.has3dFix) _had3d = true;

    if (s.lastReached >= 0 && s.lastReached != _lastReached) {
      final last = s.missionTotal > 0 && s.lastReached >= s.missionTotal - 1;
      raise('mission', AlertSeverity.info, last ? 'Mission complete' : 'Item ${s.lastReached} reached', force: true);
      _lastReached = s.lastReached;
    }

    final v = s.batteryVoltage;
    if (!v.isNaN) {
      final level = (criticalVolt != null && v <= criticalVolt)
          ? 'critical'
          : (lowVolt != null && v <= lowVolt)
          ? 'low'
          : 'ok';
      if (level != _battLevel) {
        if (level == 'critical') {
          raise(
            'battery',
            AlertSeverity.critical,
            'Battery critical: ${v.toStringAsFixed(1)} V — land now',
            force: true,
          );
        } else if (level == 'low') {
          raise('battery', AlertSeverity.caution, 'Battery low: ${v.toStringAsFixed(1)} V', force: true);
        }
        _battLevel = level;
      }
    }

    // APX runs up to four redundant IMU lanes; a lane drifting away from the
    // others is worth knowing before the voter has to deal with it.
    final lanes = s.imu.where((l) => l.updated != null).toList();
    if (lanes.length >= 2) {
      final z = lanes.map((l) => l.accZ);
      final spread = z.reduce(math.max) - z.reduce(math.min);
      if (spread > 1.5) {
        raise('imu.spread', AlertSeverity.warning, 'IMU lanes disagree: ${spread.toStringAsFixed(1)} m/s² on Z');
      }
    }
  }

  /// Emits an alert unless the same [key] fired within [repeatAfter].
  void raise(String key, AlertSeverity severity, String text, {bool force = false}) {
    final now = _now();
    final last = _lastRaised[key];
    if (!force && last != null && now.difference(last) < repeatAfter) return;
    _lastRaised[key] = now;
    final a = Alert(key, severity, text, now);
    history.add(a);
    if (history.length > 500) history.removeAt(0);
    _alerts.add(a);
  }

  Future<void> dispose() async {
    _poll?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _alerts.close();
  }
}
