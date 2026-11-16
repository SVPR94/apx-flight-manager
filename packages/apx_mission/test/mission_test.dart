// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_mission/apx_mission.dart';
import 'package:test/test.dart';

const origin = GeoPoint(18.52, 73.85);
final frame = LocalFrame(origin);
GeoPoint at(double east, double north) => frame.toGeo(east, north);

/// A 100 m (east) × 60 m (north) field.
final field = [at(0, 0), at(100, 0), at(100, 60), at(0, 60)];

const sprayer = Payload.defaultSprayer;
const seeder = Payload(id: 'seed', name: 'Seeder', kind: PayloadKind.spreader, onPwm: 1800, offPwm: 1000);
const drop = Payload(id: 'drop', name: 'Drop', kind: PayloadKind.servo, channel: 11);
const gimbal = Payload(
  id: 'gim',
  name: 'Gimbal',
  kind: PayloadKind.gimbal,
  channel: 12,
  pwmAtLevel: 1500,
  pwmAtDown: 1000,
);

MissionPlan plan(List<MissionElement> e, {MissionSettings settings = const MissionSettings()}) =>
    MissionPlan(settings: settings, elements: e, payloads: const [sprayer, seeder, drop, gimbal]);

CompiledMission compile(MissionPlan p, {VehicleFacts facts = const VehicleFacts()}) =>
    MissionCompiler(facts: facts).compile(p, home: origin);

List<Issue> validate(MissionPlan p, {VehicleFacts facts = const VehicleFacts()}) =>
    validatePlan(p, compile(p, facts: facts), facts);

(double, double) local(GeoPoint p) => frame.toLocal(p);

