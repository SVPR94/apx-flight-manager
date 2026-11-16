// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_geo/apx_geo.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../state/connection.dart';
import '../state/map_tiles.dart';
import '../state/overlays.dart';
import 'map_dialogs.dart';

/// Base map choice, offline controls and overlays, floating over a map.
class LayersPanel extends ConsumerWidget {
  const LayersPanel({
    super.key,
    required this.camera,
    required this.onClose,
    required this.onZoomTo,
    required this.onEditCorners,
  });

  final MapCamera Function() camera;
  final VoidCallback onClose;
  final void Function(GeoBounds) onZoomTo;
  final void Function(OverlayItem) onEditCorners;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    ref.watch(frameTickProvider); // provider health changes without a rebuild signal
    final settings = ref.watch(mapSettingsProvider);
    final choices = ref.watch(baseMapChoicesProvider);
    final current = ref.watch(currentBaseMapProvider);
    final engine = ref.watch(tileEngineProvider);
    final health = engine.value?.service.health(current.id);
    final groups = <String, List<BaseMapChoice>>{};
    for (final c in choices) {
      groups.putIfAbsent(c.group, () => []).add(c);
    }
    final canDownload = current.provider != null && (current.provider!.allowsBulkDownload || current.provider!.custom);

    return Glass(
      padding: EdgeInsets.zero,
      // Transparent Material so list rows and switches can show their ink on the glass.
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Map layers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    GlassIconButton(icon: LucideIcons.x, tooltip: 'Close', onPressed: onClose),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (engine.hasError)
                      Text(
                        'Tile server failed to start: ${engine.error}',
                        style: const TextStyle(color: AlloyPalette.warning),
                      ),
                    const Caption('Base map'),
                    const SizedBox(height: 6),
                    for (final g in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 2),
                        child: Text(
                          g.key,
                          style: TextStyle(fontSize: 12, color: p.ink2, fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (final c in g.value)
                        _ChoiceRow(
                          choice: c,
                          selected: c.id == current.id,
                          onTap: () => ref.read(mapSettingsProvider.notifier).setBaseMap(c.id),
                        ),
                    ],
                    if (current.needsKey != null)
                      _Notice('Add a ${current.needsKey!.name} key in Settings → Maps to use this map.'),
                    if (current.needsKey == null && health?.lastError != null) _Notice(health!.lastError!),
                    const SizedBox(height: 14),
                    const Caption('Offline'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Offline mode'),
                      subtitle: const Text('Use cached tiles only'),
                      value: settings.offline,
                      onChanged: (v) => ref.read(mapSettingsProvider.notifier).setOffline(v),
                    ),
                    AlloyButton(
                      label: 'Download visible area…',
                      icon: LucideIcons.download,
                      expand: true,
                      onPressed: engine.value == null || !canDownload
                          ? null
                          : () => showDownloadDialog(context, engine.value!.service, current.id, camera()),
                    ),
                    if (!canDownload)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          current.provider == null
                              ? 'This map is already a local file.'
                              : '${current.name} doesn\'t allow area downloads; tiles you view are still cached. '
                                    'Use an MBTiles file or a custom source for planned offline work.',
                          style: TextStyle(fontSize: 12, color: p.ink2),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Caption('Overlays'),
                    const SizedBox(height: 6),
                    _OverlayList(onZoomTo: onZoomTo, onEditCorners: onEditCorners),
                    const SizedBox(height: 8),
                    _AddOverlayButton(camera: camera, onAdded: onZoomTo),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.choice, required this.selected, required this.onTap});
  final BaseMapChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Material(
      color: selected ? p.accentBg : Colors.transparent,
      borderRadius: BorderRadius.circular(Alloy.radiusControl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Alloy.radiusControl),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            spacing: 8,
            children: [
              Icon(
                choice.imagery ? LucideIcons.satellite : LucideIcons.map,
                size: 16,
                color: selected ? p.accentInk : p.ink2,
              ),
              Expanded(
                child: Text(
                  choice.name,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? p.accentInk : p.ink,
                  ),
                ),
              ),
              if (choice.needsKey != null) Text('needs key', style: TextStyle(fontSize: 11, color: p.ink2)),
              if (selected) Icon(LucideIcons.check, size: 16, color: p.accentInk),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: context.alloy.cautionBg, borderRadius: BorderRadius.circular(Alloy.radiusControl)),
    child: Text(text, style: TextStyle(fontSize: 12, color: context.alloy.cautionInk)),
  );
}

