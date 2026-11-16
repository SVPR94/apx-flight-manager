// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
@Tags(['sitl'])
library;

import 'dart:async';

import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:test/test.dart';

import 'package:apx_vehicle/testing.dart';

/// End‑to‑end against the real APX firmware (SITL). Run with:
///   dart test -t sitl
void main() {
  late ApxSitl sitl;
  late VehicleSession session;

  setUpAll(() async {
    sitl = await ApxSitl.start();
    session = VehicleSession(TcpLink('127.0.0.1', port: sitl.tcpPort, label: 'SITL'));
    await session.start();
    await _until(() => session.state.value == SessionState.ready, const Duration(seconds: 30));
  });

  tearDownAll(() async {
    await session.dispose();
    await session.link.dispose();
    await sitl.stop();
  });

  test('connects, identifies APX 0.1 and reads every parameter', () {
    expect(session.profile, same(apx01Profile));
    expect(session.version.toString(), '0.1.0');
    expect(session.parameters.progress.value.state, ParamLoadState.complete);
    expect(session.parameters.all.length, 158);
    expect(session.telemetry.snapshot.vehicleType, MavType.quadrotor);
    expect(session.link.parser.stats.crcErrors, 0);
  }, skip: ApxSitl.unavailableReason);

  test('generated parameter metadata matches what the firmware reports', () {
    final onVehicle = session.parameters.all;
    expect(onVehicle.keys.toSet(), ParamMeta.all.keys.toSet());
    for (final p in onVehicle.values) {
      final m = ParamMeta.of(p.name)!;
      expect(p.isInteger, m.isInteger, reason: '${p.name} type');
      expect(p.value, inInclusiveRange(m.min, m.max), reason: '${p.name} in range');
    }
  }, skip: ApxSitl.unavailableReason);

  test('telemetry streams at APX rates and home is estimated', () async {
    final before = session.link.stats.framesIn;
    await Future<void>.delayed(const Duration(seconds: 2));
    final perSecond = (session.link.stats.framesIn - before) / 2;
    expect(perSecond, greaterThan(100)); // ~140 msg/s measured
    final s = session.telemetry.snapshot;
    expect(s.gps[0].has3dFix, isTrue);
    expect(s.imu.where((l) => l.updated != null), hasLength(4)); // 4 redundant lanes
    expect(s.homeLat, closeTo(18.5204, 1e-3));
    expect(s.homeAltMsl, closeTo(540, 2));
  }, skip: ApxSitl.unavailableReason);

  test('parameter writes are confirmed and APX clamping is detected', () async {
    final p = session.parameters;
    final applied = await p.set('WPNAV_SPEED', 600);
    expect(applied.outcome, ParamSetOutcome.applied);
    final clamped = await p.set('WPNAV_SPEED', 99999);
    expect(clamped.outcome, ParamSetOutcome.clamped);
    expect(clamped.stored, 2000);
    expect((await p.set('NOT_A_PARAM', 1)).outcome, ParamSetOutcome.noReply);
    await p.set('WPNAV_SPEED', 500);
  }, skip: ApxSitl.unavailableReason);

  test('unsupported commands are refused locally, supported ones answered', () async {
    expect((await session.commands.long(MavCmd.preflightCalibration, p1: 1)).result, MavResult.unsupported);
    expect((await session.commands.setMode(5)).accepted, isTrue); // LOITER
    await _until(() => session.telemetry.snapshot.customMode == 5, const Duration(seconds: 3));
    expect((await session.commands.setMode(0)).accepted, isTrue);
  }, skip: ApxSitl.unavailableReason);

  test('setHome updates onboard home position and reflects in telemetry', () async {
    final s = session.telemetry.snapshot;
    const newHomeLat = 18.5280;
    const newHomeLon = 73.8620;
    const newHomeAlt = 545.0;

    final res = await session.commands.setHome(
      useCurrentPosition: false,
      lat: newHomeLat,
      lon: newHomeLon,
      altMsl: newHomeAlt,
    );
    expect(res.accepted, isTrue);

    await _until(() => (s.homeLat - newHomeLat).abs() < 1e-4, const Duration(seconds: 3));
    expect(s.homeLat, closeTo(newHomeLat, 1e-4));
    expect(s.homeLon, closeTo(newHomeLon, 1e-4));

    final resCurr = await session.commands.setHome(useCurrentPosition: true);
    expect(resCurr.accepted, isTrue);
    await _until(() => (s.homeLat - s.lat).abs() < 1e-4, const Duration(seconds: 3));
    expect(s.homeLat, closeTo(s.lat, 1e-4));
    expect(s.homeLon, closeTo(s.lon, 1e-4));
  }, skip: ApxSitl.unavailableReason);

  test(
    'mission round trip, then flies it and reports progress',
    () async {
      final s = session.telemetry.snapshot;
      final lat = (s.lat * 1e7).round(), lon = (s.lon * 1e7).round();
      final plan = [
        WireMissionItem(seq: 0, command: MavCmd.navWaypoint, frame: MavFrame.globalInt, x: lat, y: lon),
        const WireMissionItem(seq: 1, command: MavCmd.navTakeoff, z: 8),
        WireMissionItem(seq: 2, command: MavCmd.navWaypoint, x: lat + 1500, y: lon, z: 8),
        WireMissionItem(seq: 3, command: MavCmd.navWaypoint, x: lat + 1500, y: lon + 1500, z: 8),
        const WireMissionItem(seq: 4, command: MavCmd.navReturnToLaunch),
      ];
      await session.missions.upload(plan);
      final back = await session.missions.download();
      expect(back.map((i) => (i.command, i.x, i.y, i.z)), plan.map((i) => (i.command, i.x, i.y, i.z)));

      expect((await session.commands.setMode(4)).accepted, isTrue); // GUIDED
      expect((await session.commands.arm()).accepted, isTrue);
      expect((await session.commands.startMission()).accepted, isTrue);
      await _until(() => s.customMode == 3, const Duration(seconds: 3));
      await _until(() => s.lastReached >= 2, const Duration(seconds: 40));
      expect(s.missionTotal, plan.length);
      expect(s.altRel, greaterThan(5));

      expect((await session.commands.setMode(9)).accepted, isTrue); // LAND
      await _until(() => !s.armed, const Duration(seconds: 60));
    },
    skip: ApxSitl.unavailableReason,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _until(bool Function() ok, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
