// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_mission/apx_mission.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/fields.dart';
import '../design/tokens.dart';
import '../map/map_dialogs.dart';
import '../plan/plan_panel.dart';
import '../state/connection.dart';
import '../state/payloads.dart';
import '../state/vehicle_params.dart';
import 'failsafe_page.dart';
import 'motor_diagram.dart';
import 'param_field.dart';
import 'sensor_calibration_page.dart';
import '../shell/developer_page.dart';

const _cms = 0.01; // cm, cm/s → m, m/s

/// Curated settings pages. Every name here exists in APX 0.1's parameter
/// table (checked by a test against the generated metadata).
final vehicleSections = <(String, IconData, String?, List<ParamView>)>[
  (
    'Sprayer',
    LucideIcons.sprayCan,
    'The pump runs in proportion to ground speed while spraying (DO_SPRAYER), and stops below the minimum speed.',
    const [
      ParamView('SPRAY_ENABLE', 'Sprayer', options: {0: 'Disabled', 1: 'Enabled'}),
      ParamView('SPRAY_PUMP_RATE', 'Pump rate', unit: '% per m/s'),
      ParamView('SPRAY_PUMP_MIN', 'Minimum pump', unit: '%'),
      ParamView('SPRAY_SPEED_MIN', 'Spray above', unit: 'm/s', scale: _cms, decimals: 2),
      ParamView('SPRAY_SPINNER', 'Spinner PWM while spraying', unit: 'µs', decimals: 0),
      ParamView('SPRAY_PWM_MIN', 'Pump PWM off', unit: 'µs', decimals: 0),
      ParamView('SPRAY_PWM_MAX', 'Pump PWM full', unit: 'µs', decimals: 0),
      ParamView('SPRAY_PUMP_CH', 'Pump output', decimals: 0),
      ParamView('SPRAY_SPIN_CH', 'Spinner output', decimals: 0),
    ],
  ),
  (
    'Mission & navigation',
    LucideIcons.route,
    'How AUTO and GUIDED fly between points.',
    const [
      ParamView('WPNAV_SPEED', 'Cruise speed', unit: 'm/s', scale: _cms),
      ParamView('WPNAV_ACCEL', 'Acceleration', unit: 'm/s²', scale: _cms),
      ParamView('WPNAV_SPEED_UP', 'Climb speed', unit: 'm/s', scale: _cms),
      ParamView('WPNAV_SPEED_DN', 'Descent speed', unit: 'm/s', scale: _cms),
      ParamView(
        'WPNAV_RADIUS',
        'Waypoint radius',
        unit: 'm',
        scale: _cms,
        help: 'Arrival radius and how far a corner may be cut',
      ),
      ParamView('WPNAV_JERK', 'Jerk limit', unit: 'm/s³'),
      ParamView('WPNAV_BLEND', 'Corner shape', options: {0: 'Circular arc', 1: 'Smooth blend'}),
      ParamView(
        'WP_YAW_BEHAVIOR',
        'Heading in AUTO',
        options: {
          0: 'Keep heading',
          1: 'Face next waypoint',
          2: 'Face next waypoint (not RTL)',
          3: 'Along course',
          4: 'Fixed',
        },
      ),
      ParamView('AUTO_YAW_HEAD', 'Fixed heading', unit: '°', help: '−1 = heading when AUTO starts'),
      ParamView('LOIT_SPEED', 'Loiter speed', unit: 'm/s', scale: _cms),
      ParamView('ANGLE_MAX', 'Max lean angle', unit: '°', scale: 0.01),
      ParamView('BRAKE_ACCEL', 'Brake deceleration', unit: 'm/s²', scale: _cms),
    ],
  ),
  (
    'Landing & return',
    LucideIcons.planeLanding,
    null,
    const [
      ParamView('RTL_ALT', 'Return altitude', unit: 'm', scale: _cms),
      ParamView('LAND_SPEED', 'Final descent speed', unit: 'm/s', scale: _cms, decimals: 2),
      ParamView(
        'LAND_SPEED_HIGH',
        'Descent speed above slow‑down height',
        unit: 'm/s',
        scale: _cms,
        help: '0 = climb/descent speed',
      ),
      ParamView('LAND_ALT_LOW', 'Slow‑down height', unit: 'm', scale: _cms),
      ParamView('LAND_REPOS_SPEED', 'Reposition speed while landing', unit: 'm/s', scale: _cms),
      ParamView('DISARM_DELAY', 'Auto‑disarm after landing', unit: 's', help: '0 = off'),
    ],
  ),
  (
    'Battery & safety',
    LucideIcons.batteryMedium,
    'APX 0.1 stores these but does not act on them yet: this app raises the battery alerts from these thresholds.',
    const [
      ParamView('BATT_CAPACITY', 'Battery capacity', unit: 'mAh', decimals: 0),
      ParamView('BATT_LOW_VOLT', 'Low voltage', unit: 'V', decimals: 2),
      ParamView('BATT_CRT_VOLT', 'Critical voltage', unit: 'V', decimals: 2),
      ParamView('BATT_MONITOR', 'Battery monitor', decimals: 0),
      ParamView('FS_THR_ENABLE', 'Throttle failsafe', decimals: 0),
      ParamView('FS_GCS_ENABLE', 'GCS failsafe', decimals: 0),
      ParamView('ARMING_CHECK', 'Arming checks', options: {0: 'Off', 1: 'On'}),
    ],
  ),
  (
    'Frame & motors',
    LucideIcons.fan,
    null,
    const [
      ParamView('FRAME_CLASS', 'Frame class', decimals: 0),
      ParamView('FRAME_TYPE', 'Frame type', decimals: 0),
      ParamView('MOT_SPIN_ARM', 'Idle spin when armed', unit: 'fraction', decimals: 2),
      ParamView('MOT_THST_HOVER', 'Hover thrust (learned)', unit: 'fraction', decimals: 2),
      ParamView('PILOT_SPEED_UP', 'Pilot climb speed', unit: 'm/s', scale: _cms),
      ParamView('PILOT_SPEED_DN', 'Pilot descent speed', unit: 'm/s', scale: _cms),
    ],
  ),
  (
    'Tuning',
    LucideIcons.activity,
    'Controller gains. Change in small steps and test‑fly; values reset on reboot in APX 0.1.',
    const [
      ParamView('ATC_RAT_RLL_P', 'Roll rate P', decimals: 4),
      ParamView('ATC_RAT_RLL_I', 'Roll rate I', decimals: 4),
      ParamView('ATC_RAT_RLL_D', 'Roll rate D', decimals: 4),
      ParamView('ATC_RAT_PIT_P', 'Pitch rate P', decimals: 4),
      ParamView('ATC_RAT_PIT_I', 'Pitch rate I', decimals: 4),
      ParamView('ATC_RAT_PIT_D', 'Pitch rate D', decimals: 4),
      ParamView('ATC_RAT_YAW_P', 'Yaw rate P', decimals: 4),
      ParamView('ATC_RAT_YAW_I', 'Yaw rate I', decimals: 4),
      ParamView('ATC_ANG_RLL_P', 'Roll angle P', decimals: 2),
      ParamView('ATC_ANG_PIT_P', 'Pitch angle P', decimals: 2),
      ParamView('ATC_ANG_YAW_P', 'Yaw angle P', decimals: 2),
      ParamView('ATC_RATE_R_MAX', 'Max roll rate', unit: '°/s', decimals: 0),
      ParamView('ATC_RATE_P_MAX', 'Max pitch rate', unit: '°/s', decimals: 0),
      ParamView('ATC_RATE_Y_MAX', 'Max yaw rate', unit: '°/s', decimals: 0),
      ParamView('PSC_POSXY_P', 'Position P', decimals: 2),
      ParamView('PSC_VELXY_P', 'Velocity P', decimals: 2),
      ParamView('PSC_VELXY_I', 'Velocity I', decimals: 2),
      ParamView('PSC_VELXY_D', 'Velocity D', decimals: 2),
      ParamView('PSC_POSZ_P', 'Altitude P', decimals: 2),
      ParamView('PSC_VELZ_P', 'Climb rate P', decimals: 2),
      ParamView('PSC_VELZ_I', 'Climb rate I', decimals: 2),
      ParamView('PSC_VELZ_D', 'Climb rate D', decimals: 3),
    ],
  ),
];

