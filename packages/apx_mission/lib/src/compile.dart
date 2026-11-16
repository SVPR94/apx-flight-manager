// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';

import 'mission.dart';
import 'patterns.dart';
import 'payload.dart';

/// Vehicle parameters that change how a mission compiles and how long it
/// takes. Defaults are APX's firmware defaults (used when not connected).
final class VehicleFacts {
  const VehicleFacts({
    this.wpYawBehavior = 2,
    this.sprayEnabled = true,
    this.pumpChannel = 9,
    this.spinnerChannel = 10,
    this.cruiseSpeed = 5,
    this.climbSpeed = 2.5,
    this.descentSpeed = 1.5,
    this.landSpeed = 0.5,
    this.rtlAltitude = 15,
  });

  /// Reads the facts from vehicle parameters (missing ones keep defaults).
  factory VehicleFacts.fromParameters(Map<String, double> p) {
    const d = VehicleFacts();
    return VehicleFacts(
      wpYawBehavior: p['WP_YAW_BEHAVIOR']?.round() ?? d.wpYawBehavior,
      sprayEnabled: (p['SPRAY_ENABLE'] ?? 1) > 0.5,
      pumpChannel: p['SPRAY_PUMP_CH']?.round() ?? d.pumpChannel,
      spinnerChannel: p['SPRAY_SPIN_CH']?.round() ?? d.spinnerChannel,
      cruiseSpeed: (p['WPNAV_SPEED'] ?? 500) / 100,
      climbSpeed: (p['WPNAV_SPEED_UP'] ?? 250) / 100,
      descentSpeed: (p['WPNAV_SPEED_DN'] ?? 150) / 100,
      landSpeed: (p['LAND_SPEED'] ?? 50) / 100,
      rtlAltitude: (p['RTL_ALT'] ?? 1500) / 100,
    );
  }

  final int wpYawBehavior;
  final bool sprayEnabled;
  final int pumpChannel, spinnerChannel;
  final double cruiseSpeed, climbSpeed, descentSpeed, landSpeed, rtlAltitude;

  Object get _key => (
    wpYawBehavior,
    sprayEnabled,
    pumpChannel,
    spinnerChannel,
    cruiseSpeed,
    climbSpeed,
    descentSpeed,
    landSpeed,
    rtlAltitude,
  );

  // Value equality, so a UI that re‑reads parameters often only recompiles
  // the plan when something relevant actually changed.
  @override
  bool operator ==(Object other) => other is VehicleFacts && other._key == _key;

  @override
  int get hashCode => _key.hashCode;

  /// Heading is locked from the start of AUTO (WP_YAW_BEHAVIOR 0 or 4).
  bool get headingLockedAtStart => wpYawBehavior == 0 || wpYawBehavior == 4;

  /// Outputs a DO_SET_SERVO can reach inside an APX mission.
  // TODO(APX-FW-10): mission DO_SET_SERVO only drives the sprayer pump/spinner.
  bool servoWorksInMission(int channel) =>
      channel == 9 || channel == 10 || channel == pumpChannel || channel == spinnerChannel;
}

enum IssueLevel { info, warning, error }

/// Something the planner wants the user to know, tied to an element.
final class Issue {
  const Issue(this.level, this.message, {this.elementId});
  final IssueLevel level;
  final String message;
  final String? elementId;

  @override
  String toString() => '[${level.name}] $message';
}

/// What a compiled item is for (map colouring, statistics).
enum ItemRole { takeoff, transit, pass, runIn, runOut, orbit, yaw, speed, payload, altitude, land, rtl, command }

/// One item the vehicle will run, before sequence numbers are assigned.
final class PlannedItem {
  const PlannedItem(
    this.command, {
    this.p1 = 0,
    this.p2 = 0,
    this.p3 = 0,
    this.p4 = 0,
    this.position,
    this.altitude = 0,
    required this.role,
    this.elementId,
    this.payloadOn = false,
  });

  final int command;
  final double p1, p2, p3, p4;
  final GeoPoint? position;

  /// Metres above home (frame GLOBAL_RELATIVE_ALT).
  final double altitude;
  final ItemRole role;

  /// Element this item came from (null for take‑off/finish).
  final String? elementId;

  /// A payload is working while flying to this item.
  final bool payloadOn;

