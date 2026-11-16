// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:typed_data';

import 'package:apx_flight_manager/state/connection.dart';
import 'package:apx_flight_manager/state/trail.dart';
import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _FakeLink extends Link {
  _FakeLink() : super(const LinkDescriptor(LinkKind.tcp, 'Fake', '127.0.0.1'));

  @override
  Future<void> openTransport() async {
    state.value = LinkState.up;
  }

  @override
  Future<void> closeTransport() async {
    state.value = LinkState.closed;
  }

  @override
  Future<void> writeTransport(Uint8List frame) async {}
}

class _TestConnectionController extends ConnectionController {
  _TestConnectionController(this._conn);

  final Connection _conn;

  @override
  Connection? build() => _conn;
}

void main() {
  group('FlightTrailController', () {
    test('records points during flight and clears previous trail on next takeoff', () async {
      final link = _FakeLink();
      final session = VehicleSession(link);
      final alerts = AlertsEngine();
      final connection = Connection(TcpConfig('127.0.0.1', 5760), session, alerts);

      final container = ProviderContainer(
        overrides: [
          connectionProvider.overrideWith(() => _TestConnectionController(connection)),
        ],
      );
      addTearDown(container.dispose);

      // Read trail provider to initialize
      expect(container.read(flightTrailProvider).points, isEmpty);

      // Disarmed on ground: apply position
      session.telemetry.apply(
        GlobalPositionInt(
          timeBootMs: 1000,
          lat: 185204300,
          lon: 738567400,
          alt: 560000,
          relativeAlt: 0,
          vx: 0,
          vy: 0,
          vz: 0,
          hdg: 0,
        ),
      );

      // Wait for sample timer
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(container.read(flightTrailProvider).points, isEmpty);

      // Arm and become airborne
      session.telemetry.apply(
        Heartbeat(
          type: MavType.quadrotor,
          autopilot: MavAutopilot.apxmega,
          baseMode: MavModeFlag.safetyArmed | MavModeFlag.customModeEnabled,
          customMode: 3,
          systemStatus: MavState.active,
          mavlinkVersion: 3,
        ),
      );
      session.telemetry.apply(
        GlobalPositionInt(
          timeBootMs: 2000,
          lat: 185204300,
          lon: 738567400,
          alt: 570000,
          relativeAlt: 10000, // 10m
          vx: 100,
          vy: 0,
          vz: 0,
          hdg: 0,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(container.read(flightTrailProvider).points.length, 1);
      expect(container.read(flightTrailProvider).points.first, const LatLng(18.52043, 73.85674));

      // Fly to second position (>1m away)
      session.telemetry.apply(
        GlobalPositionInt(
          timeBootMs: 3000,
          lat: 185214300,
          lon: 738577400,
          alt: 575000,
          relativeAlt: 15000,
          vx: 200,
          vy: 100,
          vz: 0,
          hdg: 45,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(container.read(flightTrailProvider).points.length, 2);

      // Land and disarm: trail is retained
      session.telemetry.apply(
        GlobalPositionInt(
          timeBootMs: 4000,
          lat: 185214300,
          lon: 738577400,
          alt: 560000,
          relativeAlt: 0,
          vx: 0,
          vy: 0,
          vz: 0,
          hdg: 45,
        ),
      );
      session.telemetry.apply(
        Heartbeat(
          type: MavType.quadrotor,
          autopilot: MavAutopilot.apxmega,
          baseMode: MavModeFlag.customModeEnabled, // disarmed
          customMode: 0,
          systemStatus: MavState.standby,
          mavlinkVersion: 3,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(container.read(flightTrailProvider).points.length, 2);

      // Next flight takeoff: Arming triggers trail reset
      session.telemetry.apply(
        Heartbeat(
          type: MavType.quadrotor,
          autopilot: MavAutopilot.apxmega,
          baseMode: MavModeFlag.safetyArmed | MavModeFlag.customModeEnabled,
          customMode: 3,
          systemStatus: MavState.active,
          mavlinkVersion: 3,
        ),
      );
      session.telemetry.apply(
        GlobalPositionInt(
          timeBootMs: 5000,
          lat: 185220000,
          lon: 738580000,
          alt: 565000,
          relativeAlt: 5000, // 5m
          vx: 50,
          vy: 50,
          vz: 100,
          hdg: 45,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));
      // Old trail has vanished, only new takeoff point is recorded
      expect(container.read(flightTrailProvider).points.length, 1);
      expect(container.read(flightTrailProvider).points.first, const LatLng(18.522, 73.858));
    });
  });
}