void main() {
  group('Survey passes', () {
    test('cover the field at the given spacing, half a spacing in from the edges', () {
      final passes = surveyPasses(field, spacing: 10, angleDeg: 0);
      expect(passes, hasLength(10)); // lines run north–south across 100 m
      final xs = [for (final p in passes) local(p.start).$1];
      expect(xs.first, closeTo(5, 0.05));
      expect(xs.last, closeTo(95, 0.05));
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i] - xs[i - 1], closeTo(10, 0.05));
      }
      // Alternating directions, each pass spanning the field.
      expect(local(passes[0].start).$2, closeTo(0, 0.05));
      expect(local(passes[0].end).$2, closeTo(60, 0.05));
      expect(local(passes[1].start).$2, closeTo(60, 0.05));
    });

    test('east–west passes and run‑in/run‑out beyond the boundary', () {
      final passes = surveyPasses(field, spacing: 20, angleDeg: 90, overshoot: 8);
      expect(passes, hasLength(3));
      final p = passes.first;
      expect(local(p.start).$1, closeTo(0, 0.05));
      expect(local(p.entry).$1, closeTo(-8, 0.05));
      expect(local(p.exit).$1, closeTo(108, 0.05));
    });

    test('a concave field gives separate pieces, so the payload is off over the gap', () {
      // U shape: two 20 m arms joined by a 20 m base.
      final u = [at(0, 0), at(60, 0), at(60, 60), at(40, 60), at(40, 20), at(20, 20), at(20, 60), at(0, 60)];
      final passes = surveyPasses(u, spacing: 10, angleDeg: 90);
      // Lines at y = 5, 15 cross the base (one piece); 25..55 cross both arms.
      expect(passes, hasLength(2 + 4 * 2));
      final c = compile(
        plan([
          SurveyElement(
            id: 's',
            polygon: u,
            altitude: 10,
            spacing: 10,
            angleDeg: 90,
            payload: const PatternPayload(payloadId: 'sprayer'),
          ),
        ]),
      );
      final sprays = c.items.where((i) => i.command == MavCmd.doSprayer).toList();
      expect(sprays.where((i) => i.p1 == 1), hasLength(passes.length));
      expect(sprays.where((i) => i.p1 == 0), hasLength(passes.length));
    });

    test('starts at the corner nearest a given point', () {
      final p = surveyPasses(field, spacing: 10, startNear: at(110, 70));
      expect(local(p.first.entry).$1, closeTo(95, 0.1));
      expect(local(p.first.entry).$2, closeTo(60, 0.1));
    });

    test('a continent‑sized survey is refused before generating anything', () {
      final huge = [const GeoPoint(10, 70), const GeoPoint(10, 80), const GeoPoint(20, 80), const GeoPoint(20, 70)];
      expect(surveyLineCount(huge, spacing: 5), greaterThan(100000));
      expect(surveyLineCount(field, spacing: 10), 10);
      final watch = Stopwatch()..start();
      final c = compile(plan([SurveyElement(id: 's', polygon: huge, altitude: 10, spacing: 5)]));
      expect(watch.elapsedMilliseconds, lessThan(500));
      expect(c.issues.single.message, contains('passes'));
    });

    test('area and self‑intersection', () {
      expect(polygonArea(field), closeTo(6000, 1));
      expect(selfIntersects(field), isFalse);
      expect(selfIntersects([at(0, 0), at(100, 60), at(100, 0), at(0, 60)]), isTrue);
    });
  });

  group('Corridor and orbit geometry', () {
    test('corridor lanes are offset evenly and alternate', () {
      final lanes = corridorLanes([at(0, 0), at(100, 0)], width: 20, spacing: 5, overshoot: 4);
      expect(lanes, hasLength(4));
      final ys = [for (final l in lanes) local(l.points.first).$2];
      expect(ys, [
        for (final y in [7.5, 2.5, -2.5, -7.5]) closeTo(y, 0.05),
      ]);
      expect(local(lanes[0].points.first).$1, closeTo(0, 0.05));
      expect(local(lanes[1].points.first).$1, closeTo(100, 0.05)); // back the other way
      expect(local(lanes[0].entry).$1, closeTo(-4, 0.05));
    });

    test('corridor follows a bend', () {
      final lanes = corridorLanes([at(0, 0), at(50, 0), at(50, 50)], width: 10, spacing: 10);
      expect(lanes.single.points, hasLength(3));
      expect(local(lanes.single.points[1]).$1, closeTo(50, 0.05));
    });

    /// Distance from [p] to the polyline [path], both in local metres.
    double distToPath((double, double) p, List<(double, double)> path) {
      var best = double.infinity;
      for (var i = 0; i + 1 < path.length; i++) {
        final (ax, ay) = path[i];
        final (bx, by) = path[i + 1];
        final dx = bx - ax, dy = by - ay;
        final t = (((p.$1 - ax) * dx + (p.$2 - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
        best = math.min(best, math.sqrt(math.pow(p.$1 - ax - t * dx, 2) + math.pow(p.$2 - ay - t * dy, 2)));
      }
      return best;
    }

    /// Every lane point keeps its own offset from the path: not closer (a loop
    /// folding back past the centre line) and not much further (a spike).
    void expectClean(List<GeoPoint> path, {required double width, required double spacing}) {
      final lanes = corridorLanes(path, width: width, spacing: spacing);
      final n = (width / spacing - 1e-6).ceil();
      expect(lanes, hasLength(n));
      final centre = [for (final p in path) local(p)];
      for (final (k, lane) in lanes.indexed) {
        final off = ((k - (n - 1) / 2) * spacing).abs();
        for (final p in lane.points) {
          final (x, y) = local(p);
          expect(x.isFinite && y.isFinite, isTrue, reason: 'lane $k has a NaN point');
          expect(distToPath((x, y), centre), inInclusiveRange(off - 0.05, off * 1.16 + 0.05), reason: 'lane $k');
        }
      }
    }

    test('sharp corridor corners: no spikes outside, no loops inside', () {
      // 170° hairpin, a 120° corner, then a gentle 20° bend.
      final hairpin = [at(0, 0), at(80, 0), at(0, 14), at(-40, 70), at(-30, 98)];
      expectClean(hairpin, width: 20, spacing: 5);
      // Full U‑turn back along the same line.
      expectClean([at(0, 0), at(60, 0), at(0, 0.001)], width: 10, spacing: 5);
      // Zig‑zag with legs shorter than the corridor is wide.
      expectClean([at(0, 0), at(30, 0), at(20, 8), at(50, 8), at(40, 16)], width: 12, spacing: 4);
    });

    test('outer lane rounds a sharp corner in ≤30° steps; gentle bends keep one mitre point', () {
      final lanes = corridorLanes([at(0, 0), at(80, 0), at(0, 14)], width: 20, spacing: 20);
      expect(lanes.single.points, hasLength(3), reason: 'single centre lane follows the path');
      final two = corridorLanes([at(0, 0), at(80, 0), at(0, 14)], width: 20, spacing: 10);
      // Left hairpin: the right lane (k = 1, flown backwards) is on the outside.
      expect(two[1].points.length, greaterThan(5));
      expect(two[0].points.length, lessThanOrEqualTo(3), reason: 'inside lane cut at the crossing');
      final gentle = corridorLanes([at(0, 0), at(50, 0), at(97, 17)], width: 20, spacing: 10);
      expect(gentle.every((l) => l.points.length == 3), isTrue);
    });

    test('orbit points sit on the circle, legs no larger than the resolution', () {
      final pts = orbitPoints(origin, radius: 25, startBearing: 90, sweepDeg: 360, resolutionDeg: 20);
      expect(pts, hasLength(19));
      for (final p in pts) {
        expect(haversineMetres(origin, p), closeTo(25, 0.02));
      }
      expect(bearingDeg(origin, pts[0]), closeTo(90, 0.01));
      expect(bearingDeg(origin, pts[1]), closeTo(110, 0.01)); // clockwise
      final ccw = orbitPoints(origin, radius: 25, sweepDeg: 90, resolutionDeg: 30, clockwise: false);
      expect(ccw, hasLength(4));
      expect(bearingDeg(origin, ccw[1]), closeTo(330, 0.01));
    });
  });

  group('Compiler', () {
    test('take‑off, waypoints and RTL; seq 0 is the home placeholder', () {
      final c = compile(
        plan([
          WaypointElement(id: 'a', position: at(0, 50), altitude: 15),
          WaypointElement(id: 'b', position: at(50, 50), altitude: 20, acceptRadius: 1),
        ]),
      );
      expect(c.items.map((i) => i.command), [
        MavCmd.navTakeoff,
        MavCmd.navWaypoint,
        MavCmd.navWaypoint,
        MavCmd.navReturnToLaunch,
      ]);
      final w = c.toWire();
      expect(w.first.seq, 0);
      expect(w.first.frame, MavFrame.globalInt);
      expect(w.first.x, (origin.lat * 1e7).round());
      expect([for (final i in w) i.seq], [0, 1, 2, 3, 4]);
      expect(w[1].z, 10);
      expect(w[3].param2, 1);
      expect(w[3].frame, MavFrame.globalRelativeAltInt);
      expect(c.stats.distanceM, closeTo(10 + 50 + 5 + 50 + 5 + 70.71 + 0 + 20, 1));
    });

    test('speed changes only where needed and patterns go back to the default', () {
      final c = compile(
        plan([
          SurveyElement(id: 's', polygon: field, altitude: 10, spacing: 30, speed: 3),
          WaypointElement(id: 'w', position: at(0, 0), altitude: 10),
        ], settings: const MissionSettings(speed: 6)),
      );
      final speeds = [for (final i in c.items.where((i) => i.command == MavCmd.doChangeSpeed)) i.p2];
      expect(speeds, [6, 3, 6]);
    });

    test('survey with the sprayer: on along each pass, off in the turns', () {
      final c = compile(
        plan([
          SurveyElement(
            id: 's',
            polygon: field,
            altitude: 10,
            spacing: 20,
            overshoot: 5,
            payload: const PatternPayload(payloadId: 'sprayer'),
          ),
        ]),
      );
      final cmds = [for (final i in c.of('s')) i.command];
      // Per pass: run‑in, start, sprayer on, end, sprayer off, run‑out.
      expect(cmds.take(6), [
        MavCmd.navWaypoint,
        MavCmd.navWaypoint,
        MavCmd.doSprayer,
        MavCmd.navWaypoint,
        MavCmd.doSprayer,
        MavCmd.navWaypoint,
      ]);
      final legs = c.of('s').where((i) => i.isNav).toList();
      expect([for (final l in legs.take(4)) l.payloadOn], [false, false, true, false]);
      expect(c.stats.workDistanceM, closeTo(5 * 60, 1)); // 5 passes × 60 m
    });

    test('payload on for the whole pattern stays on through the turns', () {
      final c = compile(
        plan([
          SurveyElement(
            id: 's',
            polygon: field,
            altitude: 10,
            spacing: 20,
            payload: const PatternPayload(payloadId: 'sprayer', onlyOnLines: false),
          ),
        ]),
      );
      expect(c.items.where((i) => i.command == MavCmd.doSprayer), hasLength(2));
      final legs = c.of('s').where((i) => i.isNav).skip(1).toList();
      expect(legs.every((l) => l.payloadOn), isTrue);
    });

    test('spreader uses the spinner output; gimbal maps tilt to PWM', () {
      final facts = const VehicleFacts(spinnerChannel: 10);
      final c = MissionCompiler(facts: facts);
      final on = c.payloadItems(seeder, on: true).single;
      expect([on.command, on.p1, on.p2], [MavCmd.doSetServo, 10, 1800]);
      expect(c.payloadItems(seeder, on: false).single.p2, 1000);
      expect(c.payloadItems(gimbal, on: true, tiltDeg: -45).single.p2, 1250);
      expect(c.payloadItems(gimbal, on: true, tiltDeg: -90).single.p2, 1000);
      expect(c.payloadItems(drop, on: true).single.p1, 11);
    });

    test('orbit facing the centre turns before every leg', () {
      final c = compile(
        plan([
          OrbitElement(
            id: 'o',
            center: origin,
            radius: 30,
            altitude: 15,
            sweepDeg: 360,
            resolutionDeg: 30,
            heading: OrbitHeading.center,
          ),
        ]),
      );
      final items = c.of('o').toList();
      final yaws = items.where((i) => i.command == MavCmd.conditionYaw).toList();
      expect(yaws, hasLength(12));
      // Leg 1 runs from bearing 0 to 30 around the centre: mid‑bearing 15,
      // so the vehicle faces 195.
      expect(yaws.first.p1, closeTo(195, 0.01));
      // Each yaw comes right before its leg's waypoint.
      for (var k = 0; k < items.length - 1; k++) {
        if (items[k].command == MavCmd.conditionYaw) expect(items[k + 1].command, MavCmd.navWaypoint);
      }
      expect(c.stats.yawStops, 12);
    });

    test('orbit along travel needs no yaw unless a heading was locked earlier', () {
      OrbitElement orbit() =>
          OrbitElement(id: 'o', center: origin, radius: 30, altitude: 15, sweepDeg: 90, resolutionDeg: 30);
      expect(compile(plan([orbit()])).items.where((i) => i.command == MavCmd.conditionYaw), isEmpty);
      final locked = compile(plan([WaypointElement(id: 'w', position: at(0, 40), altitude: 15, heading: 90), orbit()]));
      final yaws = locked.of('o').where((i) => i.command == MavCmd.conditionYaw).toList();
      expect(yaws, hasLength(3));
      // Leg from bearing 0 to 30 on the circle: chord bearing 105° (clockwise travel).
      expect(yaws.first.p1, closeTo(105, 0.1));
      // WP_YAW_BEHAVIOR 0/4 locks heading from the start of AUTO.
      final fixedFacts = compile(plan([orbit()]), facts: const VehicleFacts(wpYawBehavior: 0));
      expect(fixedFacts.items.where((i) => i.command == MavCmd.conditionYaw), hasLength(3));
    });

    test('finish: land here adds a land at the last point; hover adds nothing', () {
      final e = [WaypointElement(id: 'a', position: at(0, 50), altitude: 15)];
      final land = compile(plan(e, settings: const MissionSettings(finish: FinishAction.landHere)));
      expect(land.items.last.command, MavCmd.navLand);
      expect(land.items.last.position, at(0, 50));
      final hover = compile(plan(e, settings: const MissionSettings(finish: FinishAction.hover)));
      expect(hover.items.last.command, MavCmd.navWaypoint);
    });
  });

  group('Validation', () {
    bool has(List<Issue> issues, IssueLevel level, String text) =>
        issues.any((i) => i.level == level && i.message.contains(text));

    test('catches bad values', () {
      final issues = validate(
        plan([
          WaypointElement(id: 'a', position: at(0, 50), altitude: 0),
          WaypointElement(id: 'b', position: at(0, 60), altitude: 20, speed: 25),
          SurveyElement(id: 's', polygon: [at(0, 0), at(100, 60), at(100, 0), at(0, 60)], altitude: 10),
          OrbitElement(id: 'o', center: origin, radius: 1, altitude: 10),
        ]),
      );
      expect(has(issues, IssueLevel.error, 'above 0 m'), isTrue);
      expect(has(issues, IssueLevel.error, '20 m/s'), isTrue);
      expect(has(issues, IssueLevel.error, 'crosses itself'), isTrue);
      expect(has(issues, IssueLevel.error, 'radius'), isTrue);
      expect(issues.firstWhere((i) => i.message.contains('crosses')).elementId, 's');
    });

    test('warns about payloads APX ignores in missions, not about the spinner', () {
      final issues = validate(
        plan([
          SurveyElement(
            id: 's1',
            polygon: field,
            altitude: 10,
            spacing: 30,
            payload: const PatternPayload(payloadId: 'drop'),
          ),
          SurveyElement(
            id: 's2',
            polygon: field,
            altitude: 10,
            spacing: 30,
            payload: const PatternPayload(payloadId: 'seed'),
          ),
        ]),
      );
      expect(issues.where((i) => i.elementId == 's1' && i.message.contains('ignores')), isNotEmpty);
      expect(issues.where((i) => i.elementId == 's2' && i.level != IssueLevel.info), isEmpty);
    });

    test('sprayer disabled on the vehicle, items after landing, undefined payload', () {
      final issues = validate(
        plan([
          SurveyElement(
            id: 's',
            polygon: field,
            altitude: 10,
            spacing: 30,
            payload: const PatternPayload(payloadId: 'sprayer'),
          ),
          const LandElement(id: 'l'),
          WaypointElement(id: 'w', position: at(0, 0), altitude: 10, actions: const [PayloadAction('nope')]),
        ]),
        facts: const VehicleFacts(sprayEnabled: false),
      );
      expect(has(issues, IssueLevel.warning, 'SPRAY_ENABLE'), isTrue);
      expect(has(issues, IssueLevel.warning, 'never runs'), isTrue);
    });

    test('a clean mission has no errors or warnings', () {
      final issues = validate(
        plan([
          SurveyElement(
            id: 's',
            polygon: field,
            altitude: 10,
            spacing: 10,
            payload: const PatternPayload(payloadId: 'sprayer'),
          ),
        ]),
      );
      expect(issues.where((i) => i.level != IssueLevel.info), isEmpty);
    });
  });

  group('Editing', () {
    test('converting a pattern to waypoints compiles to the same mission', () {
      final p = plan([
        SurveyElement(
          id: 's',
          polygon: field,
          altitude: 12,
          spacing: 15,
          overshoot: 4,
          speed: 3,
          acceptRadius: 1,
          payload: const PatternPayload(payloadId: 'seed'),
        ),
        OrbitElement(
          id: 'o',
          center: at(50, 100),
          radius: 20,
          altitude: 12,
          sweepDeg: 180,
          resolutionDeg: 45,
          heading: OrbitHeading.center,
        ),
        WaypointElement(id: 'w', position: at(0, 0), altitude: 12),
      ]);
      final before = compile(p);
      final ids = IdSource(1);
      final exploded = [for (final e in p.elements) ...explodeElement(e, before, ids)];
      final after = compile(p.copyWith(elements: exploded));
      String sig(PlannedItem i) => '${i.command} ${i.p1} ${i.p2} ${i.p3} ${i.p4} ${i.position} ${i.altitude}';
      expect([for (final i in after.items) sig(i)], [for (final i in before.items) sig(i)]);
      expect(
        exploded.whereType<WaypointElement>().length,
        before.items.where((i) => i.command == MavCmd.navWaypoint).length,
      );
    });

    test('insert waypoint goes into the nearest leg', () {
      final ids = IdSource(1);
      final e = [
        WaypointElement(id: 'a', position: at(0, 0), altitude: 10),
        WaypointElement(id: 'b', position: at(100, 0), altitude: 20),
        WaypointElement(id: 'c', position: at(100, 100), altitude: 30),
      ];
      final out = insertWaypoint(e, at(50, 3), 99, ids);
      expect(out.map((x) => x.id).toList()..removeAt(1), ['a', 'b', 'c']);
      expect((out[1] as WaypointElement).altitude, 10);
    });
  });

  group('Files', () {
    final p = plan([
      SurveyElement(
        id: 's',
        polygon: field,
        altitude: 12,
        spacing: 20,
        angleDeg: 30,
        payload: const PatternPayload(payloadId: 'sprayer'),
      ),
      CommandElement(id: 'c', command: MavCmd.conditionYaw, params: const {1: 90, 2: 20}),
      OrbitElement(id: 'o', center: at(50, 100), radius: 20, altitude: 12, heading: OrbitHeading.outward),
      CorridorElement(id: 'k', path: [at(0, 0), at(0, 200)], altitude: 8, width: 12, spacing: 4),
      WaypointElement(id: 'w', position: at(0, 0), altitude: 12, actions: const [PayloadAction('gim', tiltDeg: -30)]),
    ], settings: const MissionSettings(takeoffAltitude: 7, speed: 4, finish: FinishAction.landHere));

    test('.apxplan keeps everything', () {
      final back = PlanFiles.fromApxPlan(PlanFiles.toApxPlan(p));
      expect(PlanFiles.toApxPlan(back), PlanFiles.toApxPlan(p));
      expect(compile(back).toWire().toString(), compile(p).toWire().toString());
    });

    test('GCS .plan and .waypoints round trip the vehicle items', () {
      final c = compile(p);
      for (final r in [
        PlanFiles.fromQgcPlan(PlanFiles.toQgcPlan(c)),
        PlanFiles.fromWaypoints(PlanFiles.toWaypoints(c)),
      ]) {
        expect(r.warnings, isEmpty);
        expect(r.home!.lat, closeTo(origin.lat, 1e-7));
        final again = MissionCompiler().compile(r.plan, home: r.home);
        expect(again.toWire().toString(), c.toWire().toString());
      }
    });

    test('imports GCS surveys as surveys and reports what it drops', () {
      const planJson = '''
{"fileType":"Plan","mission":{"plannedHomePosition":[18.52,73.85,560],"items":[
 {"type":"SimpleItem","command":22,"frame":3,"params":[0,0,0,null,0,0,12]},
 {"type":"ComplexItem","complexItemType":"survey","angle":45,
  "polygon":[[18.52,73.85],[18.52,73.851],[18.521,73.851],[18.521,73.85]],
  "TransectStyleComplexItem":{"CameraCalc":{"AdjustedFootprintSide":8,"DistanceToSurface":15},"TurnAroundDistance":5}},
 {"type":"SimpleItem","command":16,"frame":3,"params":[5,0,0,null,18.522,73.852,20]},
 {"type":"SimpleItem","command":206,"frame":3,"params":[10,0,0,0,0,0,0]},
 {"type":"SimpleItem","command":20,"frame":3,"params":[0,0,0,0,0,0,0]}]}}''';
      final r = PlanFiles.fromQgcPlan(planJson);
      expect(r.plan.settings.takeoff, isTrue);
      expect(r.plan.settings.takeoffAltitude, 12);
      expect(r.plan.settings.finish, FinishAction.rtl);
      final s = r.plan.elements.first as SurveyElement;
      expect([s.spacing, s.altitude, s.angleDeg, s.overshoot], [8, 15, 45, 5]);
      expect(r.warnings, contains(contains('hold')));
      expect(r.warnings, contains(contains('206')));
    });

    test('a mission read back from the vehicle becomes the same plan', () {
      final c = compile(p);
      final r = PlanFiles.fromWire(c.toWire());
      expect(r.home!.lat, closeTo(origin.lat, 1e-7));
      expect(MissionCompiler().compile(r.plan, home: r.home).toWire().toString(), c.toWire().toString());
    });

    test('rejects other files', () {
      expect(() => PlanFiles.fromApxPlan('{"format":"x"}'), throwsFormatException);
      expect(() => PlanFiles.fromQgcPlan('{"fileType":"Fence"}'), throwsFormatException);
      expect(() => PlanFiles.fromWaypoints('hello'), throwsFormatException);
    });
  });

  group('Resume', () {
    test('continues mid‑survey with speed, heading and sprayer restored', () {
      final p = plan([
        WaypointElement(id: 'h', position: at(-10, -10), altitude: 10, heading: 45),
        SurveyElement(
          id: 's',
          polygon: field,
          altitude: 10,
          spacing: 20,
          speed: 3,
          payload: const PatternPayload(payloadId: 'sprayer'),
        ),
      ]);
      final c = compile(p);
      // Interrupt during the second pass: the item after its "sprayer on".
      final ons = [
        for (final (i, it) in c.items.indexed)
          if (it.command == MavCmd.doSprayer && it.p1 == 1) i,
      ];
      final seq = ons[1] + 2; // 1‑based seq of the waypoint at the end of pass 2
      final r = resumeFrom(c, seq, onGround: true);
      final cmds = r.items.map((i) => i.command).toList();
      expect(cmds.take(6), [
        MavCmd.navTakeoff,
        MavCmd.doChangeSpeed,
        MavCmd.conditionYaw,
        MavCmd.navWaypoint,
        MavCmd.doSprayer,
        MavCmd.navWaypoint,
      ]);
      expect(r.items[1].p2, 3);
      expect(r.items[2].p1, 45);
      expect(r.items[3].position, c.items[ons[1] - 1].position); // start of the interrupted pass
      expect(r.items[4].p1, 1);
      expect(r.items.skip(5).toList(), c.items.skip(seq - 1).toList());
      expect(r.toWire().first.seq, 0);
    });
  });

  test('stats: time adds climb, legs at cruise speed, yaw stops and landing', () {
    final c = compile(
      plan([WaypointElement(id: 'a', position: at(0, 100), altitude: 10, heading: 180)]),
      facts: const VehicleFacts(cruiseSpeed: 5, climbSpeed: 2, descentSpeed: 1, landSpeed: 0.5, rtlAltitude: 15),
    );
    // climb 10 m @2 = 5 s; yaw 180° @30 = 6 s + 2 s settle; 100 m @5 = 20 s;
    // RTL: climb 5 m @2 = 2.5 s; 100 m @5 = 20 s; land 15 m @0.5 = 30 s.
    expect(c.stats.duration.inSeconds, closeTo(85.5, 1));
    expect(c.stats.maxDistanceFromHomeM, closeTo(100, 0.5));
    expect(c.stats.yawStops, 1);
    expect(math.max(0, c.stats.items), 5);
  });
}
