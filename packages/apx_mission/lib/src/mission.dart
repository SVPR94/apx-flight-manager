// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_geo/apx_geo.dart';

import 'catalog.dart';
import 'payload.dart';

/// What the vehicle does after the last element.
enum FinishAction {
  /// Return to launch and land there.
  rtl,

  /// Land where the mission ends.
  landHere,

  /// Hover at the last point (pilot takes over).
  hover,
}

/// Mission‑wide defaults.
final class MissionSettings {
  const MissionSettings({
    this.takeoffAltitude = 10,
    this.altitude = 20,
    this.speed,
    this.finish = FinishAction.rtl,
    this.takeoff = true,
  });

  /// Start with a take‑off to this height (m above home).
  final bool takeoff;
  final double takeoffAltitude;

  /// Default height for new items (m above home).
  final double altitude;

  /// Cruise speed (m/s); null = the vehicle's WPNAV_SPEED.
  final double? speed;
  final FinishAction finish;

  MissionSettings copyWith({
    double? takeoffAltitude,
    double? altitude,
    double? speed,
    bool clearSpeed = false,
    FinishAction? finish,
    bool? takeoff,
  }) => MissionSettings(
    takeoffAltitude: takeoffAltitude ?? this.takeoffAltitude,
    altitude: altitude ?? this.altitude,
    speed: clearSpeed ? null : (speed ?? this.speed),
    finish: finish ?? this.finish,
    takeoff: takeoff ?? this.takeoff,
  );

  Map<String, Object?> toJson() => {
    'takeoff': takeoff,
    'takeoffAltitude': takeoffAltitude,
    'altitude': altitude,
    'speed': speed,
    'finish': finish.name,
  };

  factory MissionSettings.fromJson(Map<String, Object?> j) => MissionSettings(
    takeoff: j['takeoff'] != false,
    takeoffAltitude: (j['takeoffAltitude'] as num?)?.toDouble() ?? 10,
    altitude: (j['altitude'] as num?)?.toDouble() ?? 20,
    speed: (j['speed'] as num?)?.toDouble(),
    finish: FinishAction.values.asNameMap()[j['finish']] ?? FinishAction.rtl,
  );
}

/// One entry in the mission list. Patterns expand into many items when
/// compiled; every element can be edited, and patterns can be converted to
/// plain waypoints for item‑by‑item editing.
sealed class MissionElement {
  const MissionElement(this.id);

  final String id;

  String get title;

  /// Map positions that define the element (for zoom‑to and bounds).
  List<GeoPoint> get anchors;

  Map<String, Object?> toJson();

  /// A copy with every position moved by [dLat]/[dLon] (drag the whole element).
  MissionElement translated(double dLat, double dLon);

  static MissionElement fromJson(Map<String, Object?> j) => switch (j['type']) {
    'waypoint' => WaypointElement.fromJson(j),
    'command' => CommandElement.fromJson(j),
    'land' => LandElement.fromJson(j),
    'survey' => SurveyElement.fromJson(j),
    'corridor' => CorridorElement.fromJson(j),
    'orbit' => OrbitElement.fromJson(j),
    _ => throw FormatException('Unknown mission element "${j['type']}"'),
  };
}

GeoPoint _p(Object? v) {
  final l = v as List;
  return GeoPoint((l[0] as num).toDouble(), (l[1] as num).toDouble());
}

List<double> _j(GeoPoint p) => [p.lat, p.lon];

List<PayloadAction> _actions(Object? v) => [
  for (final a in (v as List? ?? const [])) PayloadAction.fromJson((a as Map).cast()),
];

GeoPoint _shift(GeoPoint p, double dLat, double dLon) => GeoPoint(p.lat + dLat, p.lon + dLon);

/// Fly to a point. Optional speed for the leg, acceptance radius, heading
/// (a CONDITION_YAW before the leg) and payload actions on arrival.
final class WaypointElement extends MissionElement {
  const WaypointElement({
    required String id,
    required this.position,
    required this.altitude,
    this.speed,
    this.acceptRadius,
    this.heading,
    this.actions = const [],
  }) : super(id);

  final GeoPoint position;
  final double altitude;
  final double? speed;
  final double? acceptRadius;

