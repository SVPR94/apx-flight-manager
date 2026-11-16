// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../fly/fly_view.dart';
import '../plan/plan_view.dart';
import '../state/connection.dart';
import '../state/vehicle_params.dart';
import '../video/video_widgets.dart';
import '../vehicle/vehicle_view.dart';
import 'exit_dialog.dart';
import 'link_page.dart';
import 'settings_page.dart';

/// Sidebar dock + the active space. Spaces appear here only once they work:
/// Logs joins in a later stage.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _spaces = [
    (LucideIcons.navigation, 'Fly'),
    (LucideIcons.map, 'Plan'),
    (LucideIcons.settings2, 'Vehicle'),
    (LucideIcons.cable, 'Link'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () => confirmAndExitApp(context, ref)},
      child: Focus(
        autofocus: true,
        // Also starts the video manager with the app, so a configured stream
        // auto-connects (and can record) whatever space is open.
        child: VideoNoticeListener(
          child: Scaffold(
            body: Row(
              children: [
                Container(
                  width: 76,
                  decoration: BoxDecoration(
                    color: p.plate,
                    border: Border(right: BorderSide(color: p.hairline)),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: 18),
                        const _Badge(),
                        const SizedBox(height: 18),
                        for (final (i, (icon, label)) in _spaces.indexed)
                          _DockItem(
                            icon: icon,
                            label: label,
                            selected: _index == i,
                            onTap: () => setState(() => _index = i),
                          ),
                        const Spacer(),
                        _DockItem(
                          icon: LucideIcons.settings,
                          label: 'Settings',
                          selected: _index == _spaces.length,
                          onTap: () => setState(() => _index = _spaces.length),
                        ),
                        _DockItem(
                          icon: LucideIcons.power,
                          label: 'Exit',
                          selected: false,
                          isExit: true,
                          onTap: () => confirmAndExitApp(context, ref),
                        ),
                        const SizedBox(height: 6),
                        const _LinkLamp(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        // One shared backdrop for every glass panel on the page.
                        child: BackdropGroup(
                          child: IndexedStack(
                            index: _index,
                            // Hidden spaces keep their state but not their animations
                            // (the Fly view's per-frame motion pauses while away).
                            children: [
                              for (final (i, page) in const [
                                FlyView(),
                                PlanView(),
                                VehicleView(),
                                LinkPage(),
                                SettingsPage(),
                              ].indexed)
                                TickerMode(enabled: i == _index, child: page),
                            ],
                          ),
                        ),
                      ),
                      const Positioned(left: 0, right: 0, top: 0, bottom: 0, child: _ParamLoadBanner()),
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
}

class _Badge extends StatelessWidget {
  const _Badge();
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: const LinearGradient(
        colors: [Color(0xFFFDFDFE), Color(0xFFC9CED5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: const [BoxShadow(color: Color(0x2E141820), blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: const Text(
      'APX',
      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1D1F23)),
    ),
  );
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.isExit = false,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isExit;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final fg = selected
        ? p.accentInk
        : isExit
        ? const Color(0xFFE0622B)
        : p.ink2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Material(
          color: selected ? p.accentBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: isExit ? const Color(0x1FFF3B30) : null,
            onTap: onTap,
            child: SizedBox(
              width: 60,
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 4,
                children: [
                  Icon(icon, size: 21, color: fg),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Link state at the foot of the dock.
class _LinkLamp extends ConsumerWidget {
  const _LinkLamp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    ref.watch(frameTickProvider);
    final p = context.alloy;
    final state = conn?.session.state.value;
    final (color, text) = switch (state) {
      null => (p.hairline, 'Off'),
      SessionState.ready => (AlloyPalette.ok, conn!.session.link.descriptor.kind.name.toUpperCase()),
      SessionState.lost => (AlloyPalette.critical, 'Lost'),
      _ => (AlloyPalette.caution, '…'),
    };
    return Tooltip(
      message: conn?.config.title ?? 'Not connected',
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 3),
            Text(
              text,
              style: AlloyText.mono(10, weight: FontWeight.w500, color: p.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Parameter download after connecting, on every page: a thin bar along the
/// top and a capsule at the bottom with the count; a retry if it fails; a
/// short confirmation when it completes.
class _ParamLoadBanner extends ConsumerStatefulWidget {
  const _ParamLoadBanner();

  @override
  ConsumerState<_ParamLoadBanner> createState() => _ParamLoadBannerState();
}

class _ParamLoadBannerState extends ConsumerState<_ParamLoadBanner> {
  bool _showDone = false;
  bool _dismissed = false;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(paramProgressProvider, (prev, next) {
      if (next.state == ParamLoadState.loading) _dismissed = false;
      if (next.state == ParamLoadState.complete && prev?.state == ParamLoadState.loading) {
        _hide?.cancel();
        setState(() => _showDone = true);
        _hide = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showDone = false);
        });
      }
    });
    final pr = ref.watch(paramProgressProvider);
    final p = context.alloy;
    final loading = pr.state == ParamLoadState.loading;
    final failed = pr.state == ParamLoadState.failed && !_dismissed;
    if (!loading && !failed && !_showDone) return const SizedBox.shrink();

    final capsule = Glass(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      radius: Alloy.radiusCapsule,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Icon(
            failed ? LucideIcons.triangleAlert : (loading ? LucideIcons.download : LucideIcons.circleCheck),
            size: 18,
            color: failed ? AlloyPalette.warning : (loading ? p.ink2 : p.okInk),
          ),
          if (loading)
            SizedBox(
              width: 220,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Text(
                    pr.total == 0 ? 'Reading parameters…' : 'Reading parameters  ${pr.received} / ${pr.total}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: pr.total == 0 ? null : pr.fraction, minHeight: 4),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: Text(
                failed
                    ? (pr.message ?? 'Parameter download failed')
                    : '${pr.received} parameters read from the vehicle',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (failed) ...[
            AlloyButton(label: 'Retry', onPressed: () => ref.read(paramServiceProvider)?.refresh()),
            GlassIconButton(
              icon: LucideIcons.x,
              tooltip: 'Dismiss',
              onPressed: () => setState(() => _dismissed = true),
            ),
          ] else
            const SizedBox(width: 4),
        ],
      ),
    );
    return Stack(
      children: [
        if (loading)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: LinearProgressIndicator(value: pr.total == 0 ? null : pr.fraction, minHeight: 3),
            ),
          ),
        // Above the bottom panels' row, centred, so it covers nothing it shouldn't for long.
        Positioned(left: 0, right: 0, bottom: 96, child: Center(child: capsule)),
      ],
    );
  }
}
