// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mavlink/apx_mavlink.dart';

import 'compile.dart';

/// Builds a mission that continues [mission] from item [fromSeq] (vehicle
/// sequence number, 1‑based as reported by MISSION_CURRENT), e.g. after
/// landing to refill the tank.
///
/// APX can't start AUTO mid‑mission (it always restarts at item 0 and
/// DO_SET_MISSION_CURRENT is unsupported), so the GCS uploads a new mission:
/// take‑off (if [onGround]), the speed, heading lock and payload states that
/// were in force at that point, a waypoint at the start of the interrupted
/// leg, then the rest of the original items.
// TODO(APX-FW-11): replace with DO_SET_MISSION_CURRENT once APX supports it.
CompiledMission resumeFrom(
  CompiledMission mission,
  int fromSeq, {
  required bool onGround,
  double takeoffAltitude = 10,
}) {
  final idx = (fromSeq - 1).clamp(0, mission.items.length);
  final before = mission.items.take(idx).toList();
  final rest = mission.items.skip(idx).toList();

  PlannedItem? lastNav, lastSpeed, lastYaw;
  final payload = <String, PlannedItem>{}; // last state per sprayer / servo output
  var altitude = takeoffAltitude;
  for (final it in before) {
    switch (it.command) {
      case MavCmd.navWaypoint:
        lastNav = it;
        altitude = it.altitude;
      case MavCmd.navTakeoff:
        altitude = it.altitude;
      case MavCmd.doChangeSpeed:
        lastSpeed = it;
      case MavCmd.conditionYaw:
        lastYaw = it;
      case MavCmd.doSprayer:
        payload['sprayer'] = it;
      case MavCmd.doSetServo:
        payload['servo${it.p1.round()}'] = it;
    }
  }
  // Resume where the interrupted leg started; payloads switch back on there.
  final out = <PlannedItem>[
    if (onGround) PlannedItem(MavCmd.navTakeoff, altitude: altitude, role: ItemRole.takeoff),
    ?lastSpeed,
    ?lastYaw,
    if (lastNav != null)
      PlannedItem(MavCmd.navWaypoint, position: lastNav.position, altitude: lastNav.altitude, role: ItemRole.transit),
    ...payload.values,
    ...rest,
  ];
  final home = mission.home ?? out.map((i) => i.position).nonNulls.firstOrNull ?? const GeoPoint(0, 0);
  return CompiledMission(out, const [], mission.stats, home);
}
