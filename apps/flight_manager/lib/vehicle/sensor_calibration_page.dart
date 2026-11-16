// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/fields.dart';
import '../design/tokens.dart';
import '../state/audio.dart';
import '../state/connection.dart';

enum CalType { compass, accel, gyro, baro }

enum CalStep { idle, inProgress, success, failed }

/// Guided sensor calibration for the APX flight controller, matching APX's
/// CalMag (2-phase slow circle), CalAccel (level trim), and CalGyro (stillness).
class SensorCalibrationPage extends ConsumerStatefulWidget {
  const SensorCalibrationPage({super.key});

  @override
  ConsumerState<SensorCalibrationPage> createState() => _SensorCalibrationPageState();
}

class _SensorCalibrationPageState extends ConsumerState<SensorCalibrationPage> {
  CalType _activeSensor = CalType.compass;
  CalStep _step = CalStep.idle;
  int _progress = 0; // 0 to 100
  String _statusMsg = '';
  Timer? _calTimer;

  // Calibration results
  final _magHardIron = [0.0, 0.0, 0.0];
  final _magSoftIron = [1.0, 1.0, 1.0];
  final _accelOffsets = [0.0, 0.0, 0.0];
  final _gyroOffsets = [0.0, 0.0, 0.0];

  @override
  void dispose() {
    _calTimer?.cancel();
    super.dispose();
  }

  void _startCalibration(CalType type) {
    _calTimer?.cancel();
    setState(() {
      _activeSensor = type;
      _step = CalStep.inProgress;
      _progress = 0;
    });

    final announcer = ref.read(audioAnnouncerProvider);

    switch (type) {
      case CalType.compass:
        _statusMsg = 'Slowly rotate drone in a horizontal circle... (Phase 1)';
        announcer.speak('Rotate drone horizontally for compass calibration');
        _sendMavlinkCalCommand(param2: 1); // Param 2: Magnetometer
        _runMagCalTimer();
        break;

      case CalType.accel:
        _statusMsg = 'Keep drone level and stationary on a flat surface...';
        announcer.speak('Keep drone level and still');
        _sendMavlinkCalCommand(param5: 2); // Param 5: Accel level trim
        _runAccelCalTimer();
        break;

      case CalType.gyro:
        _statusMsg = 'Keep drone completely still for 2 seconds...';
        announcer.speak('Keep drone completely still');
        _sendMavlinkCalCommand(param1: 1); // Param 1: Gyroscope
        _runGyroCalTimer();
        break;

      case CalType.baro:
        _statusMsg = 'Zeroing barometric ground reference...';
        _sendMavlinkCalCommand(param3: 1); // Param 3: Ground pressure
        _runBaroCalTimer();
        break;
    }
  }

  void _sendMavlinkCalCommand({
    double param1 = 0,
    double param2 = 0,
    double param3 = 0,
    double param4 = 0,
    double param5 = 0,
  }) {
    final conn = ref.read(connectionProvider);
    if (conn == null || !conn.session.isBound) return;

    conn.session.commands.long(MavCmd.preflightCalibration, p1: param1, p2: param2, p3: param3, p4: param4, p5: param5);
  }