  bool get isNav =>
      const {MavCmd.navWaypoint, MavCmd.navTakeoff, MavCmd.navLand, MavCmd.navReturnToLaunch}.contains(command);

  WireMissionItem toWire(int seq) => WireMissionItem(
    seq: seq,
    command: command,
    param1: p1,
    param2: p2,
    param3: p3,
    param4: p4,
    x: position == null ? 0 : (position!.lat * 1e7).round(),
    y: position == null ? 0 : (position!.lon * 1e7).round(),
    z: altitude,
  );
}

/// Mission totals for the planner's summary line.
final class MissionStats {
  const MissionStats({
    required this.items,
    required this.distanceM,
    required this.duration,
    required this.workDistanceM,
    required this.areaM2,
    required this.yawStops,
    required this.maxDistanceFromHomeM,
  });

  /// Items on the vehicle (incl. the home placeholder).
  final int items;
  final double distanceM;
  final Duration duration;

  /// Distance flown with a payload working.
  final double workDistanceM;

  /// Surveyed area.
  final double areaM2;
  final int yawStops;
  final double maxDistanceFromHomeM;
}

/// The result of compiling a plan.
final class CompiledMission {
  CompiledMission(this.items, this.issues, this.stats, this.home);

  final List<PlannedItem> items;
  final List<Issue> issues;
  final MissionStats stats;

  /// Planning home (where the mission is assumed to start).
  final GeoPoint? home;

  bool get hasErrors => issues.any((i) => i.level == IssueLevel.error);

  /// Items as uploaded: seq 0 is APX's home placeholder (NAV_WAYPOINT that
  /// the firmware skips, see docs/01 §7), then the plan.
  List<WireMissionItem> toWire() {
    final h = home ?? items.map((i) => i.position).nonNulls.firstOrNull ?? const GeoPoint(0, 0);
    return [
      WireMissionItem(
        seq: 0,
        command: MavCmd.navWaypoint,
        frame: MavFrame.globalInt,
        x: (h.lat * 1e7).round(),
        y: (h.lon * 1e7).round(),
      ),
      for (final (i, it) in items.indexed) it.toWire(i + 1),
    ];
  }

  /// Items belonging to one element.
  Iterable<PlannedItem> of(String elementId) => items.where((i) => i.elementId == elementId);
}

/// Turns a [MissionPlan] into the exact items APX executes.
///
/// Firmware rules applied here (docs/01 §8):
/// * Waypoints only carry the acceptance radius (p2); yaw is a separate,
///   blocking CONDITION_YAW that stops the vehicle and then locks the
///   heading for the rest of the mission.
/// * Payloads switch with instant DO items, which run when the vehicle
///   reaches the previous waypoint.
final class MissionCompiler {
  const MissionCompiler({this.facts = const VehicleFacts()});

  final VehicleFacts facts;

