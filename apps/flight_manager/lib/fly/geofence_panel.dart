// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/fields.dart';
import '../design/tokens.dart';
import '../state/connection.dart';
import '../state/fence.dart';

/// Geofence configuration and drawing control panel floating over FlyView map.
class GeofencePanel extends ConsumerWidget {
  const GeofencePanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    final fence = ref.watch(fenceProvider);
    final fenceCtrl = ref.read(fenceProvider.notifier);
    final conn = ref.watch(connectionProvider);
    final session = conn?.session;
    final breach = ref.watch(fenceBreachProvider);
    final breached = breach != null;

    return Glass(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.shieldAlert, size: 18, color: Color(0xFFFF9500)),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Safety Geofence', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    GlassIconButton(icon: LucideIcons.x, tooltip: 'Close', onPressed: onClose),
                  ],
                ),
              ),

              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    // Master Enable / Disable Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Geofence', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        fence.enabled ? 'Vehicle will enforce boundary & ceiling' : 'Geofence is currently inactive',
                        style: TextStyle(fontSize: 12, color: p.ink2),
                      ),
                      value: fence.enabled,
                      activeThumbColor: const Color(0xFFFF9500),
                      onChanged: (val) {
                        fenceCtrl.toggleEnabled(session, val);
                        _notify(context, val ? 'Geofence enabled' : 'Geofence disabled');
                      },
                    ),

                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: breached
                            ? const Color(0xFFFF3B30).withValues(alpha: 0.15)
                            : fence.enabled
                            ? const Color(0xFFFF9500).withValues(alpha: 0.12)
                            : p.plate,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: breached
                              ? const Color(0xFFFF3B30)
                              : fence.enabled
                              ? const Color(0xFFFF9500).withValues(alpha: 0.5)
                              : p.hairline,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            breached
                                ? LucideIcons.triangleAlert
                                : fence.enabled
                                ? LucideIcons.shieldCheck
                                : LucideIcons.shield,
                            size: 16,
                            color: breached
                                ? const Color(0xFFFF3B30)
                                : fence.enabled
                                ? const Color(0xFFFF9500)
                                : p.ink2,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              breached
                                  ? 'BREACH ACTIVE: ${breach.toUpperCase()} exceeded'
                                  : fence.enabled
                                  ? 'ENABLED: ${fence.hasValidPolygon ? "${fence.points.length} vertices" : "No polygon"}, ${fence.altMax <= 0 ? "No alt limit" : "Alt ≤ ${fence.altMax.toStringAsFixed(0)}m"}'
                                  : 'FENCE INACTIVE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: breached
                                    ? const Color(0xFFFF3B30)
                                    : fence.enabled
                                    ? const Color(0xFFFF9500)
                                    : p.ink2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 16),

                    // Polygon Boundary Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(child: Caption('Polygon Boundary')),
                        Text(
                          '${fence.points.length} vertices',
                          style: TextStyle(fontSize: 12, color: p.ink2, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    if (fence.isDrawing) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9500).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFF9500).withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 8,
                          children: [
                            Row(
                              children: [
                                const Icon(LucideIcons.penTool, size: 14, color: Color(0xFFFF9500)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Drawing active: Tap on the map to add fence boundary vertices.',
                                    style: TextStyle(fontSize: 12, color: p.ink),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              spacing: 8,
                              children: [
                                Expanded(
                                  child: AlloyButton(
                                    label: 'Done',
                                    icon: LucideIcons.check,
                                    onPressed: fence.hasValidPolygon
                                        ? () {
                                            fenceCtrl.finishDrawing();
                                            _notify(context, 'Fence polygon defined (${fence.points.length} vertices)');
                                          }
                                        : null,
                                  ),
                                ),
                                if (fence.points.isNotEmpty)
                                  Expanded(
                                    child: AlloyButton(
                                      label: 'Undo',
                                      icon: LucideIcons.undo,
                                      onPressed: fenceCtrl.undoPoint,
                                    ),
                                  ),
                                Expanded(
                                  child: AlloyButton(
                                    label: 'Clear',
                                    icon: LucideIcons.trash2,
                                    onPressed: fenceCtrl.clearPoints,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else if (fence.isMoving) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9500).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFF9500).withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 8,
                          children: [
                            Row(
                              children: [
                                const Icon(LucideIcons.move, size: 14, color: Color(0xFFFF9500)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Move Mode: Drag the central ⊕ anchor on the map to relocate the entire fence.',
                                    style: TextStyle(fontSize: 12, color: p.ink),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              spacing: 8,
                              children: [
                                Expanded(
                                  child: AlloyButton(
                                    label: 'Done',
                                    icon: LucideIcons.check,
                                    onPressed: fenceCtrl.finishMoving,
                                  ),
                                ),
                                if (session != null && session.telemetry.snapshot.hasPosition)
                                  Expanded(
                                    child: AlloyButton(
                                      label: 'To Drone',
                                      icon: LucideIcons.navigation,
                                      onPressed: () {
                                        final s = session.telemetry.snapshot;
                                        fenceCtrl.moveTo(LatLng(s.lat, s.lon));
                                        _notify(context, 'Fence moved to drone coordinates');
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: AlloyButton(
                              label: fence.points.isEmpty ? 'Draw on Map' : 'Edit Boundary',
                              icon: LucideIcons.pencil,
                              onPressed: fenceCtrl.startDrawing,
                            ),
                          ),
                          if (fence.points.isNotEmpty) ...[
                            Expanded(
                              child: AlloyButton(
                                label: 'Move Fence',
                                icon: LucideIcons.move,
                                onPressed: fenceCtrl.startMoving,
                              ),
                            ),
                            AlloyButton(label: 'Clear', icon: LucideIcons.trash2, onPressed: fenceCtrl.clearPoints),
                          ],
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),
                    const Caption('Altitude Ceiling'),
                    const SizedBox(height: 4),
                    Text(
                      'Maximum allowed altitude above takeoff point (0m = no height restriction)',
                      style: TextStyle(fontSize: 11, color: p.ink2),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: NumField(
                            label: 'Ceiling Altitude',
                            unit: 'm',
                            value: fence.altMax,
                            min: 0,
                            max: 5000,
                            integer: true,
                            help: fence.altMax == 0
                                ? 'No limit (0m): unrestricted altitude'
                                : 'Breach triggers when vehicle exceeds ${fence.altMax.toStringAsFixed(0)}m',
                            onChanged: (val) => fenceCtrl.setAltMax(session, val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: fence.altMax == 0 ? const Color(0xFFFF9500) : p.hairline,
                              ),
                              backgroundColor:
                                  fence.altMax == 0 ? const Color(0xFFFF9500).withValues(alpha: 0.15) : null,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                            onPressed: () => fenceCtrl.setAltMax(session, 0.0),
                            child: const Text('No Limit', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    const Caption('Breach Failsafe Action'),
                    const SizedBox(height: 4),
                    Text(
                      'Action triggered when fence boundary or altitude ceiling is breached',
                      style: TextStyle(fontSize: 11, color: p.ink2),
                    ),
                    const SizedBox(height: 8),

                    DropdownButtonFormField<int>(
                      initialValue: fence.action,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      dropdownColor: p.plate,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Return to Launch (RTL)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 2, child: Text('Land Immediately', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 4, child: Text('Brake / Hold Position', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 0, child: Text('Report Only (Warning)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) fenceCtrl.setAction(session, val);
                      },
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 16),

                    // Upload Button
                    SizedBox(
                      height: 40,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9500),
                          foregroundColor: Colors.black,
                        ),
                        icon: fence.isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(LucideIcons.uploadCloud, size: 18),
                        label: Text(
                          fence.isUploading
                              ? 'Uploading to Drone…'
                              : session != null
                              ? 'Upload Fence to Drone'
                              : 'Connect Drone to Upload',
                        ),
                        onPressed: session != null && !fence.isUploading
                            ? () async {
                                final error = await fenceCtrl.uploadToVehicle(session);
                                if (!context.mounted) return;
                                _notify(
                                  context,
                                  error == null
                                      ? 'Safety fence uploaded to the flight controller.'
                                      : 'Fence upload failed: $error',
                                );
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }
}
