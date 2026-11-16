// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';

/// How a mission command behaves in APX's AUTO mode.
enum CommandKind {
  /// Flies somewhere; the mission waits for arrival.
  nav,

  /// Holds position until done (e.g. a yaw turn).
  condition,

  /// Runs instantly when the mission reaches it, after the previous nav item.
  action,
}

/// One parameter the firmware actually reads.
final class ParamSpec {
  const ParamSpec(
    this.index,
    this.label, {
    this.unit = '',
    this.min,
    this.max,
    this.defaultValue = 0,
    this.options,
    this.help,
  });

  /// 1..4 (param1..param4), 7 = altitude.
  final int index;
  final String label, unit;
  final double? min, max;
  final double defaultValue;

  /// For enumerated params: value → label.
  final Map<int, String>? options;
  final String? help;
}

/// A mission command APX executes, with exactly the parameters it reads
/// (from `modules/modes/mode_auto.cpp`; see docs/01 §8).
final class ApxCommand {
  const ApxCommand(this.id, this.name, this.kind, {this.params = const [], this.hasPosition = false, this.note});

  final int id;
  final String name;
  final CommandKind kind;
  final List<ParamSpec> params;

  /// Uses latitude/longitude.
  final bool hasPosition;

  /// What the firmware does differently from the MAVLink spec.
  final String? note;
}

/// The ten commands APX 0.1 executes. Anything else is skipped in flight, so
/// the planner never produces it.
abstract final class ApxCatalog {
  static const waypoint = ApxCommand(
    MavCmd.navWaypoint,
    'Waypoint',
    CommandKind.nav,
    hasPosition: true,
    params: [
      ParamSpec(
        2,
        'Acceptance radius',
        unit: 'm',
        min: 0,
        max: 50,
        help: '0 = WPNAV_RADIUS. Also how far a fly‑through corner may pass from the point.',
      ),
      ParamSpec(7, 'Altitude', unit: 'm', min: 0, max: 500),
    ],
    note: 'APX ignores hold time and yaw on waypoints.',
  );

  static const takeoff = ApxCommand(
    MavCmd.navTakeoff,
    'Take off',
    CommandKind.nav,
    params: [ParamSpec(7, 'Altitude', unit: 'm', min: 1, max: 500, defaultValue: 10)],
    note: 'Climbs vertically where the vehicle is.',
  );

  static const land = ApxCommand(
    MavCmd.navLand,
    'Land',
    CommandKind.nav,
    hasPosition: true,
    note: 'Flies level to the point, then descends and disarms. No position = land at home.',
  );

  static const rtl = ApxCommand(
    MavCmd.navReturnToLaunch,
    'Return to launch',
    CommandKind.nav,
    note: 'Climbs to RTL_ALT if lower, flies home and lands.',
  );

  static const changeAlt = ApxCommand(
    MavCmd.conditionChangeAlt,
    'Change altitude (hold)',
    CommandKind.condition,
    params: [
      ParamSpec(1, 'Climb rate', unit: 'm/s', min: 0, max: 10, help: '0 = WPNAV_SPEED_UP / _DN'),
      ParamSpec(7, 'Altitude', unit: 'm', min: 0, max: 500),
    ],
  );

  static const yaw = ApxCommand(
    MavCmd.conditionYaw,
    'Turn to heading (hold)',
    CommandKind.condition,
    params: [
      ParamSpec(1, 'Heading', unit: '°', min: 0, max: 360),
      ParamSpec(2, 'Turn rate', unit: '°/s', min: 0, max: 180, help: '0 = 30 °/s'),
      ParamSpec(3, 'Direction', options: {0: 'Shortest', 1: 'Clockwise', -1: 'Counter‑clockwise'}),
      ParamSpec(4, 'Relative', options: {0: 'Absolute', 1: 'Relative'}),
    ],
    note: 'Stops, turns, then keeps that heading for the rest of the mission.',
  );

  static const changeSpeed = ApxCommand(
    MavCmd.doChangeSpeed,
    'Set speed',
    CommandKind.action,
    params: [
      ParamSpec(1, 'Speed type', options: {1: 'Ground speed', 2: 'Climb rate', 3: 'Descent rate'}, defaultValue: 1),
      ParamSpec(2, 'Speed', unit: 'm/s', min: -2, max: 20, defaultValue: 5, help: '−2 resets to WPNAV_SPEED'),
    ],
  );

  static const setServo = ApxCommand(
    MavCmd.doSetServo,
    'Set servo',
    CommandKind.action,
    params: [
      ParamSpec(1, 'Output', min: 9, max: 16, defaultValue: 9),
      ParamSpec(2, 'PWM', unit: 'µs', min: 800, max: 2200, defaultValue: 1500),
    ],
    note: 'In APX 0.1 missions only the sprayer pump and spinner outputs respond.',
  );

  static const changeAltitude = ApxCommand(
    MavCmd.doChangeAltitude,
    'Change altitude',
    CommandKind.action,
    params: [ParamSpec(1, 'Altitude', unit: 'm', min: 0, max: 500)],
  );

  static const sprayer = ApxCommand(
    MavCmd.doSprayer,
    'Sprayer',
    CommandKind.action,
    params: [
      ParamSpec(1, 'Spray', options: {1: 'On', 0: 'Off'}, defaultValue: 1),
    ],
    note: 'Pump follows ground speed (SPRAY_PUMP_RATE). Needs SPRAY_ENABLE = 1.',
  );

  static const all = [waypoint, takeoff, land, rtl, changeAlt, yaw, changeSpeed, setServo, changeAltitude, sprayer];

  /// Commands a user may add on their own (nav items have dedicated elements).
  static const standalone = [yaw, changeSpeed, changeAlt, changeAltitude, setServo, sprayer];

  static ApxCommand? byId(int id) => all.where((c) => c.id == id).firstOrNull;
}
