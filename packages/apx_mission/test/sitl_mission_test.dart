// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
@Tags(['sitl'])
library;

import 'dart:async';

import 'package:apx_geo/apx_geo.dart';
import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_mission/apx_mission.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:apx_vehicle/testing.dart';
import 'package:test/test.dart';

/// Stage 7 exit test against the real firmware: plan → compile → upload →
/// read back → fly in AUTO → watch progress, sprayer and heading → RTL.
void main() {
  test(
    'a planned survey with the sprayer and a centre‑facing orbit flies in SITL',
    () async {
      final sitl = await ApxSitl.start();
      final session = VehicleSession(TcpLink('127.0.0.1', port: sitl.tcpPort, label: 'SITL'));
      addTearDown(() async {
        await session.dispose();
        await session.link.dispose();
        await sitl.stop();
      });
      await session.start();
      await _until(() => session.state.value == SessionState.ready, const Duration(seconds: 30));
      final s = session.telemetry.snapshot;
      await _until(() => s.hasPosition, const Duration(seconds: 10));

      final home = GeoPoint(s.lat, s.lon);
      final f = LocalFrame(home);
      GeoPoint at(double e, double n) => f.toGeo(e, n);
      final plan = MissionPlan(
        settings: const MissionSettings(takeoffAltitude: 8, speed: 4),
        elements: [
          SurveyElement(
            id: 'survey',
            polygon: [at(10, 10), at(34, 10), at(34, 26), at(10, 26)],
            altitude: 8,
            spacing: 8,
            angleDeg: 90,
            payload: const PatternPayload(payloadId: 'sprayer'),
          ),
          OrbitElement(
            id: 'orbit',
            center: at(22, 50),
            radius: 8,
            altitude: 8,
            resolutionDeg: 90,
            heading: OrbitHeading.center,
          ),
        ],
      );
      final facts = VehicleFacts.fromParameters({for (final p in session.parameters.all.values) p.name: p.value});
      final compiled = MissionCompiler(facts: facts).compile(plan, home: home);
      expect(validatePlan(plan, compiled, facts).where((i) => i.level == IssueLevel.error), isEmpty);
      final wire = compiled.toWire();

      await session.missions.upload(wire);
      final back = await session.missions.download();
      expect(
        back.map((i) => (i.command, i.x, i.y, i.z, i.param1)),
        wire.map((i) => (i.command, i.x, i.y, i.z, i.param1)),
      );

      // Watch the pump (output 9) and heading while the mission runs.
      var maxPump = 0;
      final headingsAtOrbitWps = <double>[];
      final orbitSeqs = {
        for (final (i, it) in compiled.items.indexed)
          // Orbit legs (each right after its CONDITION_YAW), as vehicle seq.
          if (it.elementId == 'orbit' &&
              it.command == MavCmd.navWaypoint &&
              compiled.items[i - 1].command == MavCmd.conditionYaw)
            i + 1,
      };
      var lastSeq = -1;
      final watch = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (s.servo[8] > maxPump) maxPump = s.servo[8];
        if (s.missionCurrent != lastSeq) {
          // Heading as the vehicle sets off on an orbit leg.
          if (orbitSeqs.contains(s.missionCurrent)) headingsAtOrbitWps.add(s.headingDeg);
          lastSeq = s.missionCurrent;
        }
      });
      addTearDown(watch.cancel);

      expect((await session.commands.setMode(4)).accepted, isTrue); // GUIDED
      expect((await session.commands.arm()).accepted, isTrue);
      expect((await session.commands.startMission()).accepted, isTrue);
      await _until(() => s.customMode == 3, const Duration(seconds: 5));
      // Through the survey and the orbit to the final RTL item.
      await _until(() => s.missionCurrent >= wire.length - 1, const Duration(minutes: 4));
      expect(s.missionTotal, wire.length);
      expect(maxPump, greaterThan(1150), reason: 'sprayer pump ran during the passes');
      // RTL lands and disarms.
      await _until(() => !s.armed, const Duration(minutes: 2));
      expect(haversineMetres(GeoPoint(s.lat, s.lon), home), lessThan(3));
      // Each orbit leg starts after a CONDITION_YAW to face the centre (±10°).
      final yaws = compiled.of('orbit').where((i) => i.command == MavCmd.conditionYaw).map((i) => i.p1).toList();
      expect(headingsAtOrbitWps.length, greaterThanOrEqualTo(3));
      for (var k = 0; k < 3; k++) {
        final err = ((headingsAtOrbitWps[k] - yaws[k] + 540) % 360 - 180).abs();
        expect(err, lessThan(10), reason: 'leg $k heading ${headingsAtOrbitWps[k]} vs ${yaws[k]}');
      }
    },
    skip: ApxSitl.unavailableReason,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _until(bool Function() ok, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