  CompiledMission compile(MissionPlan plan, {GeoPoint? home}) {
    final out = <PlannedItem>[];
    final issues = <Issue>[];
    final s = plan.settings;
    final start = home ?? plan.elements.expand((e) => e.anchors).firstOrNull;
    // Speed for elements that don't set their own; a "Set speed" item changes it.
    var defaultSpeed = s.speed ?? facts.cruiseSpeed;
    var speed = facts.cruiseSpeed;
    // Payloads currently working (for colouring the path and statistics).
    final active = <String>{};
    var yawLocked = facts.headingLockedAtStart;
    var area = 0.0;
    GeoPoint? at = start;

    if (s.takeoff) {
      out.add(PlannedItem(MavCmd.navTakeoff, altitude: s.takeoffAltitude, role: ItemRole.takeoff));
    }
    void setSpeed(double? want, String? id) {
      final target = want ?? defaultSpeed;
      if ((target - speed).abs() > 0.05) {
        out.add(_speed(target, id));
        speed = target;
      }
    }

    if (s.speed != null) setSpeed(s.speed, null);

    void wp(GeoPoint p, double a, ItemRole role, String id, {double? radius}) {
      out.add(
        PlannedItem(
          MavCmd.navWaypoint,
          p2: radius ?? 0,
          position: p,
          altitude: a,
          role: role,
          elementId: id,
          payloadOn: active.isNotEmpty,
        ),
      );
      at = p;
    }

    void yaw(double heading, String id, {double rate = 0}) {
      out.add(
        PlannedItem(MavCmd.conditionYaw, p1: (heading % 360 + 360) % 360, p2: rate, role: ItemRole.yaw, elementId: id),
      );
      yawLocked = true;
    }

    void payload(String? payloadId, bool on, String id, {double? tilt}) {
      if (payloadId == null) return;
      final p = plan.payload(payloadId);
      if (p == null) {
        issues.add(Issue(IssueLevel.error, 'Uses a payload that isn\'t defined ($payloadId).', elementId: id));
        return;
      }
      out.addAll(payloadItems(p, on: on, tiltDeg: tilt, elementId: id));
      // A gimbal moved to an angle isn't "working"; switch payloads are.
      if (p.kind != PayloadKind.gimbal) on ? active.add(p.id) : active.remove(p.id);
    }

    /// A raw sprayer/servo command: infer which payload it switches.
    void rawPayload(int command, double p1, double p2) {
      if (command == MavCmd.doSprayer) {
        final sp = plan.payloads.where((p) => p.kind == PayloadKind.sprayer).firstOrNull;
        final key = sp?.id ?? 'sprayer';
        p1 > 0.5 ? active.add(key) : active.remove(key);
        return;
      }
      final ch = p1.round();
      for (final p in plan.payloads.where((p) => p.kind == PayloadKind.servo || p.kind == PayloadKind.spreader)) {
        final pc = p.kind == PayloadKind.spreader ? facts.spinnerChannel : p.channel;
        if (pc != ch) continue;
        (p2.round() - p.onPwm).abs() < (p2.round() - p.offPwm).abs() ? active.add(p.id) : active.remove(p.id);
      }
    }

    for (final e in plan.elements) {
      switch (e) {
        case WaypointElement():
          setSpeed(e.speed, e.id);
          if (e.heading != null) yaw(e.heading!, e.id);
          wp(e.position, e.altitude, ItemRole.transit, e.id, radius: e.acceptRadius);
          for (final a in e.actions) {
            payload(a.payloadId, a.on, e.id, tilt: a.tiltDeg);
          }
        case CommandElement():
          if (e.payload != null) {
            payload(e.payload!.payloadId, e.payload!.on, e.id, tilt: e.payload!.tiltDeg);
            break;
          }
          final spec = e.spec;
          if (spec == null) {
            issues.add(Issue(IssueLevel.error, 'APX doesn\'t execute command ${e.command}.', elementId: e.id));
            break;
          }
          if (e.command == MavCmd.conditionYaw) yawLocked = true;
          if (e.command == MavCmd.doChangeSpeed && e.param(1).round() <= 1) {
            speed = defaultSpeed = e.param(2) < 0 ? facts.cruiseSpeed : e.param(2);
          }
          if (e.command == MavCmd.doSprayer || e.command == MavCmd.doSetServo)
            rawPayload(e.command, e.param(1), e.param(2));
          out.add(
            PlannedItem(
              e.command,
              p1: e.param(1),
              p2: e.param(2),
              p3: e.param(3),
              p4: e.param(4),
              altitude: e.params.containsKey(7) ? e.param(7) : 0,
              role: switch (e.command) {
                MavCmd.conditionYaw => ItemRole.yaw,
                MavCmd.doChangeSpeed => ItemRole.speed,
                MavCmd.conditionChangeAlt || MavCmd.doChangeAltitude => ItemRole.altitude,
                MavCmd.doSprayer || MavCmd.doSetServo => ItemRole.payload,
                _ => ItemRole.command,
              },
              elementId: e.id,
            ),
          );
        case LandElement():
          out.add(PlannedItem(MavCmd.navLand, position: e.position, role: ItemRole.land, elementId: e.id));
          if (e.position != null) at = e.position;
        case SurveyElement():
          final lines = surveyLineCount(e.polygon, spacing: e.spacing, angleDeg: e.angleDeg);
          if (lines > maxSurveyLines) {
            issues.add(
              Issue(
                IssueLevel.error,
                'The area needs $lines passes at ${e.spacing} m spacing (limit $maxSurveyLines). Draw a smaller area or widen the spacing.',
                elementId: e.id,
              ),
            );
            break;
          }
          area += polygonArea(e.polygon);
          final passes = surveyPasses(
            e.polygon,
            spacing: e.spacing,
            angleDeg: e.angleDeg,
            overshoot: e.overshoot,
            reverse: e.reverse,
          );
          if (passes.isEmpty) {
            issues.add(
              Issue(IssueLevel.error, 'The survey produces no passes. Check the polygon and spacing.', elementId: e.id),
            );
            break;
          }
          setSpeed(e.speed, e.id);
          _passes(
            passes: [
              for (final p in passes) (p.entry, [p.start, p.end], p.exit),
            ],
            altitude: e.altitude,
            radius: e.acceptRadius,
            pp: e.payload,
            id: e.id,
            wp: wp,
            payload: payload,
          );
        case CorridorElement():
          final lanes = corridorLanes(e.path, width: e.width, spacing: e.spacing, overshoot: e.overshoot);
          if (lanes.isEmpty) {
            issues.add(Issue(IssueLevel.error, 'A corridor needs a path of at least two points.', elementId: e.id));
            break;
          }
          setSpeed(e.speed, e.id);
          _passes(
            passes: [for (final l in lanes) (l.entry, l.points, l.exit)],
            altitude: e.altitude,
            radius: e.acceptRadius,
            pp: e.payload,
            id: e.id,
            wp: wp,
            payload: payload,
          );
        case OrbitElement():
          final pts = orbitPoints(
            e.center,
            radius: e.radius,
            startBearing: e.startBearing,
            sweepDeg: e.sweepDeg,
            clockwise: e.clockwise,
            resolutionDeg: e.resolutionDeg,
          );
          setSpeed(e.speed, e.id);
          wp(pts.first, e.altitude, ItemRole.transit, e.id, radius: e.acceptRadius);
          final tilt = e.payload.gimbalTiltDeg;
          payload(e.payload.payloadId, true, e.id, tilt: tilt);
          if (e.heading == OrbitHeading.fixed) yaw(e.fixedHeading, e.id, rate: e.yawRate);
          final step = e.sweepDeg / (pts.length - 1) * (e.clockwise ? 1 : -1);
          for (var k = 1; k < pts.length; k++) {
            // Mid‑leg bearing from the centre: the heading error is split
            // evenly across the straight leg.
            final mid = e.startBearing + (k - 0.5) * step;
            switch (e.heading) {
              case OrbitHeading.center:
                yaw(mid + 180, e.id, rate: e.yawRate);
              case OrbitHeading.outward:
                yaw(mid, e.id, rate: e.yawRate);
              case OrbitHeading.travel:
                // The firmware faces the next waypoint by itself, unless a
                // heading lock is in force (then emulate it leg by leg).
                if (yawLocked) yaw(bearingDeg(pts[k - 1], pts[k]), e.id, rate: e.yawRate);
              case OrbitHeading.fixed:
                break;
            }
            wp(pts[k], e.altitude, ItemRole.orbit, e.id, radius: e.acceptRadius);
          }
          payload(e.payload.payloadId, false, e.id, tilt: 0);
      }
    }

    switch (s.finish) {
      case FinishAction.rtl:
        out.add(const PlannedItem(MavCmd.navReturnToLaunch, role: ItemRole.rtl));
      case FinishAction.landHere:
        if (at != null && out.isNotEmpty && out.last.command != MavCmd.navLand) {
          out.add(PlannedItem(MavCmd.navLand, position: at, role: ItemRole.land));
        }
      case FinishAction.hover:
        break;
    }

    return CompiledMission(out, issues, _stats(out, start, area), start);
  }

