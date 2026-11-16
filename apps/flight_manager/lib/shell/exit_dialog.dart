// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/tokens.dart';
import '../state/connection.dart';
import '../video/video_manager.dart';

/// Handler type for terminating the application process.
typedef ExitHandler = void Function(int code);

/// Provider for application termination, allowing safe stubbing in test suites.
final appExitHandlerProvider = Provider<ExitHandler>(
  (ref) =>
      (code) => exit(code),
);

/// Shows an exit confirmation dialog and terminates the application if confirmed.
Future<bool> confirmAndExitApp(BuildContext context, WidgetRef ref) async {
  final conn = ref.read(connectionProvider);
  final session = conn?.session;
  final isArmed = session?.telemetry.snapshot.armed ?? false;
  final isConnected = session != null;
  final exitHandler = ref.read(appExitHandlerProvider);

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final p = ctx.alloy;
      return AlertDialog(
        backgroundColor: p.plate,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.hairline),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isArmed
                    ? const Color(0xFFFF3B30).withValues(alpha: 0.15)
                    : const Color(0xFFFF9500).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isArmed ? LucideIcons.triangleAlert : LucideIcons.power,
                color: isArmed ? const Color(0xFFFF3B30) : const Color(0xFFFF9500),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Exit APX Flight Manager', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isArmed) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF3B30)),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.shieldAlert, color: Color(0xFFFF3B30), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'VEHICLE IS CURRENTLY ARMED!\nDisconnecting during flight may lead to loss of control.',
                        style: TextStyle(color: Color(0xFFFF3B30), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isConnected) ...[
              Text(
                'A vehicle is connected. Exiting will terminate the telemetry and ground link.',
                style: TextStyle(color: p.ink2, fontSize: 13),
              ),
              const SizedBox(height: 8),
            ],
            Text('Are you sure you want to close APX Flight Manager?', style: TextStyle(color: p.ink, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: isArmed ? const Color(0xFFFF3B30) : p.ink,
              foregroundColor: isArmed ? Colors.white : p.onInk,
            ),
            icon: const Icon(LucideIcons.power, size: 16),
            label: const Text('Exit App'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      );
    },
  );

  if (confirm == true) {
    // Finish any video recording so the file is complete (MP4 writes its index last).
    await ref.read(videoManagerProvider.notifier).shutdown();
    exitHandler(0);
    return true;
  }
  return false;
}
