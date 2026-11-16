// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/src/telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('Telemetry Home Position Updates', () {
    test('home updates on boot on ground, stays fixed in air, and updates upon landing', () {
      final engine = TelemetryStore();
      final now = DateTime.now();

      // 1. Initial GPS lock on ground at takeoff spot A (18.5204, 73.8567)
      engine.apply(
        GlobalPositionInt(
          timeBootMs: 1000,
          lat: 185204000,
          lon: 738567000,
          alt: 540000,
          relativeAlt: 0,
          vx: 0,
          vy: 0,
          vz: 0,
          hdg: 0,
        ),
        now: now,
      );

      expect(engine.snapshot.homeLat, closeTo(18.5204, 1e-5));
      expect(engine.snapshot.homeLon, closeTo(73.8567, 1e-5));

      // 2. Arm vehicle
      engine.apply(
        Heartbeat(
          type: MavType.quadrotor,
          autopilot: MavAutopilot.generic,
          baseMode: 128 | 1, // ARMED + CUSTOM_MODE
          customMode: 0,
          systemStatus: MavState.active,
          mavlinkVersion: 3,
        ),
        now: now.add(const Duration(seconds: 1)),
      );
      expect(engine.snapshot.armed, isTrue);

      // 3. Drone flies to location B (18.5250, 73.8600) at 30m altitude
      engine.apply(
        GlobalPositionInt(
          timeBootMs: 15000,
          lat: 185250000,
          lon: 738600000,
          alt: 570000,
          relativeAlt: 30000,
          vx: 200,
          vy: 100,
          vz: 0,
          hdg: 4500,
        ),
        now: now.add(const Duration(seconds: 15)),
      );

      // While flying, home MUST remain at original spot A for RTL
      expect(engine.snapshot.homeLat, closeTo(18.5204, 1e-5));
      expect(engine.snapshot.homeLon, closeTo(73.8567, 1e-5));

      // 4. Drone lands at spot B and disarms (altRel = 0, armed = false)
      engine.apply(
        GlobalPositionInt(
          timeBootMs: 60000,
          lat: 185250000,
          lon: 738600000,
          alt: 540000,
          relativeAlt: 0,
          vx: 0,
          vy: 0,
          vz: 0,
          hdg: 4500,
        ),
        now: now.add(const Duration(seconds: 60)),
      );
      engine.apply(
        Heartbeat(
          type: MavType.quadrotor,
          autopilot: MavAutopilot.generic,
          baseMode: 1, // DISARMED
          customMode: 0,
          systemStatus: MavState.standby,
          mavlinkVersion: 3,
        ),
        now: now.add(const Duration(seconds: 61)),
      );

      // After landing and disarming, home position MUST update to new landed location B!
      expect(engine.snapshot.armed, isFalse);
      expect(engine.snapshot.homeLat, closeTo(18.5250, 1e-5));
      expect(engine.snapshot.homeLon, closeTo(73.8600, 1e-5));
    });

    test('updates home when HomePosition MAVLink message is received from vehicle', () {
      final engine = TelemetryStore();
      final now = DateTime.now();

      engine.apply(
        HomePosition(
          latitude: 191234567,
          longitude: 729876543,
          altitude: 125000,
          x: 0,
          y: 0,
          z: 0,
          q: [1, 0, 0, 0],
          approachX: 0,
          approachY: 0,
          approachZ: 0,
          timeUsec: 123456789,
        ),
        now: now,
      );

      expect(engine.snapshot.homeLat, closeTo(19.1234567, 1e-6));
      expect(engine.snapshot.homeLon, closeTo(72.9876543, 1e-6));
      expect(engine.snapshot.homeAltMsl, closeTo(125.0, 1e-3));
    });
  });
}
