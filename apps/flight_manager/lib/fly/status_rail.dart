// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../state/connection.dart';
import 'mode_ring.dart';

/// Glass capsule at the top of the Fly view.
class StatusRail extends ConsumerStatefulWidget {
  const StatusRail({super.key, required this.connection, required this.onResult});
  final Connection connection;
  final void Function(CommandResult) onResult;

  @override
  ConsumerState<StatusRail> createState() => _StatusRailState();
}

class _StatusRailState extends ConsumerState<StatusRail> {
  DateTime? _armedAt;
  bool _showDisarmSlider = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(frameTickProvider);
    final session = widget.connection.session;
    final s = session.telemetry.snapshot;
    final ready = session.state.value != SessionState.waiting;

    if (s.armed && _armedAt == null) _armedAt = DateTime.now();
    if (!s.armed) {
      _armedAt = null;
      if (_showDisarmSlider) _showDisarmSlider = false;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Glass(
          radius: Alloy.radiusCapsule,
          padding: const EdgeInsets.all(6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _mode(session, s, ready),
              Pill(
                icon: LucideIcons.power,
                tone: s.armed ? Tone.caution : Tone.neutral,
                tooltip: ready ? (s.armed ? 'Tap to open Disarm slider' : 'Tap to Arm drone') : null,
                onTap: ready ? () => setState(() => _showDisarmSlider = !_showDisarmSlider) : null,
                children: [
                  Text(
                    s.armed ? 'ARMED' : 'DISARMED',
                    style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                  if (ready)
                    Icon(
                      _showDisarmSlider ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 13,
                      color: s.armed ? const Color(0xFFFF9500) : context.alloy.ink2,
                    ),
                ],
              ),
              _link(session),
              if (ready) _gps(s),
              if (ready) _battery(session, s),
              if (_armedAt != null)
                Pill(icon: LucideIcons.timer, children: [Reading(_elapsed(DateTime.now().difference(_armedAt!)))]),
            ],
          ),
        ),
        if (_showDisarmSlider && ready) ...[
          const SizedBox(height: 8),
          Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                if (!s.armed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 290,
                        child: SlideToConfirm(
                          label: 'Slide to arm drone',
                          icon: LucideIcons.power,
                          tone: Tone.caution,
                          onConfirmed: () async {
                            final r = await session.commands.arm();
                            widget.onResult(r);
                            if (mounted) setState(() => _showDisarmSlider = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Cancel',
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () => setState(() => _showDisarmSlider = false),
                      ),
                    ],
                  )
                else if (s.altRel.isNaN || s.altRel < 1.5) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 290,
                        child: SlideToConfirm(
                          label: 'Slide to take off (10m)',
                          icon: LucideIcons.arrowUpFromLine,
                          tone: Tone.accent,
                          onConfirmed: () async {
                            final r = await session.commands.takeoff(10);
                            widget.onResult(r);
                            if (mounted) setState(() => _showDisarmSlider = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Cancel',
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () => setState(() => _showDisarmSlider = false),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 290,
                    child: SlideToConfirm(
                      label: 'Slide to disarm drone',
                      icon: LucideIcons.powerOff,
                      tone: Tone.critical,
                      onConfirmed: () async {
                        final r = await session.commands.disarm();
                        widget.onResult(r);
                        if (mounted) setState(() => _showDisarmSlider = false);
                      },
                    ),
                  ),
                ] else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 290,
                        child: SlideToConfirm(
                          label: 'Slide to disarm (Emergency)',
                          icon: LucideIcons.powerOff,
                          tone: Tone.critical,
                          onConfirmed: () async {
                            final r = await session.commands.disarm();
                            widget.onResult(r);
                            if (mounted) setState(() => _showDisarmSlider = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Cancel',
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () => setState(() => _showDisarmSlider = false),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _mode(VehicleSession session, VehicleSnapshot s, bool ready) {
    final canSwitch = session.state.value == SessionState.ready && session.profile.selectableModes.isNotEmpty;
    return Pill(
      tone: Tone.inverted,
      tooltip: canSwitch ? 'Change flight mode' : null,
      onTap: canSwitch
          ? () async {
              final chosen = await showModeRing(context, session.profile, s.customMode);
              if (chosen != null && chosen != s.customMode) {
                widget.onResult(await session.commands.setMode(chosen));
              }
            }
          : null,
      children: [
        Text(
          ready ? session.profile.modeName(s.customMode).toUpperCase() : '—',
          style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.6),
        ),
        if (canSwitch) const Icon(LucideIcons.chevronDown, size: 15, color: Colors.white),
      ],
    );
  }

  Widget _link(VehicleSession session) {
    final link = session.link;
    final loss = link.parser.stats.lossRatio * 100;
    final (tone, text) = switch (session.state.value) {
      SessionState.lost => (Tone.critical, 'Link lost'),
      SessionState.waiting => (Tone.caution, 'Waiting for vehicle'),
      SessionState.initializing => (Tone.accent, session.step.value),
      SessionState.ready => (loss > 5 ? Tone.caution : Tone.ok, null),
    };
    return Pill(
      icon: LucideIcons.signal,
      tone: tone,
      tooltip: link.descriptor.address,
      children: text != null
          ? [Text(text)]
          : [
              Reading(link.stats.hasRates ? link.stats.framesInPerSecond.toStringAsFixed(0) : '—', unit: 'msg/s'),
              Reading(loss.toStringAsFixed(loss < 10 ? 1 : 0), unit: '% loss'),
            ],
    );
  }

  Widget _gps(VehicleSnapshot s) {
    final g = s.gps[0];
    final tone = g.has3dFix ? Tone.neutral : (g.fixType == 2 ? Tone.caution : Tone.warning);
    final fix = switch (g.fixType) {
      >= 3 => '3D',
      2 => '2D',
      1 => 'No fix',
      _ => 'No GPS',
    };
    return Pill(
      icon: LucideIcons.satellite,
      tone: tone,
      children: [
        Text(fix, style: const TextStyle(fontWeight: FontWeight.w600)),
        Reading('${g.satellites}', unit: 'sat'),
        if (!g.hdop.isNaN) Reading(g.hdop.toStringAsFixed(1), unit: 'HDOP'),
      ],
    );
  }

  Widget _battery(VehicleSession session, VehicleSnapshot s) {
    final v = s.batteryVoltage;
    if (v.isNaN) {
      return const Pill(icon: LucideIcons.battery, children: [Text('No battery data')]);
    }
    final low = session.isBound ? session.parameters['BATT_LOW_VOLT']?.value : null;
    final crit = session.isBound ? session.parameters['BATT_CRT_VOLT']?.value : null;
    final tone = (crit != null && v <= crit)
        ? Tone.critical
        : (low != null && v <= low)
        ? Tone.caution
        : Tone.neutral;
    return Pill(
      icon: LucideIcons.batteryMedium,
      tone: tone,
      children: [
        Reading(v.toStringAsFixed(1), unit: 'V'),
        if (s.batteryRemaining >= 0) Reading('${s.batteryRemaining}', unit: '%'),
      ],
    );
  }

  static String _elapsed(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Drops below the rail with the latest alert; critical alerts stay until dismissed.
class NotificationCapsule extends StatefulWidget {
  const NotificationCapsule({super.key, required this.alerts, this.local});
  final AlertsEngine alerts;

  /// A local message (e.g. a refused command) shown the same way.
  final Alert? local;

  @override
  State<NotificationCapsule> createState() => _NotificationCapsuleState();
}

class _NotificationCapsuleState extends State<NotificationCapsule> {
  Alert? _shown;
  Timer? _hide;
  late StreamSubscription<Alert> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.alerts.alerts.listen(_show);
  }

  @override
  void didUpdateWidget(NotificationCapsule old) {
    super.didUpdateWidget(old);
    if (widget.local != null && widget.local != old.local) _show(widget.local!);
  }

  void _show(Alert a) {
    // Don't let routine information hide an unacknowledged critical alert.
    if (_shown?.severity == AlertSeverity.critical && a.severity != AlertSeverity.critical) return;
    setState(() => _shown = a);
    _hide?.cancel();
    if (a.severity != AlertSeverity.critical) {
      _hide = Timer(const Duration(seconds: 6), () => mounted ? setState(() => _shown = null) : null);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _hide?.cancel();
    super.dispose();
  }

  static Tone tone(AlertSeverity s) => switch (s) {
    AlertSeverity.info => Tone.accent,
    AlertSeverity.caution => Tone.caution,
    AlertSeverity.warning => Tone.warning,
    AlertSeverity.critical => Tone.critical,
  };

  @override
  Widget build(BuildContext context) {
    final a = _shown;
    return AnimatedSwitcher(
      duration: Alloy.panel,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: a == null
          ? const SizedBox.shrink()
          : Glass(
              key: ValueKey(a),
              radius: 18,
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Pill(
                    icon: severityIcon(tone(a.severity)),
                    tone: tone(a.severity),
                    children: [Text(a.severity.name.toUpperCase())],
                  ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Text(a.text, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _history(context),
                    child: Text('History · ${widget.alerts.history.length}'),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => setState(() => _shown = null),
                  ),
                ],
              ),
            ),
    );
  }

  void _history(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.alloy.plate,
    builder: (context) {
      final items = widget.alerts.history.reversed.toList();
      return SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final a = items[i];
            final t = a.time;
            return ListTile(
              dense: true,
              leading: Icon(severityIcon(tone(a.severity))),
              title: Text(a.text),
              trailing: Text(
                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}',
                style: AlloyText.mono(12, weight: FontWeight.w500),
              ),
            );
          },
        ),
      );
    },
  );
}
