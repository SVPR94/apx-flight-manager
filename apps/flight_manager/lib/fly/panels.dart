// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../state/connection.dart';
import '../state/units.dart';
import 'instruments.dart';
import 'motion.dart';

/// Speed tape · attitude sphere · altitude tape. Moving parts follow
/// [motion] every frame; wind (slow) comes from the snapshot [s].
class CockpitCluster extends ConsumerWidget {
  const CockpitCluster({super.key, required this.s, required this.motion});
  final VehicleSnapshot s;
  final FlightMotion motion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    final units = ref.watch(unitsProvider);
    return Glass(
      child: RepaintBoundary(
        child: ListenableBuilder(
          listenable: motion,
          builder: (context, _) {
            final heading = motion.heading;
            // A direction means nothing in calm air.
            final windy = !motion.windSpeed.isNaN && motion.windSpeed >= 0.2;
            final windDeg = (windy && !motion.windFromDeg.isNaN) ? motion.windFromDeg : null;

            final displayGs = units.convertSpeed(motion.groundSpeed);
            final displayAlt = units.convertAltitude(motion.altRel);
            final displayClimb = units.convertAltitude(motion.climbRate);

            return SizedBox(
              width: 370,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Tape(
                    title: 'GS ${units.speed.symbol}',
                    value: displayGs,
                    step: units.speed == SpeedUnit.metersPerSecond ? 2 : 5,
                    minValue: 0,
                  ),
                  SizedBox(
                    width: 200,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AttitudeIndicator(
                          rollRad: motion.roll * math.pi / 180,
                          pitchRad: motion.pitch * math.pi / 180,
                          headingDeg: heading,
                          windFromDeg: windDeg,
                        ),
                        SizedBox(
                          width: 200,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 4,
                            children: [
                              Text('HDG', style: AlloyText.label(p.ink2).copyWith(fontSize: 10)),
                              Reading('${(heading.round() % 360).toString().padLeft(3, '0')}°', size: 14),
                              if (!motion.windSpeed.isNaN)
                                Flexible(
                                  child: Text(
                                    windy
                                        ? '· ${units.convertSpeed(motion.windSpeed).toStringAsFixed(1)}${units.speed.symbol} ${motion.windFromDeg.round()}°'
                                        : '· calm',
                                    style: TextStyle(fontSize: 11, color: p.ink2),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tape(
                    title: 'ALT REL ${units.altitude.symbol}',
                    value: displayAlt,
                    step: units.altitude == AltitudeUnit.feet ? 20 : 5,
                    width: 80,
                    trend: displayClimb,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shown while AUTO runs a mission.
class MissionProgress extends StatelessWidget {
  const MissionProgress({super.key, required this.s, required this.mission});
  final VehicleSnapshot s;
  final List<WireMissionItem>? mission;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final total = s.missionTotal;
    final cur = s.missionCurrent;
    final frac = total <= 1 ? 0.0 : (cur.clamp(0, total - 1) / (total - 1));
    double? toGo;
    final m = mission;
    if (m != null && cur >= 0 && cur < m.length && (m[cur].x != 0 || m[cur].y != 0) && s.hasPosition) {
      toGo = distanceMetres(s.lat, s.lon, m[cur].x / 1e7, m[cur].y / 1e7);
    }
    return Glass(
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              cur < 0 ? 'Mission finished' : 'Mission · item $cur of ${total - 1}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: p.hairline,
                color: AlloyPalette.accent,
              ),
            ),
            if (toGo != null) Reading(toGo.toStringAsFixed(0), unit: 'm to item $cur'),
            Text(
              'Hold or a mode change ends AUTO; APX restarts a mission from item 1.',
              style: TextStyle(fontSize: 11, color: p.ink2, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Context‑sensitive actions, all checked against the firmware profile.
class ActionStack extends StatefulWidget {
  const ActionStack({super.key, required this.session, required this.onResult});
  final VehicleSession session;
  final void Function(CommandResult) onResult;

  @override
  State<ActionStack> createState() => _ActionStackState();
}

class _ActionStackState extends State<ActionStack> {
  double _takeoffAlt = 10;

  VehicleSession get _v => widget.session;

  Future<void> _run(Future<CommandResult> Function() action) async {
    final r = await action();
    widget.onResult(r);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final s = _v.telemetry.snapshot;
    final ready = _v.state.value == SessionState.ready;
    final apx = _v.profile.commands.isNotEmpty;

    Widget body;
    if (!ready || !apx) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(
            !ready
                ? (_v.state.value == SessionState.lost ? 'No link — actions paused.' : _v.step.value)
                : 'Connecting to vehicle…',
            style: TextStyle(color: p.ink2),
          ),
          if (!ready)
            Consumer(
              builder: (context, ref, _) => AlloyButton(
                label: 'Disconnect',
                icon: LucideIcons.unplug,
                onPressed: () => ref.read(connectionProvider.notifier).disconnect(),
              ),
            ),
        ],
      );
    } else if (!s.armed) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          SlideToConfirm(
            label: 'Slide to arm',
            icon: LucideIcons.power,
            tone: Tone.caution,
            onConfirmed: () => _run(_v.commands.arm),
          ),
          Text('After arming, take‑off switches the vehicle to Guided.', style: TextStyle(fontSize: 11, color: p.ink2)),
        ],
      );
    } else if (s.altRel.isNaN || s.altRel < 1.5) {
      final missionLoaded = (_v.vehicleMission?.length ?? 0) > 1;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Take‑off altitude',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.ink2),
                ),
              ),
              IconButton(
                tooltip: 'Lower',
                onPressed: _takeoffAlt > 2 ? () => setState(() => _takeoffAlt -= 1) : null,
                icon: const Icon(LucideIcons.minus, size: 16),
              ),
              Reading(_takeoffAlt.toStringAsFixed(0), unit: 'm', size: 15),
              IconButton(
                tooltip: 'Higher',
                onPressed: _takeoffAlt < 120 ? () => setState(() => _takeoffAlt += 1) : null,
                icon: const Icon(LucideIcons.plus, size: 16),
              ),
            ],
          ),
          SlideToConfirm(
            label: 'Slide to take off',
            icon: LucideIcons.arrowUpFromLine,
            onConfirmed: () => _run(() => _v.commands.takeoff(_takeoffAlt)),
          ),
          if (missionLoaded)
            AlloyButton(
              label: 'Start mission (${_v.vehicleMission!.length - 1} items)',
              icon: LucideIcons.play,
              expand: true,
              onPressed: () => _run(_v.commands.startMission),
            ),
          SlideToConfirm(
            label: 'Slide to disarm',
            icon: LucideIcons.power,
            onConfirmed: () => _run(_v.commands.disarm),
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          SlideToConfirm(
            label: 'Slide to return home',
            icon: LucideIcons.house,
            tone: Tone.caution,
            onConfirmed: () => _run(() => _v.commands.setMode(6)),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: AlloyButton(
                  icon: LucideIcons.house,
                  label: 'Return',
                  stacked: true,
                  onPressed: () => _run(() => _v.commands.setMode(6)),
                ),
              ),
              Expanded(
                child: AlloyButton(
                  icon: LucideIcons.planeLanding,
                  label: 'Land',
                  stacked: true,
                  onPressed: () => _run(_v.commands.land),
                ),
              ),
              Expanded(
                child: AlloyButton(
                  icon: LucideIcons.octagonX,
                  label: 'Brake',
                  stacked: true,
                  onPressed: () => _run(() => _v.commands.setMode(17)),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Glass(
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            body,
          ],
        ),
      ),
    );
  }
}

/// Converts a vehicle mission to map points, skipping the seq‑0 home marker
/// and items without coordinates. RTL returns to [home].
List<(int seq, double lat, double lon, int command)> missionPoints(
  List<WireMissionItem> items,
  double homeLat,
  double homeLon,
) {
  final out = <(int, double, double, int)>[];
  for (final i in items.skip(1)) {
    if (i.command == MavCmd.navReturnToLaunch && !homeLat.isNaN) {
      out.add((i.seq, homeLat, homeLon, i.command));
    } else if (i.x != 0 || i.y != 0) {
      out.add((i.seq, i.x / 1e7, i.y / 1e7, i.command));
    }
  }
  return out;
}