  /// Turn to this heading (deg) before flying the leg; null = automatic.
  final double? heading;
  final List<PayloadAction> actions;

  @override
  String get title => 'Waypoint';
  @override
  List<GeoPoint> get anchors => [position];

  WaypointElement copyWith({
    GeoPoint? position,
    double? altitude,
    double? speed,
    bool clearSpeed = false,
    double? acceptRadius,
    bool clearRadius = false,
    double? heading,
    bool clearHeading = false,
    List<PayloadAction>? actions,
  }) => WaypointElement(
    id: id,
    position: position ?? this.position,
    altitude: altitude ?? this.altitude,
    speed: clearSpeed ? null : (speed ?? this.speed),
    acceptRadius: clearRadius ? null : (acceptRadius ?? this.acceptRadius),
    heading: clearHeading ? null : (heading ?? this.heading),
    actions: actions ?? this.actions,
  );

  @override
  WaypointElement translated(double dLat, double dLon) => copyWith(position: _shift(position, dLat, dLon));

  @override
  Map<String, Object?> toJson() => {
    'type': 'waypoint',
    'id': id,
    'position': _j(position),
    'altitude': altitude,
    'speed': speed,
    'acceptRadius': acceptRadius,
    'heading': heading,
    'actions': [for (final a in actions) a.toJson()],
  };

  factory WaypointElement.fromJson(Map<String, Object?> j) => WaypointElement(
    id: j['id'] as String,
    position: _p(j['position']),
    altitude: (j['altitude'] as num).toDouble(),
    speed: (j['speed'] as num?)?.toDouble(),
    acceptRadius: (j['acceptRadius'] as num?)?.toDouble(),
    heading: (j['heading'] as num?)?.toDouble(),
    actions: _actions(j['actions']),
  );
}

/// A standalone action or condition from [ApxCatalog.standalone], or a
/// payload action ([payload] set, command ignored).
final class CommandElement extends MissionElement {
  const CommandElement({required String id, this.command = 0, this.params = const {}, this.payload}) : super(id);

  final int command;

  /// Param index (1–4, 7 = altitude) → value.
  final Map<int, double> params;

  /// Set a payload's state here instead of a raw command.
  final PayloadAction? payload;

  ApxCommand? get spec => ApxCatalog.byId(command);

  double param(int i) => params[i] ?? spec?.params.where((p) => p.index == i).firstOrNull?.defaultValue ?? 0;

  @override
  String get title => payload != null ? 'Payload' : (spec?.name ?? 'Command $command');
  @override
  List<GeoPoint> get anchors => const [];

  @override
  CommandElement translated(double dLat, double dLon) => this;

  CommandElement copyWith({int? command, Map<int, double>? params, PayloadAction? payload}) => CommandElement(
    id: id,
    command: command ?? this.command,
    params: params ?? this.params,
    payload: payload ?? this.payload,
  );

  @override
  Map<String, Object?> toJson() => {
    'type': 'command',
    'id': id,
    'command': command,
    'params': {for (final e in params.entries) '${e.key}': e.value},
    'payload': payload?.toJson(),
  };

  factory CommandElement.fromJson(Map<String, Object?> j) => CommandElement(
    id: j['id'] as String,
    command: (j['command'] as num?)?.toInt() ?? 0,
    params: {
      for (final e in ((j['params'] as Map?) ?? const {}).entries) int.parse('${e.key}'): (e.value as num).toDouble(),
    },
    payload: j['payload'] == null ? null : PayloadAction.fromJson((j['payload'] as Map).cast()),
  );
}

/// Land at a point (or at home when [position] is null). The vehicle
/// disarms on touchdown, so nothing after it runs.
final class LandElement extends MissionElement {
  const LandElement({required String id, this.position}) : super(id);
  final GeoPoint? position;

  @override
  String get title => position == null ? 'Land at home' : 'Land';
  @override
  List<GeoPoint> get anchors => [?position];
  @override
  LandElement translated(double dLat, double dLon) =>
      position == null ? this : LandElement(id: id, position: _shift(position!, dLat, dLon));

  @override
  Map<String, Object?> toJson() => {'type': 'land', 'id': id, 'position': position == null ? null : _j(position!)};

