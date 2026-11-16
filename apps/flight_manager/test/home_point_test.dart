// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Home Point Telemetry & Estimation', () {
    test('captures home position automatically on solid GPS fix on ground', () {
      final dec = TelemetryStore();
      expect(dec.snapshot.homeLat.isNaN, isTrue);
      expect(dec.snapshot.homeLon.isNaN, isTrue);

      // Vehicle receives GPS lock (3D Fix) while on the ground (disarmed)
      dec.apply(
        GpsRawInt(
          timeUsec: 1000000,
          fixType: 3,
          lat: 185204300, // 18.52043 deg
          lon: 738567400, // 73.85674 deg
          alt: 560000, // 560 m MSL
          eph: 100,
          epv: 100,
          vel: 0,
          cog: 0,
          satellitesVisible: 14,
        ),
      );

      // Home should be automatically captured from solid GPS fix on ground
      expect(dec.snapshot.homeLat, closeTo(18.52043, 1e-4));
      expect(dec.snapshot.homeLon, closeTo(73.85674, 1e-4));
      expect(dec.snapshot.homeAltMsl, closeTo(560.0, 1e-1));
    });

    test('captures home position on arming transition', () {
      final dec = TelemetryStore();
      dec.apply(
        GlobalPositionInt(
          timeBootMs: 2000,
          lat: 191234560,
          lon: 729876540,
          alt: 120000,
          relativeAlt: 0,
          vx: 0,
          vy: 0,
          vz: 0,
          hdg: 0,
        ),
      );

      // Heartbeat indicates transition to armed
      dec.apply(
        Heartbeat(
          type: MavType.quadrotor,
          autopilot: MavAutopilot.apxmega,
          baseMode: MavModeFlag.safetyArmed | MavModeFlag.customModeEnabled,
          customMode: 3,
          systemStatus: MavState.active,
          mavlinkVersion: 3,
        ),
      );

      expect(dec.snapshot.armed, isTrue);
      expect(dec.snapshot.homeLat, closeTo(19.123456, 1e-5));
      expect(dec.snapshot.homeLon, closeTo(72.987654, 1e-5));
      expect(dec.snapshot.homeAltMsl, closeTo(120.0, 1e-1));
    });

    test('manual in-flight home update sets telemetry home position', () {
      final dec = TelemetryStore();
      dec.setManualHome(lat: 20.5937, lon: 78.9629, altMsl: 310.5);

      expect(dec.snapshot.homeLat, closeTo(20.5937, 1e-4));
      expect(dec.snapshot.homeLon, closeTo(78.9629, 1e-4));
      expect(dec.snapshot.homeAltMsl, closeTo(310.5, 1e-2));
    });
  });

  group('CommandService Home & Motor Test', () {
    test('profile supports MavCmd.doSetHome and MavCmd.doMotorTest', () {
      expect(apx01Profile.supportsCommand(MavCmd.doSetHome), isTrue);
      expect(apx01Profile.supportsCommand(MavCmd.doMotorTest), isTrue);
      expect(apx01Profile.motorTest, isTrue);
    });
  });
}