/// Vehicle setup: payloads, curated settings and all parameters.
class VehicleView extends ConsumerStatefulWidget {
  const VehicleView({super.key});

  @override
  ConsumerState<VehicleView> createState() => _VehicleViewState();
}

class _VehicleViewState extends ConsumerState<VehicleView> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final pages = <(String, IconData)>[
      ('Overview', LucideIcons.gauge),
      ('Payloads', LucideIcons.plug),
      ('Sensor calibration', LucideIcons.compass),
      ('Failsafes & safety', LucideIcons.shieldAlert),
      for (final s in vehicleSections) (s.$1, s.$2),
      ('Flight modes', LucideIcons.layoutGrid),
      ('Developer diagnostics', LucideIcons.code),
      ('All parameters', LucideIcons.list),
    ];
    return ColoredBox(
      color: p.plate,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 230,
            child: Material(
              color: p.plate,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: Text('Vehicle', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  ),
                  for (final (i, (label, icon)) in pages.indexed)
                    ListTile(
                      dense: true,
                      selected: _section == i,
                      selectedTileColor: p.accentBg,
                      selectedColor: p.accentInk,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Alloy.radiusControl)),
                      leading: Icon(icon, size: 18),
                      title: Text(label),
                      onTap: () => setState(() => _section = i),
                    ),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: p.hairline),
          Expanded(
            child: Material(
              color: p.plate,
              // All parameters scrolls itself so its long list can be lazy.
              child: _section == pages.length - 1
                  ? const _AllParams()
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: switch (_section) {
                            0 => const _Overview(),
                            1 => const _PayloadsPage(),
                            2 => const SensorCalibrationPage(),
                            3 => const FailsafePage(),
                            final i when i - 4 < vehicleSections.length => _ParamsSection(vehicleSections[i - 4]),
                            final i when i == pages.length - 3 => const _FlightModes(),
                            final i when i == pages.length - 2 => const DeveloperSection(),
                            _ => const _AllParams(),
                          },
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedsVehicle extends StatelessWidget {
  const _NeedsVehicle();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: context.alloy.cautionBg, borderRadius: BorderRadius.circular(Alloy.radiusControl)),
    child: Text(
      'Connect to the vehicle to read and change its settings.',
      style: TextStyle(color: context.alloy.cautionInk),
    ),
  );
}

