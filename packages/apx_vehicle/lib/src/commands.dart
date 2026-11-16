// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';

import 'channel.dart';
import 'profile.dart';

/// Outcome of a COMMAND_LONG / COMMAND_INT exchange.
final class CommandResult {
  const CommandResult(this.command, this.result, {this.attempts = 1});
  const CommandResult.timeout(this.command, {this.attempts = 0}) : result = -1;
  const CommandResult.unsupportedByProfile(this.command) : result = MavResult.unsupported, attempts = 0;

  final int command;

  /// MAV_RESULT, or −1 when no ACK arrived.
  final int result;
  final int attempts;

  bool get accepted => result == MavResult.accepted;
  bool get timedOut => result == -1;

  String get message => switch (result) {
    -1 => 'No reply from the vehicle',
    MavResult.accepted => 'Done',
    MavResult.temporarilyRejected => 'Not possible right now',
    MavResult.denied => 'Refused by the vehicle',
    MavResult.unsupported => 'Not supported by this firmware',
    MavResult.failed => 'Failed',
    MavResult.inProgress => 'In progress',
    _ => 'Result $result',
  };

  @override
  String toString() => '${MavCmd.names[command] ?? command}: $message';
}

/// Sends commands and waits for their COMMAND_ACK.
final class CommandService {
  CommandService(this._channel, this.profile, {this.timeout = const Duration(milliseconds: 1500), this.attempts = 3});

  final VehicleChannel _channel;
  FirmwareProfile profile;
  final Duration timeout;
  final int attempts;

  /// Commands already waiting for an ACK; a second identical request joins it.
  final _inFlight = <int, Future<CommandResult>>{};

  Future<CommandResult> long(
    int command, {
    double p1 = 0,
    double p2 = 0,
    double p3 = 0,
    double p4 = 0,
    double p5 = 0,
    double p6 = 0,
    double p7 = 0,
  }) {
    if (!profile.supportsCommand(command)) {
      return Future.value(CommandResult.unsupportedByProfile(command));
    }
    return _inFlight[command] ??=
        _exchange(
          command,
          (confirmation) => CommandLong(
            targetSystem: _channel.targetSystem,
            targetComponent: _channel.targetComponent,
            command: command,
            confirmation: confirmation,
            param1: p1,
            param2: p2,
            param3: p3,
            param4: p4,
            param5: p5,
            param6: p6,
            param7: p7,
          ),
        ).whenComplete(() {
          // Block body on purpose: returning the removed future from
          // whenComplete would make this future wait on itself.
          _inFlight.remove(command);
        });
  }

  /// COMMAND_INT: positions travel as degrees × 1e7 integers, exact to about
  /// a centimetre (COMMAND_LONG's 32‑bit floats are only ~1 m at longitude 74°).
  Future<CommandResult> int_(
    int command, {
    int frame = MavFrame.global,
    double p1 = 0,
    double p2 = 0,
    double p3 = 0,
    double p4 = 0,
    double lat = 0,
    double lon = 0,
    double z = 0,
  }) {
    if (!profile.supportsCommand(command)) {
      return Future.value(CommandResult.unsupportedByProfile(command));
    }
    return _inFlight[command] ??=
        _exchange(
          command,
          (_) => CommandInt(
            targetSystem: _channel.targetSystem,
            targetComponent: _channel.targetComponent,
            frame: frame,
            command: command,
            param1: p1,
            param2: p2,
            param3: p3,
            param4: p4,
            x: (lat * 1e7).round(),
            y: (lon * 1e7).round(),
            z: z,
          ),
        ).whenComplete(() {
          _inFlight.remove(command);
        });
  }

  Future<CommandResult> _exchange(int command, MavMessage Function(int confirmation) build) async {
    for (var i = 0; i < attempts; i++) {
      final ack = Awaiter<CommandAck>(_channel.messages, (a) => a.command == command);
      await _channel.send(build(i));
      final got = await ack.wait(timeout);
      await ack.cancel();
      if (got != null) return CommandResult(command, got.result, attempts: i + 1);
    }
    return CommandResult.timeout(command, attempts: attempts);
  }

  // ---- APX actions (each checked against the profile) ----

  Future<CommandResult> arm() => long(MavCmd.componentArmDisarm, p1: 1);

  /// [force] overrides APX's "not landed" check (param2 = 21196).
  Future<CommandResult> disarm({bool force = false}) => long(MavCmd.componentArmDisarm, p1: 0, p2: force ? 21196 : 0);

