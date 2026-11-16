// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:apx_mission/apx_mission.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../design/components.dart';
import '../design/fields.dart';
import '../design/tokens.dart';
import '../map/map_dialogs.dart';
import '../state/connection.dart';
import '../state/plan.dart';
import 'element_editors.dart';

abstract final class PlanFileTypes {
  static const apxplan = XTypeGroup(
    label: 'APX plan',
    extensions: ['apxplan'],
    uniformTypeIdentifiers: ['public.json'],
  );
  static const standardPlan = XTypeGroup(
    label: 'Standard .plan',
    extensions: ['plan'],
    uniformTypeIdentifiers: ['public.json'],
  );
  static const waypoints = XTypeGroup(
    label: 'Standard .waypoints',
    extensions: ['waypoints', 'txt'],
    uniformTypeIdentifiers: ['public.plain-text'],
  );
}

/// Saves [text] where the user chooses. Android/iOS have no save dialog in
/// file_selector, so plans go to the app's documents folder ("APX Plans").
Future<String?> saveTextFile(BuildContext context, String suggestedName, String text, XTypeGroup type) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}APX Plans')
      ..createSync(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}$suggestedName')..writeAsStringSync(text);
    return f.path;
  }
  final loc = await getSaveLocation(suggestedName: suggestedName, acceptedTypeGroups: [type]);
  if (loc == null) return null;
  var path = loc.path;
  final ext = type.extensions!.first;
  if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
  File(path).writeAsStringSync(text);
  return path;
}

/// The mission list, editors, summary and vehicle transfer.
class PlanPanel extends ConsumerStatefulWidget {
  const PlanPanel({super.key, required this.onZoomTo});
  final void Function(MissionElement? e) onZoomTo;

  @override
  ConsumerState<PlanPanel> createState() => _PlanPanelState();
}

class _PlanPanelState extends ConsumerState<PlanPanel> {
  bool _settingsOpen = false;
  bool _issuesOpen = false;
  String? _busy;

  PlanController get _ctl => ref.read(planProvider.notifier);

  Future<void> _open() async {
    final f = await openFile(acceptedTypeGroups: [PlanFileTypes.apxplan, PlanFileTypes.standardPlan, PlanFileTypes.waypoints]);
    if (f == null) return;
    try {
      final text = await f.readAsString();
      final name = f.name;
      final lower = name.toLowerCase();
      if (lower.endsWith('.apxplan')) {
        _ctl.load(PlanFiles.fromApxPlan(text), name: name);
      } else {
        final r = lower.endsWith('.plan')
            ? PlanFiles.fromQgcPlan(text, ids: _ctl.ids)
            : PlanFiles.fromWaypoints(text, ids: _ctl.ids);
        _ctl.load(
          r.plan.copyWith(payloads: ref.read(planProvider).plan.payloads),
          name: name,
          home: r.home,
        );
        if (r.warnings.isNotEmpty && mounted) await _showWarnings('Imported with changes', r.warnings);
      }
      widget.onZoomTo(null);
    } catch (e) {
      if (mounted) notify(context, 'Could not open ${f.name}: ${e is FormatException ? e.message : e}');
    }
  }

  String _baseName(String ext) {
    final n = ref.read(planProvider).fileName;
    final stem = (n == null || n.isEmpty) ? 'mission' : n.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return '$stem.$ext';
  }

  Future<void> _save() async {
    final plan = ref.read(planProvider).plan;
    try {
      final path = await saveTextFile(context, _baseName('apxplan'), PlanFiles.toApxPlan(plan), PlanFileTypes.apxplan);
      if (path == null) return;
      _ctl.markSaved(File(path).uri.pathSegments.last);
      if (mounted) notify(context, 'Saved $path');
    } catch (e) {
      if (mounted) notify(context, 'Could not save: $e');
    }
  }