/// APX 0.1 keeps parameters in RAM only.
// TODO(APX-FW-3): remove once APX persists parameters.
class _NotPersisted extends StatelessWidget {
  const _NotPersisted();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: context.alloy.cautionBg, borderRadius: BorderRadius.circular(Alloy.radiusControl)),
    child: Text(
      'APX 0.1 does not save parameters: changes last until the vehicle reboots. '
      'Save them to a file under All parameters and apply the file after each power‑up.',
      style: TextStyle(color: context.alloy.cautionInk, fontSize: 12),
    ),
  );
}

class _ParamsSection extends ConsumerWidget {
  const _ParamsSection(this.section);
  final (String, IconData, String?, List<ParamView>) section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final isFrameSection = section.$1 == 'Frame & motors';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conn == null) const _NeedsVehicle() else const _NotPersisted(),
        if (isFrameSection) ...[const _FrameAndMotorsVisualizer(), const SizedBox(height: 16)],
        SectionCard(title: section.$1, subtitle: section.$3, child: ParamGrid(section.$4)),
      ],
    );
  }
}

class _FrameAndMotorsVisualizer extends ConsumerStatefulWidget {
  const _FrameAndMotorsVisualizer();

  @override
  ConsumerState<_FrameAndMotorsVisualizer> createState() => _FrameAndMotorsVisualizerState();
}

class _FrameAndMotorsVisualizerState extends ConsumerState<_FrameAndMotorsVisualizer> {
  FrameClass _frameClass = FrameClass.quad;
  FrameType _frameType = FrameType.x;
  int? _testingMotor;
  bool _testingAll = false;
  bool _safetySwitchArmed = false;
  double _testThrottlePercent = 10;
  double _testDurationSec = 2;

  Future<void> _runMotorTest(int motorNumber) async {
    if (!_safetySwitchArmed) {
      notify(context, 'Safety Lock: Confirm propellers are removed before running motor tests.');
      return;
    }
    final conn = ref.read(connectionProvider);
    if (conn == null || conn.session.isBound != true) {
      notify(context, 'Vehicle is not connected');
      return;
    }
    setState(() => _testingMotor = motorNumber);
    try {
      final res = await conn.session.commands.motorTest(
        motorIndex: motorNumber,
        throttlePercent: _testThrottlePercent,
        timeoutSec: _testDurationSec,
      );
      if (!mounted) return;
      if (!res.accepted) {
        notify(context, 'Motor $motorNumber test: ${res.message}');
      }
    } catch (e) {
      if (mounted) notify(context, 'Motor test failed: $e');
    } finally {
      // Keep highlighted on the visual diagram for the test duration
      await Future<void>.delayed(Duration(milliseconds: (_testDurationSec * 1000).toInt()));
      if (mounted && _testingMotor == motorNumber && !_testingAll) {
        setState(() => _testingMotor = null);
      }
    }
  }

  Future<void> _testAllMotorsSequence() async {
    if (!_safetySwitchArmed) {
      notify(context, 'Safety Lock: Confirm propellers are removed before running motor tests.');
      return;
    }
    final conn = ref.read(connectionProvider);
    if (conn == null || conn.session.isBound != true) {
      notify(context, 'Vehicle is not connected');
      return;
    }
    setState(() => _testingAll = true);
    final motors = getMotorLayout(_frameClass, _frameType);
    try {
      for (final m in motors) {
        if (!_testingAll || !mounted) break;
        setState(() => _testingMotor = m.number);
        await conn.session.commands.motorTest(
          motorIndex: m.number,
          throttlePercent: _testThrottlePercent,
          timeoutSec: _testDurationSec,
        );
        await Future<void>.delayed(Duration(milliseconds: (_testDurationSec * 1000).toInt() + 500));
      }
    } finally {
      if (mounted) {
        setState(() {
          _testingAll = false;
          _testingMotor = null;
        });
      }
    }
  }

