// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';

import 'channel.dart';
import 'commands.dart';
import 'mission_transfer.dart';
import 'parameters.dart';
import 'profile.dart';
import 'telemetry.dart';

enum SessionState {
  /// Link open, no vehicle heartbeat yet.
  waiting,

  /// Vehicle found; reading version, parameters and mission.
  initializing,

  ready,

  /// No heartbeat for [VehicleSession.heartbeatTimeout].
  lost,
}

/// Everything known about, and every way to talk to, one vehicle on a link.
final class VehicleSession {
  VehicleSession(
    this.link, {
    MavFrameWriter? writer,
    this.heartbeatTimeout = const Duration(milliseconds: 3500),
    this.downloadMissionOnConnect = true,
  }) : writer = writer ?? MavFrameWriter();

  final Link link;
  final MavFrameWriter writer;
  final Duration heartbeatTimeout;
  final bool downloadMissionOnConnect;

  final state = Signal(SessionState.waiting);

  /// Human‑readable initialisation step, for the connect sheet.
  final step = Signal<String>('Waiting for a vehicle heartbeat');

  final telemetry = TelemetryStore();
  FirmwareProfile profile = unknownProfile;
  FirmwareVersion? version;

  /// Mission as last read from or written to the vehicle.
  List<WireMissionItem>? vehicleMission;

  late VehicleChannel channel;
  late CommandService commands;
  late ParameterService parameters;
  late MissionTransfer missions;

  final _rebootedParams = StreamController<void>.broadcast();

  /// Fires after a vehicle reboot once parameters have been re‑read.
  /// TODO(APX-FW-3): APX resets parameters on reboot; the UI offers to
  /// re‑apply the saved profile when this fires.
  Stream<void> get parametersResetByReboot => _rebootedParams.stream;

  StreamSubscription<MavlinkFrame>? _discovery;
  StreamSubscription<MavMessage>? _telemetrySub;
  Timer? _gcsHeartbeat;
  Timer? _watchdog;
  bool _bound = false;

  /// A vehicle has answered; [channel], [commands], [parameters] and
  /// [missions] exist only from then on.
  bool get isBound => _bound;

  /// Opens the link (if needed) and waits for a vehicle.
  Future<void> start() async {
    _discovery = link.frames.listen(_onFrame);
    _gcsHeartbeat = Timer.periodic(const Duration(seconds: 1), (_) => _sendGcsHeartbeat());
    if (link.state.value != LinkState.up) await link.open();
    _sendGcsHeartbeat();
  }

  void _sendGcsHeartbeat() => link.send(
    writer.encode(
      const Heartbeat(
        type: MavType.gcs,
        autopilot: MavAutopilot.invalid,
        systemStatus: MavState.active,
        mavlinkVersion: 3,
      ),
    ),
  );

  void _onFrame(MavlinkFrame f) {
    if (_bound) return;
    final m = f.message;
    if (m is! Heartbeat || m.type == MavType.gcs || m.autopilot == MavAutopilot.invalid) return;
    _bind(f.systemId, f.componentId);
    // The discovering heartbeat arrived before the telemetry subscription;
    // apply it so identity is known before the profile is resolved.
    telemetry.apply(m);
  }

  void _bind(int sysid, int compid) {
    _bound = true;
    channel = LinkChannel(link, writer, targetSystem: sysid, targetComponent: compid);
    commands = CommandService(channel, profile);
    parameters = ParameterService(channel);
    missions = MissionTransfer(channel);
    _telemetrySub = channel.messages.listen(telemetry.apply);
    telemetry.reboots.listen((_) => _afterReboot());
    _watchdog = Timer.periodic(const Duration(milliseconds: 250), (_) => _checkHeartbeat());
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    state.value = SessionState.initializing;

    step.value = 'Reading firmware version';
    final av = Awaiter<AutopilotVersion>(channel.messages);
    await channel.send(
      CommandLong(
        targetSystem: channel.targetSystem,
        targetComponent: channel.targetComponent,
        command: MavCmd.requestMessage,
        param1: AutopilotVersion.msgId.toDouble(),
      ),
    );
    final got = await av.wait(const Duration(seconds: 2));
    await av.cancel();
    if (got != null) version = FirmwareVersion.fromFlightSw(got.flightSwVersion);

    step.value = 'Downloading parameters';
    final p = await parameters.refresh();
    if (p.state != ParamLoadState.complete) {
      step.value = p.message ?? 'Parameter download failed';
    }

    profile = resolveProfile(
      autopilot: telemetry.snapshot.autopilot,
      version: version,
      parameterNames: parameters.names,
    );
    commands.profile = profile;

    if (downloadMissionOnConnect && profile != unknownProfile) {
      step.value = 'Reading mission';
      try {
        vehicleMission = await missions.download();
      } on TransferException catch (e) {
        step.value = 'Mission: ${e.message}';
      }
    }
    step.value = 'Ready';
    state.value = SessionState.ready;
  }

  void _checkHeartbeat() {
    final last = telemetry.snapshot.lastHeartbeat;
    if (last == null) return;
    final fresh = DateTime.now().difference(last) < heartbeatTimeout;
    if (!fresh && state.value != SessionState.lost) {
      state.value = SessionState.lost;
    } else if (fresh && state.value == SessionState.lost) {
      state.value = SessionState.ready;
    }
  }

  Future<void> _afterReboot() async {
    if (state.value == SessionState.initializing) return;
    // TODO(APX-FW-3): parameters and the mission are gone after a reboot.
    vehicleMission = null;
    step.value = 'Vehicle restarted — re‑reading parameters';
    await parameters.refresh();
    step.value = 'Ready';
    _rebootedParams.add(null);
  }

  Future<void> dispose() async {
    _gcsHeartbeat?.cancel();
    _watchdog?.cancel();
    await _discovery?.cancel();
    await _telemetrySub?.cancel();
    if (_bound) await parameters.dispose();
    await telemetry.dispose();
    await _rebootedParams.close();
  }
}