  factory LandElement.fromJson(Map<String, Object?> j) =>
      LandElement(id: j['id'] as String, position: j['position'] == null ? null : _p(j['position']));
}

/// Lawn‑mower coverage of a polygon: parallel passes [spacing] apart along
/// [angleDeg] (bearing of the passes).
final class SurveyElement extends MissionElement {
  const SurveyElement({
    required String id,
    required this.polygon,
    required this.altitude,
    this.spacing = 5,
    this.angleDeg = 0,
    this.overshoot = 0,
    this.speed,
    this.acceptRadius,
    this.reverse = false,
    this.payload = const PatternPayload(),
  }) : super(id);

  final List<GeoPoint> polygon;
  final double altitude;

  /// Distance between passes (m): swath width × (1 − overlap).
  final double spacing;
  final double angleDeg;

  /// Extra run‑in/run‑out beyond the boundary so the vehicle is straight
  /// and at speed when the payload switches (m).
  final double overshoot;
  final double? speed;

  /// Acceptance radius / corner cut for the pattern's waypoints (m).
  final double? acceptRadius;

  /// Start from the other side (reverses pass order and direction).
  final bool reverse;
  final PatternPayload payload;

  @override
  String get title => 'Survey';
  @override
  List<GeoPoint> get anchors => polygon;

  SurveyElement copyWith({
    List<GeoPoint>? polygon,
    double? altitude,
    double? spacing,
    double? angleDeg,
    double? overshoot,
    double? speed,
    bool clearSpeed = false,
    double? acceptRadius,
    bool clearRadius = false,
    bool? reverse,
    PatternPayload? payload,
  }) => SurveyElement(
    id: id,
    polygon: polygon ?? this.polygon,
    altitude: altitude ?? this.altitude,
    spacing: spacing ?? this.spacing,
    angleDeg: angleDeg ?? this.angleDeg,
    overshoot: overshoot ?? this.overshoot,
    speed: clearSpeed ? null : (speed ?? this.speed),
    acceptRadius: clearRadius ? null : (acceptRadius ?? this.acceptRadius),
    reverse: reverse ?? this.reverse,
    payload: payload ?? this.payload,
  );

  @override
  SurveyElement translated(double dLat, double dLon) =>
      copyWith(polygon: [for (final p in polygon) _shift(p, dLat, dLon)]);

  @override
  Map<String, Object?> toJson() => {
    'type': 'survey',
    'id': id,
    'polygon': [for (final p in polygon) _j(p)],
    'altitude': altitude,
    'spacing': spacing,
    'angle': angleDeg,
    'overshoot': overshoot,
    'speed': speed,
    'acceptRadius': acceptRadius,
    'reverse': reverse,
    'payload': payload.toJson(),
  };

  factory SurveyElement.fromJson(Map<String, Object?> j) => SurveyElement(
    id: j['id'] as String,
    polygon: [for (final p in j['polygon'] as List) _p(p)],
    altitude: (j['altitude'] as num).toDouble(),
    spacing: (j['spacing'] as num?)?.toDouble() ?? 5,
    angleDeg: (j['angle'] as num?)?.toDouble() ?? 0,
    overshoot: (j['overshoot'] as num?)?.toDouble() ?? 0,
    speed: (j['speed'] as num?)?.toDouble(),
    acceptRadius: (j['acceptRadius'] as num?)?.toDouble(),
    reverse: j['reverse'] == true,
    payload: PatternPayload.fromJson((j['payload'] as Map?)?.cast()),
  );
}

/// Passes along a path (road, canal, power line): [width] wide, passes
/// [spacing] apart, alternating direction.
final class CorridorElement extends MissionElement {
  const CorridorElement({
    required String id,
    required this.path,
    required this.altitude,
    this.width = 10,
    this.spacing = 5,
    this.overshoot = 0,
    this.speed,
    this.acceptRadius,
    this.payload = const PatternPayload(),
  }) : super(id);

  final List<GeoPoint> path;
  final double altitude, width, spacing, overshoot;
  final double? speed, acceptRadius;
  final PatternPayload payload;

  int get lanes => spacing <= 0 ? 1 : (width / spacing - 1e-6).ceil().clamp(1, 100);

  @override
  String get title => 'Corridor';
  @override
  List<GeoPoint> get anchors => path;