  void _stopMotorTest() {
    setState(() {
      _testingAll = false;
      _testingMotor = null;
    });
    final conn = ref.read(connectionProvider);
    if (conn != null && conn.session.isBound == true) {
      conn.session.commands.motorTest(motorIndex: 1, throttlePercent: 0, timeoutSec: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final conn = ref.watch(connectionProvider);
    ref.watch(frameTickProvider);
    final params = conn?.session.isBound == true ? conn!.session.parameters.all : null;

    final vehicleType = conn?.session.telemetry.snapshot.vehicleType;
    if (vehicleType == MavType.hexarotor) {
      _frameClass = FrameClass.hexa;
    } else if (vehicleType == MavType.octorotor) {
      _frameClass = FrameClass.octa;
    } else if (vehicleType == MavType.quadrotor) {
      _frameClass = FrameClass.quad;
    }

    if (params != null) {
      final fcVal = params['FRAME_CLASS']?.value.toInt();
      if (fcVal != null) {
        if (fcVal == 1) {
          if (vehicleType == null ||
              vehicleType == MavType.quadrotor ||
              (vehicleType != MavType.hexarotor && vehicleType != MavType.octorotor)) {
            _frameClass = FrameClass.quad;
          }
        } else if (fcVal == 2) {
          _frameClass = FrameClass.hexa;
        } else if (fcVal == 3) {
          _frameClass = FrameClass.octa;
        }
      }
      final ftVal = params['FRAME_TYPE']?.value.toInt();
      if (ftVal != null) {
        _frameType = ftVal == 0 ? FrameType.plus : FrameType.x;
      }
    }

    final motors = getMotorLayout(_frameClass, _frameType);

    return SectionCard(
      title: 'Visual Frame & Motor Layout',
      subtitle:
          'Airframe layout with motor numbering, rotation arrows (CW/CCW), animated propellers, and motor testing.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MotorLayoutDiagram(
                frameClass: _frameClass,
                frameType: _frameType,
                highlightedMotor: _testingMotor,
                size: 290,
                onMotorSelected: (motorNum) => _runMotorTest(motorNum),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Frame Class',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink2),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<FrameClass>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: FrameClass.quad, label: Text('Quad (4)')),
                        ButtonSegment(value: FrameClass.hexa, label: Text('Hexa (6)')),
                        ButtonSegment(value: FrameClass.octa, label: Text('Octa (8)')),
                      ],
                      selected: {_frameClass},
                      onSelectionChanged: (v) {
                        final chosen = v.single;
                        setState(() => _frameClass = chosen);
                        if (conn?.session.isBound == true) {
                          conn!.session.parameters.set('FRAME_CLASS', chosen.paramValue.toDouble());
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Frame Configuration',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink2),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<FrameType>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: FrameType.x, label: Text('X Layout')),
                        ButtonSegment(value: FrameType.plus, label: Text('+ (Plus) Layout')),
                      ],
                      selected: {_frameType},
                      onSelectionChanged: (v) {
                        final chosen = v.single;
                        setState(() => _frameType = chosen);
                        if (conn?.session.isBound == true) {
                          conn!.session.parameters.set('FRAME_TYPE', chosen.paramValue.toDouble());
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.pill,
                        borderRadius: BorderRadius.circular(Alloy.radiusControl),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: p.okBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: p.okInk),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Green = CCW (Counter-Clockwise)',
                                style: TextStyle(fontSize: 11, color: p.okInk, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: p.warningBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: p.warningInk),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Orange = CW (Clockwise)',
                                style: TextStyle(fontSize: 11, color: p.warningInk, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Motors numbered 1..${motors.length} map to Flight Controller PWM Outputs 1..${motors.length}. Tap any motor on the diagram to test.',
                            style: TextStyle(fontSize: 11, color: p.ink2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          // --- Motor Test Panel ---
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.canvas.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Alloy.radiusControl),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.fan, size: 18, color: p.accentInk),
                    const SizedBox(width: 8),
                    Text(
                      'Motor Test & Bench Spin Check',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                    ),
                    const Spacer(),
                    if (_testingMotor != null || _testingAll)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.warningBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.warningInk),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 2, color: p.warningInk),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _testingMotor != null ? 'Spinning Motor $_testingMotor...' : 'Testing All...',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.warningInk),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _safetySwitchArmed
                        ? p.warningBg.withValues(alpha: 0.35)
                        : AlloyPalette.critical.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _safetySwitchArmed
                          ? p.warningInk.withValues(alpha: 0.7)
                          : AlloyPalette.critical.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _safetySwitchArmed ? LucideIcons.shieldAlert : LucideIcons.triangleAlert,
                            size: 20,
                            color: _safetySwitchArmed ? p.warningInk : AlloyPalette.critical,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DANGER: REMOVE ALL PROPELLERS BEFORE MOTOR TEST',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                    color: _safetySwitchArmed ? p.warningInk : AlloyPalette.critical,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Spinning motors with propellers attached is extremely dangerous! If minimum motor spin is high or motor sequence differs, the drone can violently flip over or cause severe lacerations. Always detach all propellers before bench testing.',
                                  style: TextStyle(fontSize: 11.5, color: p.ink2, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _safetySwitchArmed ? LucideIcons.checkCircle2 : LucideIcons.lock,
                                size: 16,
                                color: _safetySwitchArmed ? p.okInk : p.ink2,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _safetySwitchArmed
                                    ? 'Propellers removed confirmation verified (Armed for test)'
                                    : 'Safety Switch: Confirm propellers are removed to unlock controls',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _safetySwitchArmed ? p.okInk : p.ink,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: _safetySwitchArmed,
                            activeThumbColor: p.warningInk,
                            onChanged: _testingAll || _testingMotor != null
                                ? null
                                : (val) => setState(() => _safetySwitchArmed = val),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Slider controls for throttle and duration
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Throttle Power',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink2),
                              ),
                              Text(
                                '${_testThrottlePercent.toInt()}%',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.accentInk),
                              ),
                            ],
                          ),
                          Slider(
                            value: _testThrottlePercent,
                            min: 5,
                            max: 30,
                            divisions: 25,
                            label: '${_testThrottlePercent.toInt()}%',
                            onChanged: !_safetySwitchArmed || _testingAll || _testingMotor != null
                                ? null
                                : (v) => setState(() => _testThrottlePercent = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Duration',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink2),
                              ),
                              Text(
                                '${_testDurationSec.toStringAsFixed(1)} s',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.accentInk),
                              ),
                            ],
                          ),
                          Slider(
                            value: _testDurationSec,
                            min: 1,
                            max: 5,
                            divisions: 8,
                            label: '${_testDurationSec.toStringAsFixed(1)}s',
                            onChanged: !_safetySwitchArmed || _testingAll || _testingMotor != null
                                ? null
                                : (v) => setState(() => _testDurationSec = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Buttons row: individual motors and Test All
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final m in motors)
                      OutlinedButton.icon(
                        icon: Icon(
                          _testingMotor == m.number ? LucideIcons.loader : LucideIcons.play,
                          size: 13,
                          color: _testingMotor == m.number
                              ? const Color(0xFF00E5FF)
                              : (m.isCw ? p.warningInk : p.okInk),
                        ),
                        label: Text(
                          'Motor ${m.number} (${m.isCw ? "CW" : "CCW"})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _testingMotor == m.number ? const Color(0xFF00E5FF) : p.ink,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _testingMotor == m.number ? const Color(0xFF00E5FF) : p.hairline,
                            width: _testingMotor == m.number ? 1.8 : 1.0,
                          ),
                          backgroundColor: _testingMotor == m.number
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                              : p.plate,
                        ),
                        onPressed: (!_safetySwitchArmed || _testingAll || _testingMotor != null) ? null : () => _runMotorTest(m.number),
                      ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      icon: Icon(_testingAll ? LucideIcons.loader : LucideIcons.listOrdered, size: 14),
                      label: Text(_testingAll ? 'Testing Sequence...' : 'Test All in Sequence'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AlloyPalette.accent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: (!_safetySwitchArmed || _testingAll || _testingMotor != null) ? null : _testAllMotorsSequence,
                    ),
                    if (_testingAll || _testingMotor != null)
                      ElevatedButton.icon(
                        icon: const Icon(LucideIcons.octagonAlert, size: 14, color: Colors.white),
                        label: const Text('Stop All', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: AlloyPalette.critical),
                        onPressed: _stopMotorTest,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    final conn = ref.watch(connectionProvider);
    ref.watch(frameTickProvider);
    if (conn == null) return const _NeedsVehicle();
    final s = conn.session;
    final t = s.telemetry.snapshot;
    final pr = s.profile;
    final params = s.isBound ? s.parameters.all : const <String, Parameter>{};
    String yes(bool b) => b ? 'yes' : 'not in this firmware';
    final rows = <(String, String)>[
      ('Firmware', '${pr.name}${s.version == null ? '' : ' · ${s.version}'}'),
      ('Frame', 'class ${params['FRAME_CLASS']?.display ?? '?'} · type ${params['FRAME_TYPE']?.display ?? '?'}'),
      ('Parameters', '${params.length}'),
      (
        'GPS',
        switch (t.gps.firstOrNull) {
          null => '—',
          final g when g.fixType >= 3 => '3D fix · ${g.satellites} satellites',
          final g => 'no 3D fix (${g.satellites} satellites)',
        },
      ),
      ('Battery', t.batteryVoltage.isNaN ? '—' : '${t.batteryVoltage.toStringAsFixed(2)} V'),
      ('Sensor calibration', yes(pr.calibration)),
      ('Saves parameters', yes(pr.persistentParameters)),
      ('Onboard logs', yes(pr.onboardLogs)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Overview',
          trailing: AlloyButton(
            label: 'Reload parameters',
            icon: LucideIcons.refreshCw,
            onPressed: !s.isBound
                ? null
                : () async {
                    // The app‑wide progress capsule shows the count or the failure.
                    await s.parameters.refresh();
                  },
          ),
          child: Column(
            children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: Text(k, style: TextStyle(color: p.ink2)),
                      ),
                      Expanded(
                        child: Text(v, style: AlloyText.mono(13, weight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // TODO(APX-FW-2): calibration commands are stubs in APX 0.1.
        if (!pr.calibration)
          Text(
            'Compass and accelerometer calibration are not available: APX 0.1 accepts the command but does nothing. '
            'Calibration values can still be entered under All parameters (COMPASS_*, INS_*).',
            style: TextStyle(fontSize: 12, color: p.ink2),
          ),
      ],
    );
  }
}

class _FlightModes extends ConsumerWidget {
  const _FlightModes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final modes = conn?.session.profile.selectableModes ?? const <FlightModeInfo>[];
    final options = {for (final m in modes) m.number: m.label};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conn == null) const _NeedsVehicle() else const _NotPersisted(),
        SectionCard(
          title: 'Flight modes',
          subtitle: 'The six modes on the mode switch. Only modes that really fly in this firmware are offered.',
          child: ParamGrid([for (var i = 1; i <= 6; i++) ParamView('FLTMODE$i', 'Position $i', options: options)]),
        ),
      ],
    );
  }
}

