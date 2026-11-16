// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late AlertsEngine engine;
  late List<Alert> got;
  late VehicleSnapshot s;

  setUp(() {
    now = DateTime(2026, 11, 3, 12);
    engine = AlertsEngine(clock: () => now);
    got = [];
    engine.alerts.listen(got.add);
    s = VehicleSnapshot();
  });

  Future<void> eval({double? low = 10.5, double? crit = 10.0}) async {
    engine.evaluate(s, apx01Profile, lowVolt: low, criticalVolt: crit);
    await Future<void>.delayed(Duration.zero);
  }

  test('arming and mode changes are reported once, as edges', () async {
    await eval();
    s.baseMode = MavModeFlag.safetyArmed;
    s.customMode = 5;
    await eval();
    await eval();
    expect(got.map((a) => a.text), ['Armed', 'Mode Loiter']);
  });

  test('battery thresholds come from the vehicle parameters', () async {
    s.batteryVoltage = 12.4;
    await eval();
    s.batteryVoltage = 10.4;
    await eval();
    s.batteryVoltage = 9.9;
    await eval();
    expect(got.map((a) => a.severity), [AlertSeverity.caution, AlertSeverity.critical]);
    expect(got.last.text, contains('land now'));
  });

  test('GPS fix loss and IMU lane disagreement', () async {
    s.gps[0]
      ..fixType = GpsFixType.v3dFix
      ..updated = now;
    await eval();
    s.gps[0].fixType = GpsFixType.noFix;
    for (final (i, z) in [-9.8, -9.81, -9.79, -7.9].indexed) {
      s.imu[i]
        ..accZ = z
        ..updated = now;
    }
    await eval();
    expect(got.map((a) => a.key), containsAll(['gps.fix', 'imu.spread']));
  });

  test('repeats are suppressed until the repeat interval passes', () async {
    engine.raise('x', AlertSeverity.warning, 'one');
    engine.raise('x', AlertSeverity.warning, 'two');
    now = now.add(const Duration(seconds: 16));
    engine.raise('x', AlertSeverity.warning, 'three');
    await Future<void>.delayed(Duration.zero);
    expect(got.map((a) => a.text), ['one', 'three']);
  });

  test('STATUSTEXT severities map onto alert levels', () async {
    engine.onStatusText(StatusMessage(MavSeverity.critical, 'Crash detected - motors stopped', now));
    engine.onStatusText(StatusMessage(MavSeverity.notice, 'Mission upload complete', now));
    await Future<void>.delayed(Duration.zero);
    expect(got.map((a) => a.severity), [AlertSeverity.critical, AlertSeverity.info]);
  });
}
