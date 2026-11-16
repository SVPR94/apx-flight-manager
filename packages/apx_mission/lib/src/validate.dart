// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';

import 'compile.dart';
import 'mission.dart';
import 'patterns.dart';
import 'payload.dart';

/// Checks a plan against APX's real behaviour before upload. Errors block
/// the upload; warnings and notes are shown next to the element.
List<Issue> validatePlan(MissionPlan plan, CompiledMission compiled, VehicleFacts facts) {
  final out = <Issue>[...compiled.issues];
  void err(String m, [String? id]) => out.add(Issue(IssueLevel.error, m, elementId: id));
  void warn(String m, [String? id]) => out.add(Issue(IssueLevel.warning, m, elementId: id));
  void note(String m, [String? id]) => out.add(Issue(IssueLevel.info, m, elementId: id));

  final s = plan.settings;
  if (plan.elements.isEmpty) err('The mission is empty. Add a waypoint or a pattern.');
  if (!s.takeoff) warn('No take‑off: this mission can only be started with the vehicle already in the air.');
  if (s.takeoff && (s.takeoffAltitude < 1 || s.takeoffAltitude > 500)) err('Take‑off altitude must be 1–500 m.');
  if (s.speed != null && (s.speed! <= 0 || s.speed! > 20))
    err('Mission speed must be above 0 and at most 20 m/s (APX limit).');

  void checkAlt(double a, String id) {
    if (a <= 0) err('Altitude must be above 0 m (it is relative to home).', id);
    if (a > 120) warn('${a.toStringAsFixed(0)} m is above the usual 120 m legal limit.', id);
  }

  void checkSpeed(double? v, String id) {
    if (v != null && (v <= 0 || v > 20)) err('Speed must be above 0 and at most 20 m/s (APX limit).', id);
  }

  void checkPattern(PatternPayload pp, String id) {
    if (!pp.active) return;
    final p = plan.payload(pp.payloadId);
    if (p == null) return; // reported by the compiler
    _checkPayload(p, facts, id, warn);
  }

  var landedAt = -1;
  for (final (i, e) in plan.elements.indexed) {
    if (landedAt >= 0) {
      warn('Comes after a landing; the vehicle disarms on touchdown, so this never runs.', e.id);
      continue;
    }
    switch (e) {
      case WaypointElement():
        checkAlt(e.altitude, e.id);
        checkSpeed(e.speed, e.id);
        if (e.heading != null) {
          note(
            'Setting a heading stops the vehicle to turn, and APX then keeps that heading for the rest of the mission.',
            e.id,
          );
        }
        for (final a in e.actions) {
          final p = plan.payload(a.payloadId);
          if (p != null) _checkPayload(p, facts, e.id, warn);
        }
      case CommandElement():
        if (e.payload != null) {
          final p = plan.payload(e.payload!.payloadId);
          if (p != null) _checkPayload(p, facts, e.id, warn);
        } else if (e.command == MavCmd.doSetServo) {
          final ch = e.param(1).round();
          if (ch < 9 || ch > 16) err('Outputs 1–8 are motors; use 9–16.', e.id);
          // TODO(APX-FW-10): mission DO_SET_SERVO only drives the sprayer pump/spinner.
          if (!facts.servoWorksInMission(ch)) {
            warn(
              'APX 0.1 ignores servo output $ch inside missions (only the sprayer pump/spinner outputs respond).',
              e.id,
            );
          }
        } else if (e.command == MavCmd.doSprayer && !facts.sprayEnabled) {
          warn('SPRAY_ENABLE is 0 on the vehicle: the sprayer won\'t run.', e.id);
        } else if (e.command == MavCmd.conditionYaw) {
          note('Turning stops the vehicle, and APX keeps this heading for the rest of the mission.', e.id);
        }
      case LandElement():
        landedAt = i;
      case SurveyElement():
        checkAlt(e.altitude, e.id);
        checkSpeed(e.speed, e.id);
        if (e.polygon.length < 3) err('A survey area needs at least 3 corners.', e.id);
        if (selfIntersects(e.polygon)) err('The survey area crosses itself.', e.id);
        if (e.spacing <= 0) err('Pass spacing must be above 0 m.', e.id);
        if (e.spacing > 0 && e.spacing < 1) warn('Passes under 1 m apart make a very long mission.', e.id);
        checkPattern(e.payload, e.id);
      case CorridorElement():
        checkAlt(e.altitude, e.id);
        checkSpeed(e.speed, e.id);
        if (e.path.length < 2) err('A corridor needs at least 2 path points.', e.id);
        if (e.width <= 0 || e.spacing <= 0) err('Corridor width and spacing must be above 0 m.', e.id);
        checkPattern(e.payload, e.id);
      case OrbitElement():
        checkAlt(e.altitude, e.id);
        checkSpeed(e.speed, e.id);
        if (e.radius < 2) err('Orbit radius must be at least 2 m.', e.id);
        if (e.sweepDeg <= 0 || e.sweepDeg > 3600) err('Orbit angle must be 1–3600°.', e.id);
        if (e.resolutionDeg < 1 || e.resolutionDeg > 90) err('Leg angle must be 1–90°.', e.id);
        final heldEachLeg =
            e.heading == OrbitHeading.center ||
            e.heading == OrbitHeading.outward ||
            (e.heading == OrbitHeading.travel && compiled.of(e.id).any((it) => it.command == MavCmd.conditionYaw));
        if (heldEachLeg) {
          // TODO(APX-FW-9): CONDITION_YAW locks heading for the rest of the mission and stops to turn.
          note(
            'APX turns by stopping, so this orbit stops ${e.legs} times to face '
            '${e.heading == OrbitHeading.travel
                ? 'along the next leg (a heading was locked earlier)'
                : e.heading == OrbitHeading.center
                ? 'the centre'
                : 'outward'}. '
            'A larger leg angle means fewer stops.',
            e.id,
          );
        }
        checkPattern(e.payload, e.id);
    }
  }
  if (landedAt >= 0 && s.finish != FinishAction.hover) {
    note('The mission ends with a landing, so the finish action is not used.', plan.elements[landedAt].id);
  }

  final n = compiled.stats.items;
  if (n > 2000) {
    err('$n items: too many for one upload. Split the area or widen the spacing.');
  } else if (n > 700) {
    warn('$n items: large missions are untested on APX hardware.');
  }
  return out;
}

void _checkPayload(Payload p, VehicleFacts facts, String id, void Function(String, [String?]) warn) {
  switch (p.kind) {
    case PayloadKind.sprayer:
      if (!facts.sprayEnabled) warn('SPRAY_ENABLE is 0 on the vehicle: "${p.name}" won\'t run.', id);
    case PayloadKind.spreader:
      break; // always driven through the spinner output, which works
    case PayloadKind.servo:
    case PayloadKind.gimbal:
      // TODO(APX-FW-10): mission DO_SET_SERVO only drives the sprayer pump/spinner.
      if (!facts.servoWorksInMission(p.channel)) {
        warn(
          'APX 0.1 ignores "${p.name}" (output ${p.channel}) inside missions; only the sprayer pump/spinner outputs respond.',
          id,
        );
      }
  }
}
