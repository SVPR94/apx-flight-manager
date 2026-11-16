// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';

import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';

import 'catalog.dart';
import 'compile.dart';
import 'edit.dart';
import 'mission.dart';

/// A plan read from a file, with anything that couldn't be carried over.
final class ImportResult {
  const ImportResult(this.plan, this.warnings, {this.home});
  final MissionPlan plan;
  final List<String> warnings;
  final GeoPoint? home;
}

/// Plan files: `.apxplan` (lossless, this app), APX Flight Manager `.plan`
/// (JSON) and Standard GCS `.waypoints` (GCS WPL 110 text).
abstract final class PlanFiles {
  // ---- .apxplan ------------------------------------------------------------

  static String toApxPlan(MissionPlan plan) => const JsonEncoder.withIndent(' ').convert(plan.toJson());

  static MissionPlan fromApxPlan(String text) => MissionPlan.fromJson((jsonDecode(text) as Map).cast());

  // ---- APX Flight Manager .plan ------------------------------------------------

  /// Exports the compiled items as GCS SimpleItems (GCS shows patterns from
  /// other tools as plain items, so this is what it can read faithfully).
  static String toQgcPlan(CompiledMission m, {double cruiseSpeed = 5}) {
    final wire = m.toWire();
    final home = wire.first;
    final items = [
      for (final it in wire.skip(1))
        {
          'AMSLAltAboveTerrain': null,
          'Altitude': it.z,
          'AltitudeMode': 1,
          'autoContinue': true,
          'command': it.command,
          'doJumpId': it.seq,
          'frame': MavFrame.globalRelativeAlt,
          'params': [it.param1, it.param2, it.param3, it.param4, it.x / 1e7, it.y / 1e7, it.z],
          'type': 'SimpleItem',
        },
    ];
    return const JsonEncoder.withIndent('    ').convert({
      'fileType': 'Plan',
      'geoFence': {'circles': [], 'polygons': [], 'version': 2},
      'groundStation': 'APX Flight Manager',
      'mission': {
        'cruiseSpeed': cruiseSpeed,
        'firmwareType': 3,
        'globalPlanAltitudeMode': 1,
        'hoverSpeed': cruiseSpeed,
        'items': items,
        'plannedHomePosition': [home.x / 1e7, home.y / 1e7, 0],
        'vehicleType': 2,
        'version': 2,
      },
      'rallyPoints': {'points': [], 'version': 2},
      'version': 1,
    });
  }

  static ImportResult fromQgcPlan(String text, {IdSource? ids}) {
    final j = jsonDecode(text);
    if (j is! Map || j['fileType'] != 'Plan') throw const FormatException('Not a Standard .plan file');
    final mission = (j['mission'] as Map?) ?? const {};
    final b = _Builder(ids ?? IdSource());
    final hp = mission['plannedHomePosition'];
    final home = hp is List && hp.length >= 2 ? GeoPoint((hp[0] as num).toDouble(), (hp[1] as num).toDouble()) : null;
    for (final raw in (mission['items'] as List? ?? const [])) {
      final it = (raw as Map).cast<String, Object?>();
      switch (it['type']) {
        case 'SimpleItem':
          final p = [for (final v in (it['params'] as List)) (v as num?)?.toDouble() ?? 0.0];
          b.add(it['command'] as int, p, frame: (it['frame'] as num?)?.toInt() ?? 3);
        case 'ComplexItem':
          b.complex(it);
        default:
          b.warnings.add('Skipped an unknown item type "${it['type']}".');
      }
    }
    return ImportResult(b.plan(), b.warnings, home: home);
  }

  // ---- From the vehicle ----------------------------------------------------

  /// A mission downloaded from the vehicle, as editable elements (seq 0 is
  /// APX's home placeholder and becomes the planning home).
  static ImportResult fromWire(List<WireMissionItem> items, {IdSource? ids}) {
    final b = _Builder(ids ?? IdSource());
    GeoPoint? home;
    for (final it in items) {
      final p = [it.param1, it.param2, it.param3, it.param4, it.x / 1e7, it.y / 1e7, it.z];
      if (it.seq == 0) {
        if (it.x != 0 || it.y != 0) home = GeoPoint(it.x / 1e7, it.y / 1e7);
        continue;
      }
      b.add(it.command, p, frame: it.frame);
    }
    return ImportResult(b.plan(), b.warnings, home: home);
  }

  // ---- Standard GCS .waypoints ------------------------------------------

  static String toWaypoints(CompiledMission m) {
    final b = StringBuffer('GCS WPL 110\n');
    for (final it in m.toWire()) {
      final frame = it.seq == 0 ? 0 : MavFrame.globalRelativeAlt;
      b.writeln(
        [
          it.seq,
          it.seq == 0 ? 1 : 0,
          frame,
          it.command,
          _n(it.param1),
          _n(it.param2),
          _n(it.param3),
          _n(it.param4),
          (it.x / 1e7).toStringAsFixed(8),
          (it.y / 1e7).toStringAsFixed(8),
          _n(it.z),
          1,
        ].join('\t'),
      );
    }
    return b.toString();
  }