class _OverlayList extends ConsumerWidget {
  const _OverlayList({required this.onZoomTo, required this.onEditCorners});
  final void Function(GeoBounds) onZoomTo;
  final void Function(OverlayItem) onEditCorners;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(overlaysProvider);
    final p = context.alloy;
    if (items.isEmpty) {
      return Text(
        'GeoTIFFs, images, Shapefiles and GeoJSON you add appear here.',
        style: TextStyle(fontSize: 12, color: p.ink2),
      );
    }
    final ctl = ref.read(overlaysProvider.notifier);
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: ctl.reorder,
      children: [
        for (final (i, o) in items.indexed)
          Container(
            key: ValueKey(o.spec.id),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            decoration: BoxDecoration(
              border: Border.all(color: p.hairline),
              borderRadius: BorderRadius.circular(Alloy.radiusControl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(LucideIcons.gripVertical, size: 16, color: p.ink2),
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: Color(o.spec.colour), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.spec.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (o.spec.detail.isNotEmpty)
                            Text(o.spec.detail, maxLines: 2, style: TextStyle(fontSize: 11, color: p.ink2)),
                        ],
                      ),
                    ),
                    Checkbox(
                      value: o.spec.visible,
                      onChanged: o.busy ? null : (v) => ctl.setVisible(o.spec.id, v ?? true),
                    ),
                  ],
                ),
                if (o.busy) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: LinearProgressIndicator(value: o.progress == 0 ? null : o.progress),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Text(
                      o.spec.isRaster ? 'Rendering tiles… ${((o.progress ?? 0) * 100).round()} %' : 'Reading…',
                      style: TextStyle(fontSize: 11, color: p.ink2),
                    ),
                  ),
                ],
                if (o.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(o.error!, style: const TextStyle(fontSize: 12, color: AlloyPalette.warning)),
                  ),
                if (!o.busy)
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      Icon(LucideIcons.blend, size: 14, color: p.ink2),
                      Expanded(
                        child: Slider(value: o.spec.opacity, min: 0.1, onChanged: (v) => ctl.setOpacity(o.spec.id, v)),
                      ),
                      if (o.spec.bounds != null)
                        IconButton(
                          tooltip: 'Zoom to',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(LucideIcons.scan, size: 17),
                          onPressed: () => onZoomTo(o.spec.bounds!),
                        ),
                      if (o.spec.kind == OverlayKind.image)
                        IconButton(
                          tooltip: 'Adjust corners on the map',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(LucideIcons.move, size: 17),
                          onPressed: () => onEditCorners(o),
                        ),
                      IconButton(
                        tooltip: 'Remove',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(LucideIcons.trash2, size: 17),
                        onPressed: () async {
                          if (await confirm(
                            context,
                            'Remove overlay?',
                            '"${o.spec.name}" and its rendered tiles will be removed.',
                          )) {
                            await ctl.remove(o.spec.id);
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AddOverlayButton extends ConsumerWidget {
  const _AddOverlayButton({required this.camera, required this.onAdded});
  final MapCamera Function() camera;
  final void Function(GeoBounds) onAdded;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<String?> Function() work) async {
    try {
      final id = await work();
      if (id == null) return;
      final item = ref.read(overlaysProvider.notifier).byId(id);
      if (item?.error != null && context.mounted) notify(context, item!.error!);
      if (item?.spec.bounds != null) onAdded(item!.spec.bounds!);
    } catch (e) {
      if (context.mounted) notify(context, e is FormatException ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(overlaysProvider.notifier);
    String? lastId() => ref.read(overlaysProvider).lastOrNull?.spec.id;
    return MenuAnchor(
      builder: (context, menu, _) => AlloyButton(
        label: 'Add overlay…',
        icon: LucideIcons.plus,
        expand: true,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(LucideIcons.grid3x3, size: 16),
          child: const Text('GeoTIFF'),
          onPressed: () => _run(context, ref, () async {
            final f = await openFile(acceptedTypeGroups: [FileTypes.geotiff]);
            if (f == null) return null;
            await ctl.importGeoTiff(await readPicked(f));
            return lastId();
          }),
        ),
        MenuItemButton(
          leadingIcon: const Icon(LucideIcons.image, size: 16),
          child: const Text('Image (PNG / JPG)'),
          onPressed: () => _run(context, ref, () async {
            final f = await openFile(acceptedTypeGroups: [FileTypes.image]);
            if (f == null) return null;
            final picked = await readPicked(f);
            var placement = OverlaysController.worldFileFor(picked);
            if (placement == null) {
              if (!context.mounted) return null;
              placement = await askImagePlacement(context, picked.bytes, camera());
              if (placement == null) return null;
            }
            await ctl.importImage(picked, placement);
            return lastId();
          }),
        ),
        MenuItemButton(
          leadingIcon: const Icon(LucideIcons.braces, size: 16),
          child: const Text('GeoJSON (.geojson)'),
          onPressed: () => _run(context, ref, () async {
            final files = await openFiles(acceptedTypeGroups: [FileTypes.geojson]);
            if (files.isEmpty) return null;
            await ctl.importVector([for (final f in files) await readPicked(f)]);
            return lastId();
          }),
        ),
        MenuItemButton(
          leadingIcon: const Icon(LucideIcons.shapes, size: 16),
          child: const Text('Shapefile (.shp or .zip)'),
          onPressed: () => _run(context, ref, () async {
            final files = await openFiles(acceptedTypeGroups: [FileTypes.shapefile]);
            if (files.isEmpty) return null;
            await ctl.importVector([for (final f in files) await readPicked(f)]);
            return lastId();
          }),
        ),
      ],
    );
  }
}
