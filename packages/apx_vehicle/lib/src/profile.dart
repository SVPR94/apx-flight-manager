// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';

/// How a flight mode behaves on this firmware.
enum ModeStatus {
  /// Works as named.
  full,

  /// Selectable, but runs another mode's logic (shown with a caption).
  alias,

  /// Exists in firmware but does nothing useful yet; hidden in the UI.
  placeholder,
}

enum ModeGroup { manual, assisted, autonomous }

final class FlightModeInfo {
  const FlightModeInfo(
    this.number,
    this.name,
    this.label,
    this.group, {
    this.status = ModeStatus.full,
    this.aliasOf,
    this.needsPosition = false,
  });

  /// HEARTBEAT custom_mode / DO_SET_MODE param2.
  final int number;
  final String name;
  final String label;
  final ModeGroup group;
  final ModeStatus status;
  final String? aliasOf;
  final bool needsPosition;

  bool get selectable => status != ModeStatus.placeholder;
}

/// Where the home position comes from.
enum HomeSource { reported, estimated }

/// Everything the GCS may assume about one firmware version.
/// The UI asks the profile; it never hard‑codes vehicle capabilities.
final class FirmwareProfile {
  const FirmwareProfile({
    required this.name,
    required this.modes,
    required this.commands,
    required this.missionCommands,
    required this.persistentParameters,
    required this.parametersClampSilently,
    required this.homeSource,
    required this.calibration,
    required this.onboardLogs,
    required this.motorTest,
    required this.reboot,
    required this.fenceAndRally,
    required this.setCurrentMissionItem,
    required this.messageIntervals,
  });

  final String name;
  final List<FlightModeInfo> modes;

  /// MAV_CMD ids the vehicle executes when sent as COMMAND_LONG/INT.
  final Set<int> commands;

  /// MAV_CMD ids the vehicle executes inside a mission.
  final Set<int> missionCommands;

  final bool persistentParameters;
  final bool parametersClampSilently;
  final HomeSource homeSource;
  final bool calibration;
  final bool onboardLogs;
  final bool motorTest;
  final bool reboot;
  final bool fenceAndRally;
  final bool setCurrentMissionItem;
  final bool messageIntervals;

  FlightModeInfo? mode(int number) {
    for (final m in modes) {
      if (m.number == number) return m;
    }
    return null;
  }

  String modeName(int number) => mode(number)?.label ?? 'Mode $number';

  Iterable<FlightModeInfo> get selectableModes => modes.where((m) => m.selectable);

  bool supportsCommand(int command) => commands.contains(command);
}

/// APX 0.1.x, as established in docs/01_APX_CAPABILITY_MATRIX.md.
const apx01Profile = FirmwareProfile(
  name: 'APX 0.1',
  modes: [
    FlightModeInfo(0, 'STABILIZE', 'Stabilize', ModeGroup.manual),
    FlightModeInfo(2, 'ALT_HOLD', 'Alt Hold', ModeGroup.manual),
    FlightModeInfo(5, 'LOITER', 'Loiter', ModeGroup.assisted, needsPosition: true),
    FlightModeInfo(
      16,
      'POS_HOLD',
      'Pos Hold',
      ModeGroup.assisted,
      status: ModeStatus.alias,
      aliasOf: 'LOITER',
      needsPosition: true,
    ),
    FlightModeInfo(17, 'BRAKE', 'Brake', ModeGroup.assisted, needsPosition: true),
    FlightModeInfo(3, 'AUTO', 'Auto', ModeGroup.autonomous, needsPosition: true),
    FlightModeInfo(4, 'GUIDED', 'Guided', ModeGroup.autonomous, needsPosition: true),
    FlightModeInfo(6, 'RTL', 'Return', ModeGroup.autonomous, needsPosition: true),
    FlightModeInfo(9, 'LAND', 'Land', ModeGroup.autonomous),
    // Hold position only in 0.1.x.
    FlightModeInfo(
      100,
      'AGRI_SPRAY',
      'Agri Spray',
      ModeGroup.autonomous,
      status: ModeStatus.placeholder,
      needsPosition: true,
    ),
    FlightModeInfo(
      101,
      'AGRI_ZIGZAG',
      'Agri ZigZag',
      ModeGroup.autonomous,
      status: ModeStatus.placeholder,
      needsPosition: true,
    ),
  ],
  commands: {
    MavCmd.componentArmDisarm,
    MavCmd.doSetMode,
    MavCmd.navTakeoff,
    MavCmd.navLand,
    MavCmd.doReposition,
    MavCmd.missionStart,
    MavCmd.doChangeSpeed, // horizontal types only
    MavCmd.doSetServo, // aux channels 9–16 only
    MavCmd.doSprayer,
    MavCmd.doMotorTest,
    MavCmd.doSetHome,
    MavCmd.requestMessage, // AUTOPILOT_VERSION only
    MavCmd.requestAutopilotCapabilities,
    // Not listed on purpose: PREFLIGHT_CALIBRATION and DO_PARACHUTE are ACKed
    // ACCEPTED but do nothing. TODO(APX-FW-2): add once implemented.
  },
  missionCommands: {
    MavCmd.navWaypoint,
    MavCmd.navReturnToLaunch,
    MavCmd.navLand,
    MavCmd.navTakeoff,
    MavCmd.conditionChangeAlt,
    MavCmd.conditionYaw,
    MavCmd.doChangeSpeed,
    MavCmd.doSetServo,
    MavCmd.doChangeAltitude,
    MavCmd.doSprayer,
  },
  // TODO(APX-FW-3): parameters are not saved to flash.
  persistentParameters: false,
  parametersClampSilently: true,
  // Streams HOME_POSITION at 1 Hz and takes DO_SET_HOME (APX-FW-4 fixed).
  homeSource: HomeSource.reported,
  calibration: false,
  onboardLogs: false,
  motorTest: true,
  reboot: false,
  // TODO(APX-FW-1): fence/rally requests return the mission; never send them.
  fenceAndRally: false,
  setCurrentMissionItem: false,
  messageIntervals: false,
);

/// A vehicle that isn't recognised as APX: read‑only telemetry, no commands.
const unknownProfile = FirmwareProfile(
  name: 'Unknown autopilot',
  modes: [],
  commands: {},
  missionCommands: {},
  persistentParameters: true,
  parametersClampSilently: false,
  homeSource: HomeSource.estimated,
  calibration: false,
  onboardLogs: false,
  motorTest: true,
  reboot: false,
  fenceAndRally: false,
  setCurrentMissionItem: false,
  messageIntervals: false,
);

/// Firmware semantic version from AUTOPILOT_VERSION.flight_sw_version.
final class FirmwareVersion {
  const FirmwareVersion(this.major, this.minor, this.patch);

  factory FirmwareVersion.fromFlightSw(int v) => FirmwareVersion((v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF);

  final int major, minor, patch;

  @override
  String toString() => '$major.$minor.$patch';
}

/// Decides which profile applies.
FirmwareProfile resolveProfile({
  required int autopilot,
  FirmwareVersion? version,
  required Set<String> parameterNames,
}) {
  // Full capability profile with MAVLink standard modes and commands.
  return apx01Profile;
}
