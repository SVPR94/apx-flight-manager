// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/fields.dart';
import '../design/tokens.dart';
import '../state/connection.dart';
import '../state/failsafe.dart';

class FailsafePage extends ConsumerWidget {
  const FailsafePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    final failsafe = ref.watch(failsafeProvider);
    final ctrl = ref.read(failsafeProvider.notifier);
    final conn = ref.watch(connectionProvider);
    final snapshot = conn?.session.telemetry.snapshot;
    final battVolt = snapshot?.batteryVoltage ?? double.nan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conn == null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.cautionBg, borderRadius: BorderRadius.circular(Alloy.radiusControl)),
            child: Text(
              'Connect vehicle to synchronize failsafe parameters with the flight controller.',
              style: TextStyle(color: p.cautionInk, fontSize: 13),
            ),
          ),
        SectionCard(
          title: 'Battery Failsafe System',
          subtitle: 'Automatic flight safety actions triggered by battery exhaustion.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!battVolt.isNaN) ...[
                Row(
                  children: [
                    Icon(LucideIcons.batteryCharging, size: 18, color: p.ink2),
                    const SizedBox(width: 8),
                    Text('Live Battery Voltage: ', style: TextStyle(fontSize: 13, color: p.ink2)),
                    Reading('${battVolt.toStringAsFixed(2)} V', size: 14),
                    const SizedBox(width: 12),
                    _BatteryStatusPill(
                      voltage: battVolt,
                      lowVolt: failsafe.batteryLowVoltage,
                      critVolt: failsafe.batteryCriticalVoltage,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
              ],
              _FailsafeConfigRow(
                icon: LucideIcons.batteryLow,
                title: 'Low Battery Threshold',
                subtitle: 'Triggered when battery pack drops below this voltage.',
                valueLabel: '${failsafe.batteryLowVoltage.toStringAsFixed(1)} V',
                sliderValue: failsafe.batteryLowVoltage,
                minSlider: 10.0,
                maxSlider: 26.0,
                divisions: 32,
                onSliderChanged: (v) => ctrl.update((s) => s.copyWith(batteryLowVoltage: v)),
                currentAction: failsafe.batteryLowAction,
                onActionChanged: (a) => ctrl.update((s) => s.copyWith(batteryLowAction: a)),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _FailsafeConfigRow(
                icon: LucideIcons.batteryWarning,
                title: 'Critical Battery Threshold',
                subtitle: 'Emergency action when battery voltage becomes critically depleted.',
                valueLabel: '${failsafe.batteryCriticalVoltage.toStringAsFixed(1)} V',
                sliderValue: failsafe.batteryCriticalVoltage,
                minSlider: 9.0,
                maxSlider: 25.0,
                divisions: 32,
                onSliderChanged: (v) => ctrl.update((s) => s.copyWith(batteryCriticalVoltage: v)),
                currentAction: failsafe.batteryCriticalAction,
                onActionChanged: (a) => ctrl.update((s) => s.copyWith(batteryCriticalAction: a)),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Communication Link Loss Failsafes',
          subtitle: 'Safety procedures if remote control or ground station connection drops.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FailsafeConfigRow(
                icon: LucideIcons.radio,
                title: 'RC Transmitter Link Loss',
                subtitle: 'Triggered if manual radio control signal is lost.',
                valueLabel: '${failsafe.rcLossTimeoutSeconds} seconds',
                sliderValue: failsafe.rcLossTimeoutSeconds.toDouble(),
                minSlider: 1.0,
                maxSlider: 10.0,
                divisions: 9,
                onSliderChanged: (v) => ctrl.update((s) => s.copyWith(rcLossTimeoutSeconds: v.round())),
                currentAction: failsafe.rcLossAction,
                onActionChanged: (a) => ctrl.update((s) => s.copyWith(rcLossAction: a)),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _FailsafeConfigRow(
                icon: LucideIcons.wifiOff,
                title: 'GCS Telemetry Link Loss',
                subtitle: 'Triggered if ground station heartbeat times out during autonomous missions.',
                valueLabel: '${failsafe.gcsLossTimeoutSeconds} seconds',
                sliderValue: failsafe.gcsLossTimeoutSeconds.toDouble(),
                minSlider: 2.0,
                maxSlider: 20.0,
                divisions: 18,
                onSliderChanged: (v) => ctrl.update((s) => s.copyWith(gcsLossTimeoutSeconds: v.round())),
                currentAction: failsafe.gcsLossAction,
                onActionChanged: (a) => ctrl.update((s) => s.copyWith(gcsLossAction: a)),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Geofence & Containment',
          subtitle: 'Enforces ceiling altitude and perimeter radius limits.',
          trailing: Switch(
            value: failsafe.geofenceEnabled,
            onChanged: (v) => ctrl.update((s) => s.copyWith(geofenceEnabled: v)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FailsafeConfigRow(
                icon: LucideIcons.mountain,
                title: 'Maximum Altitude Limit',
                subtitle: 'Halts flight or returns home if drone climbs above ceiling.',
                valueLabel: '${failsafe.geofenceMaxAltitudeMeters.toStringAsFixed(0)} m',
                sliderValue: failsafe.geofenceMaxAltitudeMeters,
                minSlider: 10.0,
                maxSlider: 500.0,
                divisions: 49,
                onSliderChanged: (v) => ctrl.update((s) => s.copyWith(geofenceMaxAltitudeMeters: v)),
                currentAction: failsafe.geofenceAction,
                onActionChanged: (a) => ctrl.update((s) => s.copyWith(geofenceAction: a)),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _FailsafeConfigRow(
                icon: LucideIcons.circleDot,
                title: 'Maximum Fence Radius',
                subtitle: 'Horizontal containment radius centered on home launch point.',
                valueLabel: '${failsafe.geofenceMaxRadiusMeters.toStringAsFixed(0)} m',
                sliderValue: failsafe.geofenceMaxRadiusMeters,
                minSlider: 50.0,
                maxSlider: 2000.0,
                divisions: 39,
                onSliderChanged: (v) => ctrl.update((s) => s.copyWith(geofenceMaxRadiusMeters: v)),
                currentAction: failsafe.geofenceAction,
                onActionChanged: (a) => ctrl.update((s) => s.copyWith(geofenceAction: a)),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Firmware Parameter Synchronization',
          subtitle: 'Upload failsafe configuration to APX parameters (BATT_LOW_VOLT, BATT_CRT_VOLT, FS_GCS_ENABLE, FS_THR_ENABLE).',
          child: Align(
            alignment: Alignment.centerLeft,
            child: AlloyButton(
              icon: LucideIcons.uploadCloud,
              label: 'Sync Failsafes to Flight Controller',
              primary: true,
              onPressed: conn != null
                  ? () async {
                      await ctrl.syncToVehicleParams();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Failsafe parameters uploaded to vehicle.')));
                      }
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _BatteryStatusPill extends StatelessWidget {
  const _BatteryStatusPill({required this.voltage, required this.lowVolt, required this.critVolt});

  final double voltage;
  final double lowVolt;
  final double critVolt;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    if (voltage <= critVolt) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AlloyPalette.critical, borderRadius: BorderRadius.circular(10)),
        child: const Text(
          'CRITICAL',
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    }
    if (voltage <= lowVolt) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: p.warningBg, borderRadius: BorderRadius.circular(10)),
        child: Text(
          'LOW',
          style: TextStyle(color: p.warningInk, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: p.okBg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        'HEALTHY',
        style: TextStyle(color: p.okInk, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _FailsafeConfigRow extends StatelessWidget {
  const _FailsafeConfigRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.sliderValue,
    required this.minSlider,
    required this.maxSlider,
    required this.divisions,
    required this.onSliderChanged,
    required this.currentAction,
    required this.onActionChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String valueLabel;
  final double sliderValue;
  final double minSlider;
  final double maxSlider;
  final int divisions;
  final ValueChanged<double> onSliderChanged;
  final FailsafeAction currentAction;
  final ValueChanged<FailsafeAction> onActionChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: p.ink2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: p.ink2)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: p.pill,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.hairline),
              ),
              child: Text(valueLabel, style: AlloyText.mono(12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: sliderValue.clamp(minSlider, maxSlider),
                min: minSlider,
                max: maxSlider,
                divisions: divisions,
                onChanged: onSliderChanged,
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<FailsafeAction>(
              value: currentAction,
              underline: const SizedBox(),
              borderRadius: BorderRadius.circular(Alloy.radiusControl),
              items: [
                for (final a in FailsafeAction.values)
                  DropdownMenuItem(
                    value: a,
                    child: Text(a.label, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: (a) {
                if (a != null) onActionChanged(a);
              },
            ),
          ],
        ),
      ],
    );
  }
}