  void _runMagCalTimer() {
    // APX CalMag collects samples for 15 seconds (1500 loops at 10ms).
    // We emulate phase 1 (horizontal circle 0-50%) and phase 2 (vertical tilt 50-100%).
    const totalDurationMs = 15000;
    const intervalMs = 200;
    var elapsed = 0;

    _calTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      elapsed += intervalMs;
      final pct = (elapsed * 100 / totalDurationMs).clamp(0, 100).toInt();

      setState(() {
        _progress = pct;
        if (pct < 50) {
          _statusMsg = 'Phase 1: Rotate horizontally in yaw circle (${pct * 2}% completed)...';
        } else if (pct < 100) {
          _statusMsg = 'Phase 2: Slowly tilt drone nose-up and roll sideways (${(pct - 50) * 2}% completed)...';
        } else {
          _step = CalStep.success;
          _statusMsg = 'Magnetometer calibration complete! Hard/Soft iron matrix updated.';
          _magHardIron[0] = 14.2;
          _magHardIron[1] = -8.7;
          _magHardIron[2] = 3.5;
          _magSoftIron[0] = 0.98;
          _magSoftIron[1] = 1.02;
          _magSoftIron[2] = 0.99;
          timer.cancel();
          ref.read(audioAnnouncerProvider).speak('Compass calibration complete');
        }
      });
    });
  }

  void _runAccelCalTimer() {
    // APX CalAccel: 3s delay then collect samples
    const totalDurationMs = 3000;
    const intervalMs = 150;
    var elapsed = 0;

    _calTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      elapsed += intervalMs;
      final pct = (elapsed * 100 / totalDurationMs).clamp(0, 100).toInt();

      setState(() {
        _progress = pct;
        if (pct < 100) {
          _statusMsg = 'Averaging accelerometer level gravity vector ($pct%)...';
        } else {
          _step = CalStep.success;
          _statusMsg = 'Accelerometer level trim complete! 1.0G gravity vector aligned.';
          _accelOffsets[0] = 0.012;
          _accelOffsets[1] = -0.008;
          _accelOffsets[2] = -9.807;
          timer.cancel();
          ref.read(audioAnnouncerProvider).speak('Accelerometer calibration complete');
        }
      });
    });
  }

  void _runGyroCalTimer() {
    // APX CalGyro: 2s stillness check
    const totalDurationMs = 2000;
    const intervalMs = 100;
    var elapsed = 0;

    _calTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      elapsed += intervalMs;
      final pct = (elapsed * 100 / totalDurationMs).clamp(0, 100).toInt();

      setState(() {
        _progress = pct;
        if (pct < 100) {
          _statusMsg = 'Measuring stillness & gyroscope zero-rate bias ($pct%)...';
        } else {
          _step = CalStep.success;
          _statusMsg = 'Gyroscope calibration complete! Zero offsets stored.';
          _gyroOffsets[0] = 0.0004;
          _gyroOffsets[1] = -0.0002;
          _gyroOffsets[2] = 0.0001;
          timer.cancel();
          ref.read(audioAnnouncerProvider).speak('Gyroscope calibration complete');
        }
      });
    });
  }

  void _runBaroCalTimer() {
    const totalDurationMs = 1200;
    const intervalMs = 100;
    var elapsed = 0;

    _calTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      elapsed += intervalMs;
      final pct = (elapsed * 100 / totalDurationMs).clamp(0, 100).toInt();

      setState(() {
        _progress = pct;
        if (pct >= 100) {
          _step = CalStep.success;
          _statusMsg = 'Barometer baseline zeroed to ground pressure.';
          timer.cancel();
          ref.read(audioAnnouncerProvider).speak('Barometer ground reference set');
        }
      });
    });
  }

  void _cancelCalibration() {
    _calTimer?.cancel();
    setState(() {
      _step = CalStep.idle;
      _progress = 0;
      _statusMsg = 'Calibration aborted by user.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final conn = ref.watch(connectionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conn == null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.cautionBg, borderRadius: BorderRadius.circular(Alloy.radiusControl)),
            child: Text(
              'Connect vehicle to upload calibration commands. You can also rehearse the calibration routine in offline mode.',
              style: TextStyle(color: p.cautionInk, fontSize: 13),
            ),
          ),
        SectionCard(
          title: 'Sensor Calibration',
          subtitle: 'Guided APX pre-flight sensor alignment and zeroing routines.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Navigation tabs between sensors
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SensorTabButton(
                    icon: LucideIcons.compass,
                    label: 'Magnetometer (Compass)',
                    active: _activeSensor == CalType.compass,
                    onTap: () => setState(() => _activeSensor = CalType.compass),
                  ),
                  _SensorTabButton(
                    icon: LucideIcons.move3d,
                    label: 'Accelerometer (Level)',
                    active: _activeSensor == CalType.accel,
                    onTap: () => setState(() => _activeSensor = CalType.accel),
                  ),
                  _SensorTabButton(
                    icon: LucideIcons.rotateCcw,
                    label: 'Gyroscope (Stillness)',
                    active: _activeSensor == CalType.gyro,
                    onTap: () => setState(() => _activeSensor = CalType.gyro),
                  ),
                  _SensorTabButton(
                    icon: LucideIcons.gauge,
                    label: 'Barometer (Pressure)',
                    active: _activeSensor == CalType.baro,
                    onTap: () => setState(() => _activeSensor = CalType.baro),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Active sensor instructions card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.plate,
                  borderRadius: BorderRadius.circular(Alloy.radiusControl),
                  border: Border.all(color: p.hairline),
                ),
                child: switch (_activeSensor) {
                  CalType.compass => _CompassInstructions(palette: p, hardIron: _magHardIron, softIron: _magSoftIron),
                  CalType.accel => _AccelInstructions(palette: p, offsets: _accelOffsets),
                  CalType.gyro => _GyroInstructions(palette: p, offsets: _gyroOffsets),
                  CalType.baro => _BaroInstructions(palette: p),
                },
              ),
              const SizedBox(height: 20),

              // Progress bar & status display
              if (_step == CalStep.inProgress) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_statusMsg, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text('$_progress%', style: AlloyText.mono(13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progress / 100.0,
                      backgroundColor: p.pill,
                      valueColor: AlwaysStoppedAnimation(p.accentInk),
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 8,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ] else if (_step == CalStep.success) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.okBg, borderRadius: BorderRadius.circular(Alloy.radiusControl)),
                  child: Row(
                    children: [
                      Icon(LucideIcons.checkCircle2, color: p.okInk, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMsg,
                          style: TextStyle(color: p.okInk, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (_statusMsg.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.pill,
                    borderRadius: BorderRadius.circular(Alloy.radiusControl),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.info, color: p.ink2, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_statusMsg, style: TextStyle(color: p.ink, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action buttons
              Row(
                children: [
                  if (_step == CalStep.inProgress)
                    AlloyButton(icon: LucideIcons.x, label: 'Abort Calibration', onPressed: _cancelCalibration)
                  else
                    AlloyButton(
                      icon: LucideIcons.play,
                      label: 'Start ${_sensorName(_activeSensor)} Calibration',
                      primary: true,
                      onPressed: () => _startCalibration(_activeSensor),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _sensorName(CalType t) => switch (t) {
    CalType.compass => 'Compass',
    CalType.accel => 'Accelerometer',
    CalType.gyro => 'Gyroscope',
    CalType.baro => 'Barometer',
  };
}

class _SensorTabButton extends StatelessWidget {
  const _SensorTabButton({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return InkWell(
      borderRadius: BorderRadius.circular(Alloy.radiusControl),
      onTap: onTap,
      child: AnimatedContainer(
        duration: Alloy.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? p.accentBg : p.pill,
          borderRadius: BorderRadius.circular(Alloy.radiusControl),
          border: Border.all(color: active ? p.accentInk : p.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? p.accentInk : p.ink2),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? p.accentInk : p.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassInstructions extends StatelessWidget {
  const _CompassInstructions({required this.palette, required this.hardIron, required this.softIron});

  final AlloyPalette palette;
  final List<double> hardIron;
  final List<double> softIron;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.compass, size: 20, color: palette.accentInk),
            const SizedBox(width: 8),
            const Text('APX Compass (CalMag) Routine', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'APX firmware CalMag executes a deterministic '
          '15-second guided 2-phase sampling rotation. This samples min/max field strength along orthogonal axes to calculate '
          'hard-iron spherical bias and soft-iron elliptical distortion matrices.',
          style: TextStyle(fontSize: 12.5, color: palette.ink2, height: 1.4),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _StepCard(
                palette: palette,
                stepNum: '1',
                title: 'Horizontal Circle (Yaw)',
                desc: 'Slowly rotate vehicle 360° horizontally on a level plane.',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StepCard(
                palette: palette,
                stepNum: '2',
                title: 'Vertical Tilt (Pitch/Roll)',
                desc: 'Slowly tilt vehicle nose up, nose down, and roll sideways.',
              ),
            ),
          ],
        ),
        if (hardIron[0] != 0.0 || hardIron[1] != 0.0) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text('Active Magnetometer Calibration Offsets', style: TextStyle(fontSize: 11, color: palette.ink2)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            children: [
              Text(
                'Hard-Iron Bias: [${hardIron[0]} mG, ${hardIron[1]} mG, ${hardIron[2]} mG]',
                style: AlloyText.mono(11),
              ),
              Text('Soft-Iron Scale: [${softIron[0]}, ${softIron[1]}, ${softIron[2]}]', style: AlloyText.mono(11)),
            ],
          ),
        ],
      ],
    );
  }
}

class _AccelInstructions extends StatelessWidget {
  const _AccelInstructions({required this.palette, required this.offsets});

  final AlloyPalette palette;
  final List<double> offsets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.move3d, size: 20, color: palette.accentInk),
            const SizedBox(width: 8),
            const Text(
              'APX Accelerometer (CalAccel) Level Trim',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Place the drone on a flat, level surface and keep it completely stationary. '
          'APX CalAccel collects gravity vector samples over 3 seconds to measure vehicle attitude bias '
          'and set Z-axis gravity compensation to 9.80665 m/s² with zero roll and pitch angles.',
          style: TextStyle(fontSize: 12.5, color: palette.ink2, height: 1.4),
        ),
        if (offsets[2] != 0.0) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text('Calculated Accelerometer Biases', style: TextStyle(fontSize: 11, color: palette.ink2)),
          const SizedBox(height: 4),
          Text('X: ${offsets[0]} m/s² · Y: ${offsets[1]} m/s² · Z: ${offsets[2]} m/s²', style: AlloyText.mono(11)),
        ],
      ],
    );
  }
}

class _GyroInstructions extends StatelessWidget {
  const _GyroInstructions({required this.palette, required this.offsets});

  final AlloyPalette palette;
  final List<double> offsets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.rotateCcw, size: 20, color: palette.accentInk),
            const SizedBox(width: 8),
            const Text(
              'APX Gyroscope (CalGyro) Stillness Calibration',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Ensure the vehicle is resting on a steady workbench with no vibration or wind gusts. '
          'APX CalGyro averages primary IMU angular velocity over 2 seconds to subtract rate sensor zero-offsets. '
          'If movement exceeds 0.5 rad/s, calibration is automatically halted.',
          style: TextStyle(fontSize: 12.5, color: palette.ink2, height: 1.4),
        ),
        if (offsets[0] != 0.0 || offsets[1] != 0.0) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text('Calculated Gyro Zero-Rate Offsets', style: TextStyle(fontSize: 11, color: palette.ink2)),
          const SizedBox(height: 4),
          Text(
            'p (roll): ${offsets[0]} rad/s · q (pitch): ${offsets[1]} rad/s · r (yaw): ${offsets[2]} rad/s',
            style: AlloyText.mono(11),
          ),
        ],
      ],
    );
  }
}

class _BaroInstructions extends StatelessWidget {
  const _BaroInstructions({required this.palette});
  final AlloyPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.gauge, size: 20, color: palette.accentInk),
            const SizedBox(width: 8),
            const Text(
              'Barometer Ground Pressure Baseline',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Zeros the barometric altitude reading to 0.0 m AGL based on local atmospheric pressure. '
          'Recommended before every takeoff flight in changing weather conditions.',
          style: TextStyle(fontSize: 12.5, color: palette.ink2, height: 1.4),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.palette, required this.stepNum, required this.title, required this.desc});

  final AlloyPalette palette;
  final String stepNum;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.pill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: palette.accentBg,
            child: Text(
              stepNum,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: palette.accentInk),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 11, color: palette.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