  CorridorElement copyWith({
    List<GeoPoint>? path,
    double? altitude,
    double? width,
    double? spacing,
    double? overshoot,
    double? speed,
    bool clearSpeed = false,
    double? acceptRadius,
    bool clearRadius = false,
    PatternPayload? payload,
  }) => CorridorElement(
    id: id,
    path: path ?? this.path,
    altitude: altitude ?? this.altitude,
    width: width ?? this.width,
    spacing: spacing ?? this.spacing,
    overshoot: overshoot ?? this.overshoot,
    speed: clearSpeed ? null : (speed ?? this.speed),
    acceptRadius: clearRadius ? null : (acceptRadius ?? this.acceptRadius),
    payload: payload ?? this.payload,
  );

  @override
  CorridorElement translated(double dLat, double dLon) => copyWith(path: [for (final p in path) _shift(p, dLat, dLon)]);

  @override
  Map<String, Object?> toJson() => {
    'type': 'corridor',
    'id': id,
    'path': [for (final p in path) _j(p)],
    'altitude': altitude,
    'width': width,
    'spacing': spacing,
    'overshoot': overshoot,
    'speed': speed,
    'acceptRadius': acceptRadius,
    'payload': payload.toJson(),
  };

  factory CorridorElement.fromJson(Map<String, Object?> j) => CorridorElement(
    id: j['id'] as String,
    path: [for (final p in j['path'] as List) _p(p)],
    altitude: (j['altitude'] as num).toDouble(),
    width: (j['width'] as num?)?.toDouble() ?? 10,
    spacing: (j['spacing'] as num?)?.toDouble() ?? 5,
    overshoot: (j['overshoot'] as num?)?.toDouble() ?? 0,
    speed: (j['speed'] as num?)?.toDouble(),
    acceptRadius: (j['acceptRadius'] as num?)?.toDouble(),
    payload: PatternPayload.fromJson((j['payload'] as Map?)?.cast()),
  );
}

/// Where the vehicle points while flying an orbit.
enum OrbitHeading {
  /// Along the direction of travel.
  travel,

  /// At the centre (inspection, spraying a tree / pole).
  center,

  /// Away from the centre.
  outward,

  /// One fixed heading throughout.
  fixed,
}

/// A circle (or arc) flown as straight legs of [resolutionDeg] each.
final class OrbitElement extends MissionElement {
  const OrbitElement({
    required String id,
    required this.center,
    required this.radius,
    required this.altitude,
    this.startBearing = 0,
    this.sweepDeg = 360,
    this.clockwise = true,
    this.resolutionDeg = 15,
    this.heading = OrbitHeading.travel,
    this.fixedHeading = 0,
    this.yawRate = 0,
    this.speed,
    this.acceptRadius,
    this.payload = const PatternPayload(),
  }) : super(id);

  final GeoPoint center;
  final double radius, altitude;

  /// Where on the circle to start, as a bearing from the centre.
  final double startBearing;

  /// How much of the circle (360 = one turn; more = several turns).
  final double sweepDeg;
  final bool clockwise;

  /// Angle per straight leg; smaller = rounder but more items (and, when
  /// the heading is held, more stops).
  final double resolutionDeg;
  final OrbitHeading heading;
  final double fixedHeading;

  /// Yaw turn rate for heading changes (°/s, 0 = firmware default 30).
  final double yawRate;
  final double? speed, acceptRadius;
  final PatternPayload payload;

  int get legs => (sweepDeg / resolutionDeg.clamp(1, 90)).ceil().clamp(1, 1000);

  @override
  String get title => 'Orbit';
  @override
  List<GeoPoint> get anchors => [center];