class _AllParams extends ConsumerStatefulWidget {
  const _AllParams();
  @override
  ConsumerState<_AllParams> createState() => _AllParamsState();
}

class _AllParamsState extends ConsumerState<_AllParams> {
  String _filter = '';
  bool _changedOnly = false;

  Future<void> _saveFile(ParameterService svc) async {
    final profile = ParameterProfile('vehicle', {for (final p in svc.all.values) p.name: p.value});
    final path = await saveTextFile(
      context,
      'apx-parameters.params',
      profile.toText(),
      const XTypeGroup(
        label: 'Parameters',
        extensions: ['params', 'txt'],
        uniformTypeIdentifiers: ['public.plain-text'],
      ),
    );
    if (path != null && mounted) notify(context, 'Saved ${svc.all.length} parameters to $path');
  }

  Future<void> _applyFile(ParameterService svc) async {
    final f = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Parameters',
          extensions: ['params', 'param', 'parm', 'txt'],
          uniformTypeIdentifiers: ['public.plain-text'],
        ),
      ],
    );
    if (f == null) return;
    final profile = ParameterProfile.parse(f.name, await f.readAsString());
    final diff = profile.diff(svc.all);
    if (!mounted) return;
    if (diff.isEmpty) {
      notify(context, 'The vehicle already has every value in ${f.name}.');
      return;
    }
    final ok = await confirm(
      context,
      'Apply ${diff.length} changes?',
      [
        for (final e in diff.entries.take(12)) '${e.key}: ${e.value.$1} → ${e.value.$2}',
        if (diff.length > 12) '… and ${diff.length - 12} more',
      ].join('\n'),
      action: 'Apply',
    );
    if (!ok) return;
    final results = await profile.applyTo(svc);
    if (!mounted) return;
    final bad = results.where((r) => r.outcome != ParamSetOutcome.applied).toList();
    notify(
      context,
      bad.isEmpty
          ? 'Applied ${results.length} parameters.'
          : 'Applied ${results.length - bad.length}; ${bad.length} not accepted (${bad.take(3).map((r) => r.name).join(', ')}).',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    // Rebuilds when parameters arrive or change, never per telemetry frame;
    // rows are built lazily as they scroll into view.
    final svc = ref.watch(paramServiceProvider);
    ref.watch(paramRevisionProvider);
    Widget page(List<Widget> slivers) => CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverConstrainedCrossAxis(maxExtent: 860, sliver: SliverMainAxisGroup(slivers: slivers)),
        ),
      ],
    );
    if (svc == null) {
      return page([
        SliverToBoxAdapter(
          child: ref.watch(connectionProvider) == null ? const _NeedsVehicle() : const Text('Waiting for the vehicle…'),
        ),
      ]);
    }
    final all = svc.all;
    final q = _filter.toUpperCase();
    final names = all.keys.where((n) {
      final desc = ParamMeta.of(n)?.description.toUpperCase() ?? '';
      if (q.isNotEmpty && !n.contains(q) && !desc.contains(q)) return false;
      if (_changedOnly) {
        final m = ParamMeta.of(n);
        if (m == null || (all[n]!.value - m.defaultValue).abs() <= 1e-6 * (1 + m.defaultValue.abs())) return false;
      }
      return true;
    }).toList()..sort();
    final surface = p.brightness == Brightness.light ? Colors.white : p.canvas;
    return page([
      const SliverToBoxAdapter(child: _NotPersisted()),
      SliverToBoxAdapter(
        child: SectionCard(
          title: 'All parameters',
          subtitle: '${all.length} on the vehicle · ${names.length} shown',
          trailing: Wrap(
            spacing: 8,
            children: [
              AlloyButton(label: 'Save to file…', icon: LucideIcons.save, onPressed: () => _saveFile(svc)),
              AlloyButton(label: 'Apply file…', icon: LucideIcons.fileInput, onPressed: () => _applyFile(svc)),
            ],
          ),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: TextField(
                  textAlignVertical: TextAlignVertical.center,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(LucideIcons.search, size: 18),
                    hintText: 'Search name or description',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _filter = v.trim()),
                ),
              ),
              FilterChip(
                label: const Text('Changed only'),
                selected: _changedOnly,
                onSelected: (v) => setState(() => _changedOnly = v),
              ),
            ],
          ),
        ),
      ),
      DecoratedSliver(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
        ),
        sliver: SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          sliver: SliverList.builder(
            itemCount: names.length,
            itemBuilder: (context, i) {
              final n = names[i];
              return Padding(
                key: ValueKey(n),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n, style: AlloyText.mono(13, weight: FontWeight.w600)),
                          Text(ParamMeta.of(n)?.description ?? '', style: TextStyle(fontSize: 11, color: p.ink2)),
                        ],
                      ),
                    ),
                    Expanded(child: ParamField(ParamView(n, 'Value', decimals: 4))),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