  /// Payload passes (survey lines or corridor lanes): run‑in, on, work
  /// points, off, run‑out. With [PatternPayload.onlyOnLines] false the
  /// payload stays on from the first pass to the last.
  void _passes({
    required List<(GeoPoint, List<GeoPoint>, GeoPoint)> passes,
    required double altitude,
    required double? radius,
    required PatternPayload pp,
    required String id,
    required void Function(GeoPoint, double, ItemRole, String, {double? radius}) wp,
    required void Function(String?, bool, String, {double? tilt}) payload,
  }) {
    final perPass = pp.onlyOnLines;
    final last = passes.length - 1;
    for (final (i, (entry, work, exit)) in passes.indexed) {
      if (entry != work.first) wp(entry, altitude, i == 0 ? ItemRole.transit : ItemRole.runIn, id, radius: radius);
      wp(work.first, altitude, i == 0 && entry == work.first ? ItemRole.transit : ItemRole.runIn, id, radius: radius);
      if (perPass || i == 0) payload(pp.payloadId, true, id, tilt: pp.gimbalTiltDeg);
      for (final p in work.skip(1)) {
        wp(p, altitude, ItemRole.pass, id, radius: radius);
      }
      if (perPass || i == last) payload(pp.payloadId, false, id, tilt: 0);
      if (exit != work.last) wp(exit, altitude, ItemRole.runOut, id, radius: radius);
    }
  }

