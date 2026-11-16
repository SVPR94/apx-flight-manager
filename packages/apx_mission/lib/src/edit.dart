// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mavlink/apx_mavlink.dart';

import 'compile.dart';
import 'mission.dart';

/// Makes unique element ids.
final class IdSource {
  IdSource([int? seed]) : _n = seed ?? DateTime.now().microsecondsSinceEpoch;
  int _n;
  String next() => (_n++).toRadixString(36);
}

/// Replaces a pattern (survey, corridor, orbit) with the plain waypoints and
/// commands it compiles to, so every item can be edited on its own. The
/// result compiles to the same items.
List<MissionElement> explodeElement(MissionElement e, CompiledMission compiled, IdSource ids) {
  if (e is! SurveyElement && e is! CorridorElement && e is! OrbitElement) return [e];
  final speed = switch (e) {
    SurveyElement(:final speed) || CorridorElement(:final speed) || OrbitElement(:final speed) => speed,
    _ => null,
  };
  final out = <MissionElement>[];
  for (final it in compiled.of(e.id)) {
    switch (it.command) {
      case MavCmd.navWaypoint:
        out.add(
          WaypointElement(
            id: ids.next(),
            position: it.position!,
            altitude: it.altitude,
            speed: speed,
            acceptRadius: it.p2 > 0 ? it.p2 : null,
          ),
        );
      case MavCmd.doChangeSpeed:
        break; // carried by each waypoint's speed; the compiler re‑adds it
      default:
        out.add(
          CommandElement(
            id: ids.next(),
            command: it.command,
            params: {1: it.p1, 2: it.p2, 3: it.p3, 4: it.p4, if (it.altitude != 0) 7: it.altitude},
          ),
        );
    }
  }
  return out;
}

/// Inserts a waypoint into the leg nearest to [at] (or appends it), using
/// the altitude of the neighbouring waypoint.
List<MissionElement> insertWaypoint(List<MissionElement> elements, GeoPoint at, double altitude, IdSource ids) {
  final wpIdx = [
    for (final (i, e) in elements.indexed)
      if (e is WaypointElement) i,
  ];
  if (wpIdx.length < 2) return [...elements, WaypointElement(id: ids.next(), position: at, altitude: altitude)];
  var best = -1;
  var bestD = double.infinity;
  for (var k = 0; k + 1 < wpIdx.length; k++) {
    final a = (elements[wpIdx[k]] as WaypointElement).position,
        b = (elements[wpIdx[k + 1]] as WaypointElement).position;
    final d = _distanceToSegment(at, a, b);
    if (d < bestD) {
      bestD = d;
      best = k;
    }
  }
  final prev = elements[wpIdx[best]] as WaypointElement;
  return [...elements]..insert(wpIdx[best + 1], WaypointElement(id: ids.next(), position: at, altitude: prev.altitude));
}

double _distanceToSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
  final f = LocalFrame(a);
  final (px, py) = f.toLocal(p);
  final (bx, by) = f.toLocal(b);
  final len2 = bx * bx + by * by;
  final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
  return math.sqrt(math.pow(px - t * bx, 2) + math.pow(py - t * by, 2));
}