/// Payloads fitted to the vehicle, with test controls.
class _PayloadsPage extends ConsumerWidget {
  const _PayloadsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payloads = ref.watch(payloadsProvider);
    final ctl = ref.read(payloadsProvider.notifier);
    final p = context.alloy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Payloads',
          subtitle:
              'Devices on the vehicle that missions can switch: sprayer, spreader/seeder, servo or relay, gimbal. '
              'Every plan offers these on its waypoints and patterns.',
          trailing: MenuAnchor(
            builder: (context, m, _) =>
                AlloyButton(label: 'Add', icon: LucideIcons.plus, onPressed: () => m.isOpen ? m.close() : m.open()),
            menuChildren: [
              for (final (kind, label) in const [
                (PayloadKind.sprayer, 'Sprayer'),
                (PayloadKind.spreader, 'Spreader / seeder'),
                (PayloadKind.servo, 'Servo or relay'),
                (PayloadKind.gimbal, 'Gimbal (servo tilt)'),
              ])
                MenuItemButton(
                  onPressed: () => ctl.put(
                    Payload(
                      id: ctl.newId(),
                      name: label.split(' ').first,
                      kind: kind,
                      channel: switch (kind) {
                        PayloadKind.sprayer => 9,
                        PayloadKind.spreader => 10,
                        _ => 11,
                      },
                    ),
                  ),
                  child: Text(label),
                ),
            ],
          ),
          child: payloads.isEmpty
              ? Text('No payloads yet.', style: TextStyle(color: p.ink2))
              : Column(children: [for (final pl in payloads) _PayloadCard(pl)]),
        ),
        Text(
          'APX 0.1 only drives the sprayer pump and spinner outputs from inside a mission; other outputs work as direct '
          'commands (the test buttons) but are ignored in missions until the firmware supports them. The planner warns about this.',
          style: TextStyle(fontSize: 12, color: p.ink2),
        ),
      ],
    );
  }
}