  PlannedItem _speed(double v, String? id) =>
      PlannedItem(MavCmd.doChangeSpeed, p1: 1, p2: v, role: ItemRole.speed, elementId: id);

  /// The DO items that put [p] in the requested state.
  List<PlannedItem> payloadItems(Payload p, {required bool on, double? tiltDeg, String? elementId}) {
    switch (p.kind) {
      case PayloadKind.sprayer:
        return [PlannedItem(MavCmd.doSprayer, p1: on ? 1 : 0, role: ItemRole.payload, elementId: elementId)];
      case PayloadKind.spreader:
      case PayloadKind.servo:
        final ch = p.kind == PayloadKind.spreader ? facts.spinnerChannel : p.channel;
        return [
          PlannedItem(
            MavCmd.doSetServo,
            p1: ch.toDouble(),
            p2: (on ? p.onPwm : p.offPwm).toDouble(),
            role: ItemRole.payload,
            elementId: elementId,
          ),
        ];
      case PayloadKind.gimbal:
        return [
          PlannedItem(
            MavCmd.doSetServo,
            p1: p.channel.toDouble(),
            p2: p.gimbalPwm(tiltDeg ?? (on ? -90 : 0)).toDouble(),
            role: ItemRole.payload,
            elementId: elementId,
          ),
        ];
    }
  }

  MissionStats _stats(List<PlannedItem> items, GeoPoint? home, double area) {
    var dist = 0.0, work = 0.0, seconds = 0.0, maxFromHome = 0.0, yaws = 0;
    var speed = facts.cruiseSpeed;
    GeoPoint? at = home;
    var alt = 0.0, heading = 0.0;
    void climb(double to) {
      final dz = to - alt;
      seconds += dz > 0 ? dz / facts.climbSpeed : -dz / facts.descentSpeed;
      dist += dz.abs();
      alt = to;
    }

    for (final it in items) {
      switch (it.command) {
        case MavCmd.navTakeoff:
          climb(it.altitude);
        case MavCmd.navWaypoint:
          if (at != null) {
            final d = haversineMetres(at, it.position!);
            dist += d;
            if (it.payloadOn) work += d;
            seconds += d / math.max(speed, 0.5);
            if (d > 1) heading = bearingDeg(at, it.position!);
          }
          climb(it.altitude);
          at = it.position;
        case MavCmd.conditionYaw:
          yaws++;
          final turn = ((it.p1 - heading + 540) % 360 - 180).abs();
          seconds += turn / (it.p2 > 0 ? it.p2 : 30) + 2; // + settle (gyro quiet, ±3°)
          heading = it.p1;
        case MavCmd.doChangeSpeed when it.p1.round() <= 1:
          speed = it.p2 < 0 ? facts.cruiseSpeed : it.p2;
        case MavCmd.conditionChangeAlt:
          climb(it.altitude);
        case MavCmd.navLand:
          if (at != null && it.position != null) {
            final d = haversineMetres(at, it.position!);
            dist += d;
            seconds += d / math.max(speed, 0.5);
            at = it.position;
          }
          seconds += alt / math.max(facts.landSpeed, 0.2);
          dist += alt;
          alt = 0;
        case MavCmd.navReturnToLaunch:
          if (alt < facts.rtlAltitude) climb(facts.rtlAltitude);
          if (at != null && home != null) {
            final d = haversineMetres(at, home);
            dist += d;
            seconds += d / math.max(speed, 0.5);
            at = home;
          }
          seconds += alt / math.max(facts.landSpeed, 0.2);
          dist += alt;
          alt = 0;
      }
      if (home != null && at != null) maxFromHome = math.max(maxFromHome, haversineMetres(home, at));
    }
    return MissionStats(
      items: items.length + 1,
      distanceM: dist,
      duration: Duration(seconds: seconds.round()),
      workDistanceM: work,
      areaM2: area,
      yawStops: yaws,
      maxDistanceFromHomeM: maxFromHome,
    );
  }
}