  static ImportResult fromWaypoints(String text, {IdSource? ids}) {
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty || !lines.first.startsWith('GCS WPL'))
      throw const FormatException('Not a .waypoints (GCS WPL) file');
    final b = _Builder(ids ?? IdSource());
    GeoPoint? home;
    for (final line in lines.skip(1)) {
      final f = line.trim().split(RegExp(r'\s+'));
      if (f.length < 12) {
        b.warnings.add('Skipped a malformed line: "$line"');
        continue;
      }
      final seq = int.parse(f[0]), frame = int.parse(f[2]), cmd = int.parse(f[3]);
      final p = [for (final v in f.sublist(4, 11)) double.parse(v)];
      if (seq == 0) {
        home = GeoPoint(p[4], p[5]);
        continue;
      }
      b.add(cmd, p, frame: frame);
    }
    return ImportResult(b.plan(), b.warnings, home: home);
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// Turns flat items from other tools into plan elements.
final class _Builder {
  _Builder(this.ids);
  final IdSource ids;
  final warnings = <String>[];
  final elements = <MissionElement>[];
  // Nothing implied: take‑off and RTL only if the file has them.
  var settings = const MissionSettings(takeoff: false, finish: FinishAction.hover);
  var sawAbsolute = false;

  void add(int cmd, List<double> p, {required int frame}) {
    final pos = p.length >= 6 && (p[4] != 0 || p[5] != 0) ? GeoPoint(p[4], p[5]) : null;
    final alt = p.length >= 7 ? p[6] : 0.0;
    if (frame == MavFrame.global || frame == MavFrame.globalInt) {
      if (!sawAbsolute)
        warnings.add('Some altitudes were above sea level (AMSL); they were kept as heights above home.');
      sawAbsolute = true;
    }
    switch (cmd) {
      case MavCmd.navTakeoff when elements.isEmpty:
        settings = settings.copyWith(takeoff: true, takeoffAltitude: alt > 0 ? alt : 10);
      case MavCmd.navWaypoint:
        if (pos == null) {
          warnings.add('Skipped a waypoint without a position.');
          return;
        }
        if (p[0] != 0) warnings.add('APX ignores waypoint hold times; a ${p[0]} s hold was dropped.');
        elements.add(
          WaypointElement(id: ids.next(), position: pos, altitude: alt, acceptRadius: p[1] > 0 ? p[1] : null),
        );
      case MavCmd.navLand:
        elements.add(LandElement(id: ids.next(), position: pos));
      case MavCmd.navReturnToLaunch:
        settings = settings.copyWith(finish: FinishAction.rtl);
      default:
        final spec = ApxCatalog.byId(cmd);
        if (spec == null || spec.kind == CommandKind.nav) {
          warnings.add('Skipped command $cmd: APX doesn\'t execute it.');
          return;
        }
        elements.add(
          CommandElement(
            id: ids.next(),
            command: cmd,
            params: {1: p[0], 2: p[1], 3: p[2], 4: p[3], if (alt != 0) 7: alt},
          ),
        );
    }
  }

  /// GCS survey / corridor scan → our patterns; anything else → its items.
  void complex(Map<String, Object?> it) {
    final type = it['complexItemType'];
    final transect = (it['TransectStyleComplexItem'] as Map?)?.cast<String, Object?>();
    final cam = (transect?['CameraCalc'] as Map?)?.cast<String, Object?>();
    final spacing = (cam?['AdjustedFootprintSide'] as num?)?.toDouble();
    final alt = (cam?['DistanceToSurface'] as num?)?.toDouble() ?? settings.altitude;
    final turn = (transect?['TurnAroundDistance'] as num?)?.toDouble() ?? 0;
    List<GeoPoint> pts(Object? v) => [
      for (final p in (v as List? ?? const [])) GeoPoint(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    if (type == 'survey' && spacing != null) {
      elements.add(
        SurveyElement(
          id: ids.next(),
          polygon: pts(it['polygon']),
          altitude: alt,
          spacing: spacing,
          angleDeg: (it['angle'] as num?)?.toDouble() ?? 0,
          overshoot: turn,
        ),
      );
    } else if (type == 'CorridorScan' && spacing != null) {
      elements.add(
        CorridorElement(
          id: ids.next(),
          path: pts(it['polyline']),
          altitude: alt,
          width: (it['CorridorWidth'] as num?)?.toDouble() ?? spacing,
          spacing: spacing,
          overshoot: turn,
        ),
      );
    } else {
      final inner = transect?['Items'] as List?;
      if (inner == null) {
        warnings.add('Skipped a "$type" pattern this app can\'t read.');
        return;
      }
      warnings.add('A "$type" pattern was imported as its individual items.');
      for (final raw in inner) {
        final s = (raw as Map).cast<String, Object?>();
        add(s['command'] as int, [for (final v in (s['params'] as List)) (v as num?)?.toDouble() ?? 0.0], frame: 3);
      }
    }
  }

  MissionPlan plan() => MissionPlan(settings: settings, elements: elements);
}