class _PayloadCard extends ConsumerWidget {
  const _PayloadCard(this.payload);
  final Payload payload;

  Future<void> _test(BuildContext context, WidgetRef ref, Future<CommandResult> Function(CommandService c) send) async {
    final conn = ref.read(connectionProvider);
    if (conn == null || !conn.session.isBound) return;
    if (!await confirm(
      context,
      'Test ${payload.name}?',
      'Make sure people are clear of the payload. Propellers stay off.',
      action: 'Test',
    )) {
      return;
    }
    final r = await send(conn.session.commands);
    if (context.mounted) notify(context, r.accepted ? '${payload.name}: done.' : '${payload.name}: ${r.message}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    final ctl = ref.read(payloadsProvider.notifier);
    final pl = payload;
    final spin = ref.watch(paramValueProvider('SPRAY_SPIN_CH'))?.value.round() ?? 10;
    void put(Payload n) => ctl.put(n);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(Alloy.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: pl.name,
                  decoration: const InputDecoration(labelText: 'Name', isDense: true),
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) put(pl.copyWith(name: v.trim()));
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: ChoiceField<PayloadKind>(
                  label: 'Type',
                  value: pl.kind,
                  options: const {
                    PayloadKind.sprayer: 'Sprayer (built in)',
                    PayloadKind.spreader: 'Spreader / seeder',
                    PayloadKind.servo: 'Servo / relay',
                    PayloadKind.gimbal: 'Gimbal tilt',
                  },
                  onChanged: (k) => put(pl.copyWith(kind: k)),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(LucideIcons.trash2, size: 18),
                onPressed: () => ctl.remove(pl.id),
              ),
            ],
          ),
          switch (pl.kind) {
            PayloadKind.sprayer => Text(
              'Uses the firmware sprayer (DO_SPRAYER); outputs and rates are under Vehicle → Sprayer.',
              style: TextStyle(fontSize: 12, color: p.ink2),
            ),
            PayloadKind.spreader => FieldGrid(
              columns: 3,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Output', isDense: true),
                  child: Text('$spin (spinner, SPRAY_SPIN_CH)'),
                ),
                NumField(
                  label: 'On PWM',
                  unit: 'µs',
                  value: pl.onPwm.toDouble(),
                  integer: true,
                  min: 800,
                  max: 2200,
                  onChanged: (v) => put(pl.copyWith(onPwm: v.round())),
                ),
                NumField(
                  label: 'Off PWM',
                  unit: 'µs',
                  value: pl.offPwm.toDouble(),
                  integer: true,
                  min: 800,
                  max: 2200,
                  onChanged: (v) => put(pl.copyWith(offPwm: v.round())),
                ),
              ],
            ),
            PayloadKind.servo => FieldGrid(
              columns: 3,
              children: [
                NumField(
                  label: 'Output',
                  value: pl.channel.toDouble(),
                  integer: true,
                  min: 9,
                  max: 16,
                  onChanged: (v) => put(pl.copyWith(channel: v.round())),
                ),
                NumField(
                  label: 'On PWM',
                  unit: 'µs',
                  value: pl.onPwm.toDouble(),
                  integer: true,
                  min: 800,
                  max: 2200,
                  onChanged: (v) => put(pl.copyWith(onPwm: v.round())),
                ),
                NumField(
                  label: 'Off PWM',
                  unit: 'µs',
                  value: pl.offPwm.toDouble(),
                  integer: true,
                  min: 800,
                  max: 2200,
                  onChanged: (v) => put(pl.copyWith(offPwm: v.round())),
                ),
              ],
            ),
            PayloadKind.gimbal => FieldGrid(
              columns: 3,
              children: [
                NumField(
                  label: 'Output',
                  value: pl.channel.toDouble(),
                  integer: true,
                  min: 9,
                  max: 16,
                  onChanged: (v) => put(pl.copyWith(channel: v.round())),
                ),
                NumField(
                  label: 'PWM level (0°)',
                  unit: 'µs',
                  value: pl.pwmAtLevel.toDouble(),
                  integer: true,
                  min: 800,
                  max: 2200,
                  onChanged: (v) => put(pl.copyWith(pwmAtLevel: v.round())),
                ),
                NumField(
                  label: 'PWM down (−90°)',
                  unit: 'µs',
                  value: pl.pwmAtDown.toDouble(),
                  integer: true,
                  min: 800,
                  max: 2200,
                  onChanged: (v) => put(pl.copyWith(pwmAtDown: v.round())),
                ),
              ],
            ),
          },
          if (ref.watch(paramServiceProvider) != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: switch (pl.kind) {
                PayloadKind.sprayer => [
                  AlloyButton(label: 'Spray on', onPressed: () => _test(context, ref, (c) => c.sprayer(true))),
                  AlloyButton(label: 'Spray off', onPressed: () => _test(context, ref, (c) => c.sprayer(false))),
                ],
                PayloadKind.spreader || PayloadKind.servo => [
                  AlloyButton(
                    label: 'Test on',
                    onPressed: () => _test(
                      context,
                      ref,
                      (c) => c.setAuxServo(pl.kind == PayloadKind.spreader ? spin : pl.channel, pl.onPwm),
                    ),
                  ),
                  AlloyButton(
                    label: 'Test off',
                    onPressed: () => _test(
                      context,
                      ref,
                      (c) => c.setAuxServo(pl.kind == PayloadKind.spreader ? spin : pl.channel, pl.offPwm),
                    ),
                  ),
                ],
                PayloadKind.gimbal => [
                  for (final a in const [0.0, -45.0, -90.0])
                    AlloyButton(
                      label: 'Tilt ${a.round()}°',
                      onPressed: () => _test(context, ref, (c) => c.setAuxServo(pl.channel, pl.gimbalPwm(a))),
                    ),
                ],
              },
            ),
        ],
      ),
    );
  }
}