  OrbitElement copyWith({
    GeoPoint? center,
    double? radius,
    double? altitude,
    double? startBearing,
    double? sweepDeg,
    bool? clockwise,
    double? resolutionDeg,
    OrbitHeading? heading,
    double? fixedHeading,
    double? yawRate,
    double? speed,
    bool clearSpeed = false,
    double? acceptRadius,
    bool clearRadius = false,
    PatternPayload? payload,
  }) => OrbitElement(
    id: id,
    center: center ?? this.center,
    radius: radius ?? this.radius,
    altitude: altitude ?? this.altitude,
    startBearing: startBearing ?? this.startBearing,
    sweepDeg: sweepDeg ?? this.sweepDeg,
    clockwise: clockwise ?? this.clockwise,
    resolutionDeg: resolutionDeg ?? this.resolutionDeg,
    heading: heading ?? this.heading,
    fixedHeading: fixedHeading ?? this.fixedHeading,
    yawRate: yawRate ?? this.yawRate,
    speed: clearSpeed ? null : (speed ?? this.speed),
    acceptRadius: clearRadius ? null : (acceptRadius ?? this.acceptRadius),
    payload: payload ?? this.payload,
  );

  @override
  OrbitElement translated(double dLat, double dLon) => copyWith(center: _shift(center, dLat, dLon));

  @override
  Map<String, Object?> toJson() => {
    'type': 'orbit',
    'id': id,
    'center': _j(center),
    'radius': radius,
    'altitude': altitude,
    'startBearing': startBearing,
    'sweep': sweepDeg,
    'clockwise': clockwise,
    'resolution': resolutionDeg,
    'heading': heading.name,
    'fixedHeading': fixedHeading,
    'yawRate': yawRate,
    'speed': speed,
    'acceptRadius': acceptRadius,
    'payload': payload.toJson(),
  };

  factory OrbitElement.fromJson(Map<String, Object?> j) => OrbitElement(
    id: j['id'] as String,
    center: _p(j['center']),
    radius: (j['radius'] as num).toDouble(),
    altitude: (j['altitude'] as num).toDouble(),
    startBearing: (j['startBearing'] as num?)?.toDouble() ?? 0,
    sweepDeg: (j['sweep'] as num?)?.toDouble() ?? 360,
    clockwise: j['clockwise'] != false,
    resolutionDeg: (j['resolution'] as num?)?.toDouble() ?? 15,
    heading: OrbitHeading.values.asNameMap()[j['heading']] ?? OrbitHeading.travel,
    fixedHeading: (j['fixedHeading'] as num?)?.toDouble() ?? 0,
    yawRate: (j['yawRate'] as num?)?.toDouble() ?? 0,
    speed: (j['speed'] as num?)?.toDouble(),
    acceptRadius: (j['acceptRadius'] as num?)?.toDouble(),
    payload: PatternPayload.fromJson((j['payload'] as Map?)?.cast()),
  );
}

/// A whole plan: settings, elements in order, and the payloads it uses.
final class MissionPlan {
  const MissionPlan({
    this.settings = const MissionSettings(),
    this.elements = const [],
    this.payloads = const [Payload.defaultSprayer],
  });

  final MissionSettings settings;
  final List<MissionElement> elements;
  final List<Payload> payloads;

  Payload? payload(String? id) => id == null ? null : payloads.where((p) => p.id == id).firstOrNull;

  MissionPlan copyWith({MissionSettings? settings, List<MissionElement>? elements, List<Payload>? payloads}) =>
      MissionPlan(
        settings: settings ?? this.settings,
        elements: elements ?? this.elements,
        payloads: payloads ?? this.payloads,
      );

  GeoBounds? get bounds {
    final pts = [for (final e in elements) ...e.anchors];
    return pts.isEmpty ? null : GeoBounds.around(pts);
  }

  static const formatVersion = 1;

  Map<String, Object?> toJson() => {
    'format': 'apxplan',
    'version': formatVersion,
    'settings': settings.toJson(),
    'payloads': [for (final p in payloads) p.toJson()],
    'elements': [for (final e in elements) e.toJson()],
  };

  factory MissionPlan.fromJson(Map<String, Object?> j) {
    if (j['format'] != 'apxplan') throw const FormatException('Not an APX plan file');
    if (((j['version'] as num?) ?? 0) > formatVersion) {
      throw const FormatException('This plan was saved by a newer APX Flight Manager.');
    }
    return MissionPlan(
      settings: MissionSettings.fromJson(((j['settings'] as Map?) ?? const {}).cast()),
      payloads: [for (final p in (j['payloads'] as List? ?? const [])) Payload.fromJson((p as Map).cast())],
      elements: [for (final e in (j['elements'] as List? ?? const [])) MissionElement.fromJson((e as Map).cast())],
    );
  }
}