  Future<CommandResult> setMode(int customMode) =>
      long(MavCmd.doSetMode, p1: MavModeFlag.customModeEnabled.toDouble(), p2: customMode.toDouble());

  /// Requires armed; switches to GUIDED (standard for APX) and climbs to [relativeAltM].
  Future<CommandResult> takeoff(double relativeAltM) async {
    final guidedMode = profile.modes.cast<FlightModeInfo?>().firstWhere(
      (m) => m?.name.toUpperCase() == 'GUIDED',
      orElse: () => null,
    );
    if (guidedMode != null) {
      await setMode(guidedMode.number);
    }
    return long(MavCmd.navTakeoff, p7: relativeAltM);
  }

  Future<CommandResult> land() => long(MavCmd.navLand);

  /// Requires armed; APX switches to AUTO and runs from item 1.
  Future<CommandResult> startMission() => long(MavCmd.missionStart);

  /// Horizontal speed only (APX rejects climb/descent types as a command).
  Future<CommandResult> changeSpeed(double metresPerSecond) => long(MavCmd.doChangeSpeed, p1: 1, p2: metresPerSecond);

  Future<CommandResult> sprayer(bool on) => long(MavCmd.doSprayer, p1: on ? 1 : 0);

  /// Runs a motor test (MAV_CMD_DO_MOTOR_TEST / 209).
  /// [motorIndex] is 1-based (1..N).
  /// [throttlePercent] is 0..100%.
  /// [timeoutSec] is duration in seconds.
  /// [motorCount] is number of motors to test in sequence (1 for single motor).
  Future<CommandResult> motorTest({
    required int motorIndex,
    double throttlePercent = 10,
    double timeoutSec = 2,
    int motorCount = 1,
    int order = 0,
  }) =>
      long(
        MavCmd.doMotorTest,
        p1: motorIndex.toDouble(),
        p2: 0, // MOTOR_TEST_THROTTLE_PERCENT
        p3: throttlePercent,
        p4: timeoutSec,
        p5: motorCount.toDouble(),
        p6: order.toDouble(),
      );

  /// Sets the vehicle home position, where RTL returns (MAV_CMD_DO_SET_HOME).
  /// [useCurrentPosition] takes the vehicle's own position. Otherwise home goes
  /// to [lat]/[lon], sent as COMMAND_INT so it lands exactly; an unknown
  /// [altMsl] (NaN) keeps the vehicle's current home altitude.
  Future<CommandResult> setHome({
    bool useCurrentPosition = true,
    double lat = 0,
    double lon = 0,
    double altMsl = double.nan,
  }) => useCurrentPosition
      ? long(MavCmd.doSetHome, p1: 1)
      : int_(MavCmd.doSetHome, lat: lat, lon: lon, z: altMsl);

  /// APX drives aux outputs 9–16; 1–8 are motors and get overwritten.
  Future<CommandResult> setAuxServo(int channel, int pwm) {
    if (channel < 9 || channel > 16) {
      throw RangeError.range(channel, 9, 16, 'channel', 'APX drives aux channels 9–16 only');
    }
    return long(MavCmd.doSetServo, p1: channel.toDouble(), p2: pwm.clamp(800, 2200).toDouble());
  }

  Future<CommandResult> requestAutopilotVersion() => long(MavCmd.requestMessage, p1: AutopilotVersion.msgId.toDouble());

  /// Guided "fly here". Uses SET_POSITION_TARGET_GLOBAL_INT rather than
  /// DO_REPOSITION: APX converts COMMAND_INT lat/lon through float32 (~1 m
  /// error) and reads DO_REPOSITION altitude as AMSL. There is no ACK; the
  /// caller watches the vehicle. Only acts while in GUIDED.
  Future<void> guidedGoto(double lat, double lon, double relativeAltM) => _channel.send(
    SetPositionTargetGlobalInt(
      targetSystem: _channel.targetSystem,
      targetComponent: _channel.targetComponent,
      coordinateFrame: MavFrame.globalRelativeAltInt,
      typeMask:
          PositionTargetTypemask.vxIgnore |
          PositionTargetTypemask.vyIgnore |
          PositionTargetTypemask.vzIgnore |
          PositionTargetTypemask.axIgnore |
          PositionTargetTypemask.ayIgnore |
          PositionTargetTypemask.azIgnore |
          PositionTargetTypemask.yawIgnore |
          PositionTargetTypemask.yawRateIgnore,
      latInt: (lat * 1e7).round(),
      lonInt: (lon * 1e7).round(),
      alt: relativeAltM,
    ),
  );
}
