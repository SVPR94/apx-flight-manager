// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/fields.dart';
import '../design/tokens.dart';
import '../state/connection.dart';
import '../state/inspector.dart';

/// Developer Diagnostics: 4-lane IMU sensor monitoring, spread meters,
/// real-time MAVLink packet inspector with raw field inspection, and live graphs.
class DeveloperSection extends ConsumerStatefulWidget {
  const DeveloperSection({super.key});

  @override
  ConsumerState<DeveloperSection> createState() => _DeveloperSectionState();
}

class _DeveloperSectionState extends ConsumerState<DeveloperSection> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.accentBg.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.accentInk.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.code, size: 20, color: p.accentInk),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Developer Diagnostics: Low-level hardware sensors, redundant voter spread, and live protocol packet analysis.',
                  style: TextStyle(fontSize: 13, color: p.ink),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.hairline),
          ),
          child: TabBar(
            controller: _tab,
            labelColor: p.accentInk,
            unselectedLabelColor: p.ink2,
            indicatorColor: p.accentInk,
            indicatorWeight: 2,
            tabs: const [
              Tab(icon: Icon(LucideIcons.cpu, size: 16), text: '4-Lane Sensors & Spread'),
              Tab(icon: Icon(LucideIcons.chartLine, size: 16), text: 'Live Telemetry Graph'),
              Tab(icon: Icon(LucideIcons.binary, size: 16), text: 'MAVLink Inspector'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _tab,
          builder: (context, _) => switch (_tab.index) {
            0 => const _FourLaneSensorView(),
            1 => const _LiveGraphView(),
            _ => const _MavlinkInspectorView(),
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. 4-Lane Sensor Monitoring & Redundancy Spread Meters
// ─────────────────────────────────────────────────────────────────────────────

class _FourLaneSensorView extends ConsumerWidget {
  const _FourLaneSensorView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(frameTickProvider);
    final p = context.alloy;
    final conn = ref.watch(connectionProvider);
    final snap = conn?.session.telemetry.snapshot;

    if (conn == null || snap == null) {
      return SectionCard(
        title: 'Sensor Lanes',
        subtitle: 'Connect to APX vehicle to observe redundant sensor telemetry.',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'No active connection',
              style: TextStyle(color: p.ink2, fontStyle: FontStyle.italic),
            ),
          ),
        ),
      );
    }

    final lanes = snap.imu;
    final now = DateTime.now();
    final activeLanes = lanes.where((l) => l.updated != null && now.difference(l.updated!).inSeconds < 3).toList();

    // Spread calculations
    double accelZSpread = 0;
    double gyroSpread = 0;
    double baroSpread = 0;
    if (activeLanes.length >= 2) {
      final zAccels = activeLanes.map((l) => l.accZ);
      accelZSpread = zAccels.reduce(math.max) - zAccels.reduce(math.min);

      final gyroMags = activeLanes.map((l) => math.sqrt(l.gyroX * l.gyroX + l.gyroY * l.gyroY + l.gyroZ * l.gyroZ));
      gyroSpread = gyroMags.reduce(math.max) - gyroMags.reduce(math.min);

      final baros = activeLanes.map((l) => l.pressureHpa);
      baroSpread = baros.reduce(math.max) - baros.reduce(math.min);
    }

    // IMU Health & Calibration Advisory checks
    var lanesNeedCalibration = false;
    final laneHealthList = <(int, String, bool, String)>[];
    for (var i = 0; i < 4; i++) {
      final l = lanes[i];
      final isOnline = l.updated != null && now.difference(l.updated!).inSeconds < 3;
      if (!isOnline) {
        laneHealthList.add((i, 'Offline', false, 'No heartbeat'));
        continue;
      }

      final azErr = (l.accZ.abs() - 9.80665).abs();
      final gyroMag = math.sqrt(l.gyroX * l.gyroX + l.gyroY * l.gyroY + l.gyroZ * l.gyroZ);
      final magNorm = math.sqrt(l.magX * l.magX + l.magY * l.magY + l.magZ * l.magZ);

      if (azErr > 0.48) {
        lanesNeedCalibration = true;
        laneHealthList.add((i, 'Needs Accel Cal', false, 'Bias: ${azErr.toStringAsFixed(2)} m/s²'));
      } else if (gyroMag > 0.05) {
        lanesNeedCalibration = true;
        laneHealthList.add((i, 'Needs Gyro Cal', false, 'Drift: ${(gyroMag * 180 / math.pi).toStringAsFixed(1)}°/s'));
      } else if (magNorm > 0 && (magNorm < 180 || magNorm > 750)) {
        lanesNeedCalibration = true;
        laneHealthList.add((i, 'Needs Mag Cal', false, 'Field: ${magNorm.toStringAsFixed(0)} mG'));
      } else {
        laneHealthList.add((i, 'Healthy', true, '1.0G locked · 0°/s'));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // IMU Health & Calibration Advisory Card
        SectionCard(
          title: 'IMU Behavior & Calibration Health Report',
          subtitle: 'Real-time diagnostic analysis of multi-lane sensor biases and calibration status.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: lanesNeedCalibration ? p.warningBg : p.okBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      lanesNeedCalibration ? LucideIcons.triangleAlert : LucideIcons.checkCircle2,
                      color: lanesNeedCalibration ? p.warningInk : p.okInk,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            lanesNeedCalibration
                                ? 'Sensor Calibration Advisory: Bias Deviation Detected'
                                : 'All Active IMU Lanes Healthy & Calibrated',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: lanesNeedCalibration ? p.warningInk : p.okInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lanesNeedCalibration
                                ? 'One or more redundant sensor lanes deviate from nominal bounds. Re-calibrate in Vehicle workspace.'
                                : 'Voter consensus is locked with low noise standard deviation across all redundant hardware lanes.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: lanesNeedCalibration ? p.warningInk : p.okInk),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: p.pill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: laneHealthList[i].$3
                                        ? p.okInk
                                        : (laneHealthList[i].$2.startsWith('Needs') ? p.warningInk : p.ink2),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Lane ${laneHealthList[i].$1}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                Text(
                                  laneHealthList[i].$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: laneHealthList[i].$3
                                        ? p.okInk
                                        : (laneHealthList[i].$2.startsWith('Needs') ? p.warningInk : p.ink2),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              laneHealthList[i].$4,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: p.ink2, fontFamily: AlloyText.monoFamily),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Spread Meters Card
        SectionCard(
          title: 'Redundant Sensor Spread & Voter Health',
          subtitle: 'Real-time divergence across APX hardware sensor lanes. Alert threshold: > 1.5 m/s² on Z.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SpreadMeter(
                      title: 'Accel Z Divergence',
                      value: accelZSpread,
                      unit: 'm/s²',
                      warnThreshold: 0.8,
                      criticalThreshold: 1.5,
                      maxScale: 2.5,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SpreadMeter(
                      title: 'Gyro Divergence',
                      value: gyroSpread * 180 / math.pi,
                      unit: '°/s',
                      warnThreshold: 2.0,
                      criticalThreshold: 5.0,
                      maxScale: 10.0,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SpreadMeter(
                      title: 'Baro Divergence',
                      value: baroSpread,
                      unit: 'hPa',
                      warnThreshold: 0.5,
                      criticalThreshold: 1.5,
                      maxScale: 3.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: p.inset, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(
                      accelZSpread > 1.5 ? LucideIcons.triangleAlert : LucideIcons.shieldCheck,
                      size: 16,
                      color: accelZSpread > 1.5 ? p.warningInk : p.okInk,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Active voting lanes: ${activeLanes.length} of 4 · '
                      'State: ${accelZSpread > 1.5 ? "Diverging (Warning)" : "Optimal Consensus"}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: accelZSpread > 1.5 ? p.warningInk : p.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 4 Lanes Side by Side Card
        SectionCard(
          title: '4-Lane Redundant IMU / Baro / Mag (HIGHRES_IMU #105)',
          subtitle: 'Per-lane readings directly from APX multi-lane architecture.',
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _LaneColumn(
                        lane: lanes[i],
                        isOnline: lanes[i].updated != null && now.difference(lanes[i].updated!).inSeconds < 3,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SpreadMeter extends StatelessWidget {
  const _SpreadMeter({
    required this.title,
    required this.value,
    required this.unit,
    required this.warnThreshold,
    required this.criticalThreshold,
    required this.maxScale,
  });

  final String title;
  final double value;
  final String unit;
  final double warnThreshold;
  final double criticalThreshold;
  final double maxScale;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final ratio = (value / maxScale).clamp(0.0, 1.0);
    final isCritical = value >= criticalThreshold;
    final isWarn = value >= warnThreshold;
    final statusColor = isCritical ? AlloyPalette.critical : (isWarn ? p.cautionInk : p.okInk);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.inset,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCritical ? AlloyPalette.critical.withValues(alpha: 0.5) : p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.ink2),
              ),
              Text('${value.toStringAsFixed(2)} $unit', style: AlloyText.mono(13, color: statusColor)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: p.canvas,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({required this.lane, required this.isOnline});

  final ImuLane lane;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.inset,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOnline ? p.hairline : p.hairline.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LANE ${lane.lane}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? p.okInk : p.ink2.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MetricRow('Accel X', lane.accX.toStringAsFixed(2), 'm/s²'),
          _MetricRow('Accel Y', lane.accY.toStringAsFixed(2), 'm/s²'),
          _MetricRow('Accel Z', lane.accZ.toStringAsFixed(2), 'm/s²'),
          const Divider(height: 10),
          _MetricRow('Gyro X', (lane.gyroX * 180 / math.pi).toStringAsFixed(1), '°/s'),
          _MetricRow('Gyro Y', (lane.gyroY * 180 / math.pi).toStringAsFixed(1), '°/s'),
          _MetricRow('Gyro Z', (lane.gyroZ * 180 / math.pi).toStringAsFixed(1), '°/s'),
          const Divider(height: 10),
          _MetricRow('Mag X', lane.magX.toStringAsFixed(0), 'mG'),
          _MetricRow('Mag Y', lane.magY.toStringAsFixed(0), 'mG'),
          _MetricRow('Mag Z', lane.magZ.toStringAsFixed(0), 'mG'),
          const Divider(height: 10),
          _MetricRow('Baro', lane.pressureHpa.toStringAsFixed(1), 'hPa'),
          _MetricRow('Temp', lane.temperature.toStringAsFixed(1), '°C'),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.val, this.unit);
  final String label, val, unit;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: p.ink2)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: val,
                  style: AlloyText.mono(11, color: p.ink),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(fontSize: 9, color: p.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Real-Time Live Graph View
// ─────────────────────────────────────────────────────────────────────────────

class _LiveGraphView extends ConsumerWidget {
  const _LiveGraphView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    final insp = ref.watch(inspectorProvider);
    final ctrl = ref.read(inspectorProvider.notifier);

    // Compute summary stats across all plotted series points
    var allCount = 0;
    var statMin = double.infinity;
    var statMax = -double.infinity;
    var statSum = 0.0;

    for (final pts in insp.series.values) {
      for (final pt in pts) {
        if (pt.value < statMin) statMin = pt.value;
        if (pt.value > statMax) statMax = pt.value;
        statSum += pt.value;
        allCount++;
      }
    }
    final hasData = allCount > 0 && statMin.isFinite && statMax.isFinite;
    final statMean = hasData ? statSum / allCount : double.nan;
    final statPP = hasData ? (statMax - statMin) : double.nan;

    return SectionCard(
      title: 'Live Waveform & Telemetry Graph',
      subtitle: 'Real-time oscilloscope view for flight dynamics and multi-lane voter monitoring.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<DiagnosticChannel>(
            value: insp.selectedChannel,
            dropdownColor: p.plate,
            style: TextStyle(fontSize: 13, color: p.ink, fontWeight: FontWeight.w600),
            underline: const SizedBox(),
            items: DiagnosticChannel.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
            onChanged: (c) {
              if (c != null) ctrl.selectChannel(c);
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: insp.autoScale
                ? 'Auto-scale Y-axis: ON (click for fixed range)'
                : 'Auto-scale Y-axis: OFF (click to auto-fit)',
            icon: Icon(
              insp.autoScale ? LucideIcons.scanLine : LucideIcons.scaling,
              size: 18,
              color: insp.autoScale ? p.accentInk : p.ink2,
            ),
            onPressed: ctrl.toggleAutoScale,
          ),
          IconButton(
            tooltip: insp.isGraphPaused ? 'Resume live graph' : 'Pause graph',
            icon: Icon(insp.isGraphPaused ? LucideIcons.play : LucideIcons.pause, size: 18),
            onPressed: ctrl.togglePause,
          ),
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(LucideIcons.trash2, size: 18),
            onPressed: ctrl.clearGraph,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: p.brightness == Brightness.light ? const Color(0xFF1E2125) : const Color(0xFF0F1114),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.hairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                painter: _TelemetryGraphPainter(
                  series: insp.series,
                  channel: insp.selectedChannel,
                  autoScale: insp.autoScale,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Statistics readout card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: p.pill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(label: 'Min', val: hasData ? _formatStat(statMin, statPP, insp.selectedChannel.unit) : '—'),
                _StatItem(label: 'Max', val: hasData ? _formatStat(statMax, statPP, insp.selectedChannel.unit) : '—'),
                _StatItem(
                  label: 'Mean (Avg)',
                  val: hasData ? _formatStat(statMean, statPP, insp.selectedChannel.unit) : '—',
                ),
                _StatItem(
                  label: 'Peak-to-Peak (Δ)',
                  val: hasData ? _formatStat(statPP, statPP, insp.selectedChannel.unit) : '—',
                ),
                _StatItem(label: 'Samples', val: '$allCount pts'),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final entry in insp.series.entries) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _seriesColor(entry.key), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${entry.key}: ${entry.value.isNotEmpty ? _formatStat(entry.value.last.value, statPP, insp.selectedChannel.unit) : "--"}',
                      style: TextStyle(fontSize: 12, color: p.ink, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _formatStat(double val, double range, String unit) {
    if (val.isNaN || !val.isFinite) return '—';
    final String numStr;
    if (range < 0.05 || (val.abs() < 0.05 && val != 0)) {
      numStr = val.toStringAsFixed(3);
    } else if (range < 10) {
      numStr = val.toStringAsFixed(2);
    } else {
      numStr = val.toStringAsFixed(1);
    }
    return '$numStr $unit';
  }

  static Color _seriesColor(String name) => switch (name) {
    'Spread' => const Color(0xFF0E9AA7),
    'Lane 0' => const Color(0xFF2FA36B),
    'Lane 1' => const Color(0xFF38BDF8),
    'Lane 2' => const Color(0xFFF59E0B),
    'Lane 3' => const Color(0xFFEC4899),
    'Roll' => const Color(0xFF38BDF8),
    'Pitch' => const Color(0xFFF59E0B),
    'Alt Rel' => const Color(0xFF0E9AA7),
    'Alt MSL' => const Color(0xFF94A3B8),
    'Climb' => const Color(0xFF2FA36B),
    'Voltage' => const Color(0xFFEAB308),
    'Speed' => const Color(0xFF38BDF8),
    _ => Colors.white70,
  };
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.val});
  final String label, val;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: p.ink2)),
        Text(val, style: AlloyText.mono(11.5, color: p.ink)),
      ],
    );
  }
}

class _TelemetryGraphPainter extends CustomPainter {
  _TelemetryGraphPainter({required this.series, required this.channel, this.autoScale = true});

  final Map<String, List<TimeSeriesPoint>> series;
  final DiagnosticChannel channel;
  final bool autoScale;

  @override
  void paint(Canvas canvas, Size size) {
    const leftMargin = 60.0;
    const rightMargin = 16.0;
    const topMargin = 22.0;
    const bottomMargin = 24.0;

    final plotWidth = (size.width - leftMargin - rightMargin).clamp(10.0, double.infinity);
    final plotHeight = (size.height - topMargin - bottomMargin).clamp(10.0, double.infinity);
    final plotRect = Rect.fromLTWH(leftMargin, topMargin, plotWidth, plotHeight);

    final gridPaint = Paint()
      ..color = const Color(0xFF282D35)
      ..strokeWidth = 1.0;

    final axisPaint = Paint()
      ..color = const Color(0xFF4A5568)
      ..strokeWidth = 1.2;

    // Determine min/max: Auto-scale dynamically to data bounds so small signals retain their waveform shape
    double minVal;
    double maxVal;

    if (autoScale) {
      double dataMin = double.infinity;
      double dataMax = -double.infinity;
      var hasPoints = false;

      for (final list in series.values) {
        for (final pt in list) {
          if (pt.value.isFinite) {
            if (pt.value < dataMin) dataMin = pt.value;
            if (pt.value > dataMax) dataMax = pt.value;
            hasPoints = true;
          }
        }
      }

      if (hasPoints) {
        final spread = dataMax - dataMin;
        if (spread.abs() < 1e-4) {
          // Flat or single-point: give it a tight margin around the center value
          final center = dataMin;
          final margin = (center.abs() * 0.15).clamp(0.1, 2.0);
          minVal = center - margin;
          maxVal = center + margin;
        } else {
          // 12% headroom and footroom padding so wave peaks don't clip at top/bottom border
          final pad = spread * 0.12;
          minVal = dataMin - pad;
          maxVal = dataMax + pad;
        }
      } else {
        minVal = channel.defaultMin;
        maxVal = channel.defaultMax;
      }
    } else {
      minVal = channel.defaultMin;
      maxVal = channel.defaultMax;
      for (final list in series.values) {
        for (final pt in list) {
          if (pt.value < minVal) minVal = pt.value;
          if (pt.value > maxVal) maxVal = pt.value;
        }
      }
    }

    if ((maxVal - minVal).abs() < 1e-4) {
      maxVal += 1.0;
      minVal -= 1.0;
    }
    final range = maxVal - minVal;

    // Y-Axis Title & Unit at top
    final titleTp = TextPainter(
      text: TextSpan(
        text: '${channel.label} [${channel.unit}]${autoScale ? " · Auto-fit" : ""}',
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(canvas, const Offset(leftMargin, 5));

    // Draw horizontal grid lines & Y-axis numerical tick labels
    const yDivisions = 4;
    for (var i = 0; i <= yDivisions; i++) {
      final normY = i / yDivisions;
      final y = plotRect.top + plotRect.height * normY;
      final val = maxVal - range * normY;

      // Grid line
      canvas.drawLine(Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);

      // Y-Tick text with dynamic precision matching range
      final String tickStr;
      if (range < 0.05) {
        tickStr = val.toStringAsFixed(4);
      } else if (range < 0.5) {
        tickStr = val.toStringAsFixed(3);
      } else if (range < 10) {
        tickStr = val.toStringAsFixed(2);
      } else {
        tickStr = val.toStringAsFixed(1);
      }

      final tickTp = TextPainter(
        text: TextSpan(
          text: tickStr,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontFamily: AlloyText.monoFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tickTp.paint(canvas, Offset(plotRect.left - tickTp.width - 6, y - tickTp.height / 2));
    }

    // Zero-line accent if zero is inside the plot range
    if (minVal < 0 && maxVal > 0) {
      final zeroNorm = (0.0 - minVal) / range;
      final zeroY = plotRect.bottom - plotRect.height * zeroNorm;
      final zeroPaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.4)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(plotRect.left, zeroY), Offset(plotRect.right, zeroY), zeroPaint);
    }

    // Draw vertical grid lines & X-axis time marks (-30s, -20s, -10s, Now)
    const xLabels = ['-30s', '-20s', '-10s', 'Now'];
    for (var i = 0; i < xLabels.length; i++) {
      final normX = i / (xLabels.length - 1);
      final x = plotRect.left + plotRect.width * normX;

      // Vertical grid
      canvas.drawLine(Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);

      // X-Tick time label
      final timeTp = TextPainter(
        text: TextSpan(
          text: xLabels[i],
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontFamily: AlloyText.monoFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final textX = (i == xLabels.length - 1) ? x - timeTp.width : (i == 0 ? x : x - timeTp.width / 2);
      timeTp.paint(canvas, Offset(textX, plotRect.bottom + 6));
    }

    // Axis lines (left and bottom)
    canvas.drawLine(Offset(plotRect.left, plotRect.top), Offset(plotRect.left, plotRect.bottom), axisPaint);
    canvas.drawLine(Offset(plotRect.left, plotRect.bottom), Offset(plotRect.right, plotRect.bottom), axisPaint);

    if (series.isEmpty) return;

    // Draw telemetry curves clipped to plotRect
    canvas.save();
    canvas.clipRect(plotRect);

    for (final entry in series.entries) {
      final pts = entry.value;
      if (pts.length < 2) continue;

      final paint = Paint()
        ..color = _LiveGraphView._seriesColor(entry.key)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final x = plotRect.left + plotRect.width * (i / (pts.length - 1));
        final norm = (pts[i].value - minVal) / range;
        final y = plotRect.bottom - plotRect.height * norm.clamp(0.0, 1.0);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TelemetryGraphPainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Real-Time MAVLink Packet Inspector
// ─────────────────────────────────────────────────────────────────────────────

class _MavlinkInspectorView extends ConsumerStatefulWidget {
  const _MavlinkInspectorView();

  @override
  ConsumerState<_MavlinkInspectorView> createState() => _MavlinkInspectorViewState();
}

class _MavlinkInspectorViewState extends ConsumerState<_MavlinkInspectorView> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final insp = ref.watch(inspectorProvider);
    final ctrl = ref.read(inspectorProvider.notifier);

    final entries = insp.messages.values
        .where(
          (e) =>
              _filter.isEmpty ||
              e.name.toLowerCase().contains(_filter.toLowerCase()) ||
              e.id.toString().contains(_filter),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Protocol Link Stats Card
        SectionCard(
          title: 'Transport Counters & Error Rates',
          subtitle: 'MAVLink v2 parser statistics and frame delivery health.',
          child: Row(
            children: [
              Expanded(
                child: _StatTile(title: 'Data Rate', value: '${insp.byteRateKBs.toStringAsFixed(1)} KB/s'),
              ),
              Expanded(
                child: _StatTile(title: 'Packet Rate', value: '${insp.frameRateHz.toStringAsFixed(0)} Hz'),
              ),
              Expanded(
                child: _StatTile(title: 'Total Frames', value: '${insp.totalFrames}'),
              ),
              Expanded(
                child: _StatTile(
                  title: 'Lost Frames',
                  value: '${insp.lostFrames}',
                  color: insp.lostFrames > 0 ? p.cautionInk : null,
                ),
              ),
              Expanded(
                child: _StatTile(
                  title: 'CRC Errors',
                  value: '${insp.crcErrors}',
                  color: insp.crcErrors > 0 ? AlloyPalette.critical : null,
                ),
              ),
              Expanded(
                child: _StatTile(
                  title: 'Loss Ratio',
                  value: '${(insp.dropRatio * 100).toStringAsFixed(2)}%',
                  color: insp.dropRatio > 0.01 ? p.warningInk : null,
                ),
              ),
            ],
          ),
        ),

        // Message Inspector Table Card
        SectionCard(
          title: 'Packet Inspector & Raw Field Inspector',
          subtitle: 'Click any message to expand its real-time decoded wire fields.',
          trailing: SizedBox(
            width: 200,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Filter message…',
                hintStyle: TextStyle(fontSize: 12, color: p.ink2),
                prefixIcon: Icon(LucideIcons.search, size: 14, color: p.ink2),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: p.hairline),
                ),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: p.inset, borderRadius: BorderRadius.circular(6)),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text('ID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('RATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('COUNT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('LAST SEEN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No packets captured matching query',
                      style: TextStyle(color: p.ink2, fontStyle: FontStyle.italic),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: p.hairline.withValues(alpha: 0.5)),
                  itemBuilder: (context, index) {
                    final item = entries[index];
                    final isSelected = insp.selectedMessageId == item.id;
                    final ago = item.lastSeen != null
                        ? '${DateTime.now().difference(item.lastSeen!).inMilliseconds} ms ago'
                        : '—';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InkWell(
                          onTap: () => ctrl.selectMessage(item.id),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 60,
                                  child: Text('#${item.id}', style: AlloyText.mono(12, color: p.ink2)),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        isSelected ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                                        size: 14,
                                        color: p.ink2,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('${item.rateHz.toStringAsFixed(1)} Hz', style: AlloyText.mono(12)),
                                ),
                                Expanded(flex: 2, child: Text('${item.count}', style: AlloyText.mono(12))),
                                Expanded(
                                  flex: 2,
                                  child: Text(ago, style: TextStyle(fontSize: 11, color: p.ink2)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isSelected) _RawFieldsTable(fields: item.latestFields),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.title, required this.value, this.color});
  final String title, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 11, color: p.ink2)),
        const SizedBox(height: 2),
        Text(value, style: AlloyText.mono(14, color: color ?? p.ink)),
      ],
    );
  }
}

class _RawFieldsTable extends StatelessWidget {
  const _RawFieldsTable({required this.fields});
  final Map<String, Object> fields;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    if (fields.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.inset, borderRadius: BorderRadius.circular(6)),
        child: Text(
          'No fields decoded yet',
          style: TextStyle(fontSize: 11, color: p.ink2, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.inset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('RAW DECODED FIELDS', style: AlloyText.label(p.ink2)),
          const SizedBox(height: 8),
          for (final entry in fields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: Text(
                      entry.key,
                      style: TextStyle(fontSize: 12, color: p.ink2, fontFamily: AlloyText.monoFamily),
                    ),
                  ),
                  Expanded(
                    child: Text('${entry.value}', style: AlloyText.mono(12, color: p.ink)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
