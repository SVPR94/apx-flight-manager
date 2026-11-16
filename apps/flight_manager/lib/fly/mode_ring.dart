// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/tokens.dart';

/// Modal flight mode selector. Returns the chosen custom_mode number, or null.
Future<int?> showModeRing(BuildContext context, FirmwareProfile profile, int current) => showGeneralDialog<int>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close mode selector',
  barrierColor: const Color(0x66000000),
  transitionDuration: Alloy.panel,
  transitionBuilder: (context, a, _, child) => FadeTransition(
    opacity: a,
    child: ScaleTransition(
      scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: a, curve: Alloy.curve)),
      child: child,
    ),
  ),
  pageBuilder: (context, _, _) => Center(
    child: _ModeDialog(profile: profile, current: current),
  ),
);

class _ModeDialog extends StatelessWidget {
  const _ModeDialog({required this.profile, required this.current});
  final FirmwareProfile profile;
  final int current;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final modes = profile.selectableModes;

    final autoModes = modes.where((m) => m.group == ModeGroup.autonomous).toList();
    final assistedModes = modes.where((m) => m.group == ModeGroup.assisted).toList();
    final manualModes = modes.where((m) => m.group == ModeGroup.manual).toList();

    return Material(
      color: Colors.transparent,
      child: Glass(
        radius: 20,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Flight Mode Selection',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap a mode to command mode change on the vehicle.',
                          style: TextStyle(fontSize: 12, color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('CURRENT: ', style: AlloyText.label(p.onInk.withValues(alpha: 0.7))),
                        Text(
                          profile.modeName(current),
                          style: TextStyle(color: p.onInk, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Mode Categories
              if (autoModes.isNotEmpty) ...[
                _CategoryLabel(title: 'Autonomous Modes', icon: LucideIcons.route),
                const SizedBox(height: 8),
                _ModeGrid(modes: autoModes, current: current),
                const SizedBox(height: 16),
              ],

              if (assistedModes.isNotEmpty) ...[
                _CategoryLabel(title: 'Assisted Position & Altitude Modes', icon: LucideIcons.compass),
                const SizedBox(height: 8),
                _ModeGrid(modes: assistedModes, current: current),
                const SizedBox(height: 16),
              ],

              if (manualModes.isNotEmpty) ...[
                _CategoryLabel(title: 'Manual & Recovery Modes', icon: LucideIcons.hand),
                const SizedBox(height: 8),
                _ModeGrid(modes: manualModes, current: current),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Row(
      children: [
        Icon(icon, size: 14, color: p.accentInk),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink2),
        ),
      ],
    );
  }
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.modes, required this.current});
  final List<FlightModeInfo> modes;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final m in modes)
          _ModeCard(mode: m, selected: m.number == current, onTap: () => Navigator.of(context).pop(m.number)),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.selected, required this.onTap});
  final FlightModeInfo mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final icon = _modeIcon(mode.label);

    return SizedBox(
      width: 156,
      height: 64,
      child: Material(
        color: selected ? AlloyPalette.accent : p.plate,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AlloyPalette.accent : p.hairline, width: selected ? 1.5 : 1.0),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white.withValues(alpha: 0.25) : p.inset,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: selected ? Colors.white : p.accentInk),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        mode.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : p.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (mode.status == ModeStatus.alias)
                        Text(
                          '= ${mode.aliasOf!.toLowerCase()}',
                          style: TextStyle(fontSize: 10, color: selected ? Colors.white70 : p.ink2),
                          maxLines: 1,
                        )
                      else
                        Text(
                          _modeSubtitle(mode.label),
                          style: TextStyle(fontSize: 10, color: selected ? Colors.white70 : p.ink2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _modeIcon(String label) => switch (label.toUpperCase()) {
    'AUTO' => LucideIcons.route,
    'GUIDED' => LucideIcons.crosshair,
    'RTL' => LucideIcons.house,
    'LOITER' => LucideIcons.compass,
    'POS_HOLD' => LucideIcons.mapPin,
    'ALT_HOLD' => LucideIcons.moveVertical,
    'BRAKE' => LucideIcons.octagonX,
    'LAND' => LucideIcons.planeLanding,
    'STABILIZE' => LucideIcons.hand,
    _ => LucideIcons.navigation,
  };

  static String _modeSubtitle(String label) => switch (label.toUpperCase()) {
    'AUTO' => 'Run mission',
    'GUIDED' => 'Fly to point',
    'RTL' => 'Return home',
    'LOITER' => 'Hold 3D pos',
    'ALT_HOLD' => 'Hold altitude',
    'BRAKE' => 'Stop in place',
    'LAND' => 'Descend & disarm',
    'STABILIZE' => 'Manual level',
    _ => 'Custom mode',
  };
}
