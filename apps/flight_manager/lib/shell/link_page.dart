// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../connect/connect_form.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../state/connection.dart';

/// Connection details, transport statistics and what this firmware supports.
class LinkPage extends ConsumerWidget {
  const LinkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    ref.watch(frameTickProvider);
    final p = context.alloy;
    return ColoredBox(
      color: p.plate,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Link', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (conn == null)
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _card(context, const ConnectForm()))
          else
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _card(context, _connection(context, ref, conn)),
                _card(context, _transport(context, conn)),
                if (conn.session.isBound) _card(context, _firmware(context, conn.session)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) => Container(
    width: 380,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.alloy.brightness == Brightness.light ? Colors.white : context.alloy.canvas,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.alloy.hairline),
    ),
    child: child,
  );

  Widget _rows(BuildContext context, List<(String, String)> rows) {
    final p = context.alloy;
    return Column(
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(k, style: TextStyle(color: p.ink2)),
                ),
                Expanded(
                  child: Text(v, style: AlloyText.mono(13, weight: FontWeight.w500)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _connection(BuildContext context, WidgetRef ref, Connection c) {
    final s = c.session;
    final hasErr = s.link.lastError != null || c.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const Caption('Connection'),
        if (hasErr)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.circleAlert, size: 16, color: Color(0xFFFF3B30)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.error ?? s.link.lastError ?? 'Connection error',
                    style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        _rows(context, [
          ('Address', s.link.descriptor.address),
          ('Transport', s.link.state.value.name),
          ('Session', s.state.value.name),
          ('Step', s.step.value),
          if (s.link.lastError != null) ('Last error', s.link.lastError!),
          if (c.error != null) ('Error', c.error!),
        ]),
        AlloyButton(
          label: 'Disconnect',
          icon: LucideIcons.unplug,
          expand: true,
          onPressed: () => ref.read(connectionProvider.notifier).disconnect(),
        ),
      ],
    );
  }

  Widget _transport(BuildContext context, Connection c) {
    final l = c.session.link;
    final ps = l.parser.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const Caption('Transport'),
        _rows(context, [
          ('Frames in', '${l.stats.framesIn}  (${l.stats.framesInPerSecond.toStringAsFixed(0)}/s)'),
          ('Bytes in', '${l.stats.bytesIn}  (${(l.stats.bytesInPerSecond / 1024).toStringAsFixed(1)} KiB/s)'),
          ('Frames out', '${l.stats.framesOut}'),
          ('Sequence loss', '${ps.sequenceLost}  (${(ps.lossRatio * 100).toStringAsFixed(2)}%)'),
          ('CRC errors', '${ps.crcErrors}'),
          ('Unknown ids', '${ps.unknownIds}'),
          ('Bytes discarded', '${ps.bytesDiscarded}'),
        ]),
      ],
    );
  }

  Widget _firmware(BuildContext context, VehicleSession s) {
    final pr = s.profile;
    String yes(bool b) => b ? 'yes' : 'no';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const Caption('Firmware'),
        _rows(context, [
          ('Profile', pr.name),
          ('Version', s.version?.toString() ?? 'not reported'),
          ('System / component', '${s.channel.targetSystem} / ${s.channel.targetComponent}'),
          ('Parameters', '${s.parameters.all.length}'),
          ('Mission on vehicle', s.vehicleMission == null ? 'not read' : '${s.vehicleMission!.length} items'),
          ('Saves parameters', yes(pr.persistentParameters)),
          ('Home position', pr.homeSource == HomeSource.reported ? 'reported' : 'estimated by GCS'),
          ('Fence / rally', yes(pr.fenceAndRally)),
          ('Calibration', yes(pr.calibration)),
          ('Onboard logs', yes(pr.onboardLogs)),
        ]),
      ],
    );
  }
}