  Future<void> _export(bool isStandardPlan) async {
    final (c, _) = ref.read(compiledPlanProvider);
    try {
      final path = isStandardPlan
          ? await saveTextFile(context, _baseName('plan'), PlanFiles.toQgcPlan(c), PlanFileTypes.standardPlan)
          : await saveTextFile(context, _baseName('waypoints'), PlanFiles.toWaypoints(c), PlanFileTypes.waypoints);
      if (path != null && mounted) notify(context, 'Exported $path');
    } catch (e) {
      if (mounted) notify(context, 'Could not export: $e');
    }
  }

  Future<void> _showWarnings(String title, List<String> warnings) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: c.alloy.plate,
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [for (final w in warnings.toSet()) Text('• $w')],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );

  Future<void> _transfer(String label, Future<void> Function(MissionLink link) work) async {
    final conn = ref.read(connectionProvider);
    if (conn == null || conn.session.state.value != SessionState.ready) {
      notify(context, 'Connect to the vehicle first.');
      return;
    }
    setState(() => _busy = label);
    try {
      await work(MissionLink(conn.session));
    } on TransferException catch (e) {
      if (mounted) notify(context, '$label failed: ${e.message}');
    } catch (e) {
      if (mounted) notify(context, '$label failed: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _upload() => _transfer('Upload', (link) async {
    final (c, _) = ref.read(compiledPlanProvider);
    await link.upload(c);
    if (mounted) notify(context, 'Uploaded ${c.stats.items} items and read them back: the vehicle has this mission.');
  });

  Future<void> _download() async {
    if (ref.read(planProvider).dirty &&
        !await confirm(
          context,
          'Replace this plan?',
          'The mission on the vehicle will replace your unsaved changes.',
          action: 'Replace',
        )) {
      return;
    }
    await _transfer('Download', (link) async {
      final r = await link.download();
      _ctl.load(
        r.plan.copyWith(payloads: ref.read(planProvider).plan.payloads),
        name: 'From vehicle',
        home: r.home,
      );
      widget.onZoomTo(null);
      if (r.warnings.isNotEmpty && mounted) await _showWarnings('Read from the vehicle', r.warnings);
    });
  }

  Future<void> _resume() async {
    final conn = ref.read(connectionProvider);
    if (conn == null) return;
    final s = conn.session.telemetry.snapshot;
    final (c, _) = ref.read(compiledPlanProvider);
    final result = await showDialog<(int, bool)>(
      context: context,
      builder: (_) =>
          _ResumeDialog(current: s.missionCurrent, total: c.items.length, onGround: !s.armed || s.altRel < 1),
    );
    if (result == null) return;
    final (seq, onGround) = result;
    await _transfer('Resume upload', (link) async {
      final r = resumeFrom(
        c,
        seq,
        onGround: onGround,
        takeoffAltitude: ref.read(planProvider).plan.settings.takeoffAltitude,
      );
      await link.upload(r);
      if (mounted) {
        notify(context, 'Resume mission uploaded (${r.items.length + 1} items). Start it from the Fly view.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final st = ref.watch(planProvider);
    final (compiled, issues) = ref.watch(compiledPlanProvider);
    final plan = st.plan;
    final errors = issues.where((i) => i.level == IssueLevel.error).toList();
    final warnings = issues.where((i) => i.level == IssueLevel.warning).toList();

    return Glass(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: 400,
          child: Column(
            children: [
              // Header: name and file actions.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Mission', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          Text(
                            '${(st.fileName == null || st.fileName!.isEmpty) ? 'Untitled' : st.fileName}${st.dirty ? ' · edited' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.ink2),
                          ),
                        ],
                      ),
                    ),
                    GlassIconButton(icon: LucideIcons.undo2, tooltip: 'Undo', onPressed: st.canUndo ? _ctl.undo : null),
                    GlassIconButton(icon: LucideIcons.redo2, tooltip: 'Redo', onPressed: st.canRedo ? _ctl.redo : null),
                    _DeleteMenu(
                      waypoints: plan.elements.whereType<WaypointElement>().length,
                      items: plan.elements.length,
                      onDelete: (onlyWaypoints) {
                        final n = onlyWaypoints
                            ? plan.elements.whereType<WaypointElement>().length
                            : plan.elements.length;
                        _ctl.removeWhere((e) => !onlyWaypoints || e is WaypointElement);
                        notify(context, 'Deleted $n ${onlyWaypoints ? 'waypoints' : 'items'}. Undo brings them back.');
                      },
                    ),
                    MenuAnchor(
                      builder: (context, m, _) => GlassIconButton(
                        icon: LucideIcons.ellipsis,
                        tooltip: 'File',
                        onPressed: () => m.isOpen ? m.close() : m.open(),
                      ),
                      menuChildren: [
                        MenuItemButton(
                          leadingIcon: const Icon(LucideIcons.filePlus, size: 16),
                          onPressed: () async {
                            if (!st.dirty ||
                                await confirm(
                                  context,
                                  'Start a new plan?',
                                  'Unsaved changes will be lost.',
                                  action: 'New',
                                )) {
                              _ctl.newPlan();
                            }
                          },
                          child: const Text('New plan'),
                        ),
                        MenuItemButton(
                          leadingIcon: const Icon(LucideIcons.folderOpen, size: 16),
                          onPressed: _open,
                          child: const Text('Open…'),
                        ),
                        MenuItemButton(
                          leadingIcon: const Icon(LucideIcons.save, size: 16),
                          onPressed: _save,
                          child: const Text('Save as .apxplan…'),
                        ),
                        const Divider(),
                        MenuItemButton(
                          leadingIcon: const Icon(LucideIcons.fileOutput, size: 16),
                          onPressed: () => _export(true),
                          child: const Text('Export .plan…'),
                        ),
                        MenuItemButton(
                          leadingIcon: const Icon(LucideIcons.fileOutput, size: 16),
                          onPressed: () => _export(false),
                          child: const Text('Export .waypoints…'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  buildDefaultDragHandles: false,
                  header: _SettingsCard(
                    settings: plan.settings,
                    open: _settingsOpen,
                    onToggle: () => setState(() => _settingsOpen = !_settingsOpen),
                    onChanged: _ctl.setSettings,
                  ),
                  itemCount: plan.elements.length,
                  onReorderItem: _ctl.reorder,
                  itemBuilder: (context, i) {
                    final e = plan.elements[i];
                    return _ElementTile(
                      key: ValueKey(e.id),
                      index: i,
                      element: e,
                      plan: plan,
                      compiled: compiled,
                      issues: issues.where((x) => x.elementId == e.id).toList(),
                      selected: st.selected == e.id,
                      onSelect: () {
                        _ctl.select(st.selected == e.id ? null : e.id);
                        if (st.selected != e.id) widget.onZoomTo(e);
                      },
                      onChanged: _ctl.replace,
                      onDelete: () => _ctl.remove(e.id),
                      onExplode: () => _ctl.explode(e.id, compiled),
                    );
                  },
                ),
              ),
              // Add actions that don't need the map.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: AlloyButton(
                        label: 'Action',
                        icon: LucideIcons.slidersHorizontal,
                        onPressed: () => _ctl.add(
                          CommandElement(
                            id: _ctl.ids.next(),
                            command: ApxCatalog.changeSpeed.id,
                            params: const {1: 1, 2: 5},
                          ),
                          at: _insertIndex(st),
                        ),
                      ),
                    ),
                    Expanded(
                      child: AlloyButton(
                        label: 'Payload',
                        icon: LucideIcons.plug,
                        onPressed: plan.payloads.isEmpty
                            ? null
                            : () => _ctl.add(
                                CommandElement(id: _ctl.ids.next(), payload: PayloadAction(plan.payloads.first.id)),
                                at: _insertIndex(st),
                              ),
                      ),
                    ),
                    Expanded(
                      child: AlloyButton(
                        label: 'Land',
                        icon: LucideIcons.planeLanding,
                        onPressed: () => _ctl.add(LandElement(id: _ctl.ids.next())),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),
              // Summary.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: plan.elements.isEmpty
                    ? Text('Add waypoints or a pattern with the tools on the right.', style: TextStyle(color: p.ink2))
                    : _Stats(compiled.stats),
              ),
              if (issues.any((i) => i.level != IssueLevel.info))
                InkWell(
                  onTap: () => setState(() => _issuesOpen = !_issuesOpen),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      spacing: 6,
                      children: [
                        Icon(
                          errors.isNotEmpty ? LucideIcons.circleX : LucideIcons.triangleAlert,
                          size: 16,
                          color: errors.isNotEmpty ? AlloyPalette.critical : AlloyPalette.caution,
                        ),
                        Expanded(
                          child: Text(
                            [
                              if (errors.isNotEmpty) '${errors.length} error${errors.length > 1 ? 's' : ''}',
                              if (warnings.isNotEmpty) '${warnings.length} warning${warnings.length > 1 ? 's' : ''}',
                            ].join(' · '),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Icon(_issuesOpen ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16),
                      ],
                    ),
                  ),
                ),
              if (_issuesOpen)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    children: [
                      for (final i in [...errors, ...warnings])
                        InkWell(
                          onTap: i.elementId == null ? null : () => _ctl.select(i.elementId),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text('• ${i.message}', style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ),
              // Vehicle transfer: the only part that follows live vehicle state,
              // so only it rebuilds with the telemetry tick.
              Consumer(
                builder: (context, ref, _) {
                  final conn = ref.watch(connectionProvider);
                  ref.watch(frameTickProvider);
                  final progress = conn != null && conn.session.isBound ? conn.session.missions.progress.value : null;
                  final ready = conn?.session.state.value == SessionState.ready;
                  final snap = conn?.session.telemetry.snapshot;
                  final canResume = ready && snap != null && snap.missionCurrent > 1 && compiled.items.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [
                        if (_busy != null && progress != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 4,
                            children: [
                              LinearProgressIndicator(
                                value: progress.total == 0 ? null : progress.done / progress.total,
                              ),
                              Text(
                                '$_busy… ${progress.done}/${progress.total}',
                                style: AlloyText.mono(12, color: p.ink2),
                              ),
                            ],
                          ),
                        Row(
                          spacing: 8,
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: !ready
                                    ? 'Connect to the vehicle first'
                                    : errors.isNotEmpty
                                    ? 'Fix the errors first'
                                    : '',
                                child: AlloyButton(
                                  label: 'Upload',
                                  icon: LucideIcons.upload,
                                  primary: true,
                                  expand: true,
                                  onPressed: ready && errors.isEmpty && _busy == null && plan.elements.isNotEmpty
                                      ? _upload
                                      : null,
                                ),
                              ),
                            ),
                            Expanded(
                              child: AlloyButton(
                                label: 'Download',
                                icon: LucideIcons.download,
                                expand: true,
                                onPressed: ready && _busy == null ? _download : null,
                              ),
                            ),
                            if (canResume)
                              AlloyButton(
                                label: 'Resume…',
                                icon: LucideIcons.skipForward,
                                onPressed: _busy == null ? _resume : null,
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// New actions go after the selected element, else at the end.
  int _insertIndex(PlanState st) {
    final i = st.plan.elements.indexWhere((e) => e.id == st.selected);
    return i < 0 ? st.plan.elements.length : i + 1;
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.settings, required this.open, required this.onToggle, required this.onChanged});
  final MissionSettings settings;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<MissionSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final s = settings;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(Alloy.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(Alloy.radiusControl),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                spacing: 10,
                children: [
                  Icon(LucideIcons.settings2, size: 18, color: p.ink2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mission settings', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${s.takeoff ? 'Take off to ${s.takeoffAltitude.round()} m' : 'No take‑off'} · '
                          '${s.speed == null ? 'vehicle speed' : '${s.speed} m/s'} · '
                          '${switch (s.finish) {
                            FinishAction.rtl => 'return home',
                            FinishAction.landHere => 'land at end',
                            FinishAction.hover => 'hover at end',
                          }}',
                          style: TextStyle(fontSize: 12, color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                  Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Start with a take‑off'),
                    value: s.takeoff,
                    onChanged: (v) => onChanged(s.copyWith(takeoff: v)),
                  ),
                  FieldGrid(
                    children: [
                      NumField(
                        label: 'Take‑off altitude',
                        unit: 'm',
                        value: s.takeoffAltitude,
                        min: 1,
                        max: 500,
                        enabled: s.takeoff,
                        onChanged: (v) => onChanged(s.copyWith(takeoffAltitude: v)),
                      ),
                      NumField(
                        label: 'Default altitude',
                        unit: 'm',
                        value: s.altitude,
                        min: 1,
                        max: 500,
                        help: 'Used for new waypoints and patterns',
                        onChanged: (v) => onChanged(s.copyWith(altitude: v)),
                      ),
                      OptionalNumField(
                        label: 'Speed',
                        unit: 'm/s',
                        value: s.speed,
                        fallback: 5,
                        min: 0.5,
                        max: 20,
                        defaultLabel: 'WPNAV_SPEED',
                        onChanged: (v) => onChanged(s.copyWith(speed: v, clearSpeed: v == null)),
                      ),
                      ChoiceField<FinishAction>(
                        label: 'At the end',
                        value: s.finish,
                        options: const {
                          FinishAction.rtl: 'Return home',
                          FinishAction.landHere: 'Land at last point',
                          FinishAction.hover: 'Hover',
                        },
                        onChanged: (v) => onChanged(s.copyWith(finish: v)),
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

class _ElementTile extends StatelessWidget {
  const _ElementTile({
    super.key,
    required this.index,
    required this.element,
    required this.plan,
    required this.compiled,
    required this.issues,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    required this.onDelete,
    required this.onExplode,
  });

  final int index;
  final MissionElement element;
  final MissionPlan plan;
  final CompiledMission compiled;
  final List<Issue> issues;
  final bool selected;
  final VoidCallback onSelect, onDelete, onExplode;
  final ValueChanged<MissionElement> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final e = element;
    final worst = issues.isEmpty ? null : issues.map((i) => i.level).reduce((a, b) => a.index > b.index ? a : b);
    final pattern = e is SurveyElement || e is CorridorElement || e is OrbitElement;
    // First vehicle item of this element (seq 0 is home).
    final firstSeq = compiled.items.indexWhere((i) => i.elementId == e.id);
    // Material so the editor's switches and list tiles show their ink.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? (p.brightness == Brightness.light ? Colors.white.withValues(alpha: 0.75) : p.canvas)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Alloy.radiusControl),
          side: BorderSide(color: selected ? AlloyPalette.accent : p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(Alloy.radiusControl),
              onTap: onSelect,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(LucideIcons.gripVertical, size: 16, color: p.ink2),
                      ),
                    ),
                    Icon(elementIcon(e), size: 18, color: selected ? p.accentInk : p.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${firstSeq < 0 ? '' : '${firstSeq + 1}  '}${e.title}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            elementSummary(e, plan, compiled),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.ink2),
                          ),
                        ],
                      ),
                    ),
                    if (worst != null && worst != IssueLevel.info)
                      Icon(
                        worst == IssueLevel.error ? LucideIcons.circleX : LucideIcons.triangleAlert,
                        size: 16,
                        color: worst == IssueLevel.error ? AlloyPalette.critical : AlloyPalette.caution,
                      ),
                  ],
                ),
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    for (final i in issues)
                      Text(
                        i.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: switch (i.level) {
                            IssueLevel.error => AlloyPalette.critical,
                            IssueLevel.warning => p.cautionInk,
                            IssueLevel.info => p.ink2,
                          },
                        ),
                      ),
                    ElementEditor(element: e, plan: plan, compiled: compiled, onChanged: onChanged),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (pattern)
                          OutlinedButton.icon(
                            icon: const Icon(LucideIcons.listTree, size: 16),
                            label: const Text('Convert to waypoints'),
                            onPressed: onExplode,
                          ),
                        OutlinedButton.icon(
                          icon: const Icon(LucideIcons.trash2, size: 16),
                          label: const Text('Delete'),
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats(this.s);
  final MissionStats s;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    String d(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.round()} m';
    final t = s.duration;
    // Short enough for the stats cell: "1 h 3 min", "59 min", "45 s".
    final time = t.inHours > 0
        ? '${t.inHours} h ${t.inMinutes % 60} min'
        : t.inMinutes > 0
        ? '${t.inMinutes + (t.inSeconds % 60 >= 30 ? 1 : 0)} min'
        : '${t.inSeconds} s';
    Widget cell(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AlloyText.mono(14, weight: FontWeight.w600)),
          Text(label, style: TextStyle(fontSize: 11, color: p.ink2)),
        ],
      ),
    );
    return Row(
      children: [
        cell('distance', d(s.distanceM)),
        cell('est. time', time),
        cell('items', '${s.items}'),
        cell(
          s.areaM2 > 0 ? 'area' : 'payload on',
          s.areaM2 > 0 ? '${(s.areaM2 / 10000).toStringAsFixed(2)} ha' : d(s.workDistanceM),
        ),
      ],
    );
  }
}

class _ResumeDialog extends StatefulWidget {
  const _ResumeDialog({required this.current, required this.total, required this.onGround});
  final int current, total;
  final bool onGround;
  @override
  State<_ResumeDialog> createState() => _ResumeDialogState();
}

class _ResumeDialogState extends State<_ResumeDialog> {
  late double _seq = widget.current.clamp(1, widget.total).toDouble();
  late bool _ground = widget.onGround;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.alloy.plate,
    title: const Text('Resume mission'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          const Text(
            'APX always starts a mission at the beginning, so this uploads a new mission that continues from the chosen '
            'item, restoring speed, heading and payload state.',
          ),
          NumField(
            label: 'Continue from item',
            value: _seq,
            integer: true,
            min: 1,
            max: widget.total.toDouble(),
            onChanged: (v) => setState(() => _seq = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vehicle is on the ground'),
            subtitle: const Text('Adds a take‑off first'),
            value: _ground,
            onChanged: (v) => setState(() => _ground = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, (_seq.round(), _ground)), child: const Text('Upload')),
    ],
  );
}

/// Bulk delete: every waypoint, or the whole mission (one undo step).
class _DeleteMenu extends StatelessWidget {
  const _DeleteMenu({required this.waypoints, required this.items, required this.onDelete});
  final int waypoints, items;
  final void Function(bool onlyWaypoints) onDelete;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    builder: (context, m, _) => GlassIconButton(
      icon: LucideIcons.trash2,
      tooltip: 'Delete…',
      onPressed: items == 0 ? null : () => m.isOpen ? m.close() : m.open(),
    ),
    menuChildren: [
      MenuItemButton(
        leadingIcon: const Icon(LucideIcons.mapPin, size: 16),
        onPressed: waypoints == 0 ? null : () => onDelete(true),
        child: Text('Delete all waypoints ($waypoints)'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(LucideIcons.trash2, size: 16, color: AlloyPalette.warning),
        onPressed: () => onDelete(false),
        child: Text('Delete all items ($items)'),
      ),
    ],
  );
}
