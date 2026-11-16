// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:apx_geo/apx_geo.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/fields.dart';
import '../design/tokens.dart';
import '../map/map_dialogs.dart';
import '../state/map_tiles.dart';

/// Settings → Maps: keys, cache, offline and LAN, custom and local sources.
class MapSettingsSection extends ConsumerWidget {
  const MapSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    final s = ref.watch(mapSettingsProvider);
    final ctl = ref.read(mapSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Offline and cache',
          subtitle: 'Every tile you view is kept here, so the map works where there is no signal.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CacheCard(),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offline mode'),
                subtitle: const Text('Never fetch tiles; show only what is cached or in offline files.'),
                value: s.offline,
                onChanged: ctl.setOffline,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Share tiles on the local network'),
                subtitle: const _LanAddress(),
                value: s.shareOnLan,
                onChanged: ctl.setShareOnLan,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Offline map files',
          subtitle: 'MBTiles files or z/x/y tile folders, used as base maps without a connection.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in s.local)
                _SourceRow(
                  icon: l['kind'] == 'mbtiles' ? LucideIcons.database : LucideIcons.folder,
                  title: (l['name'] as String?) ?? File(l['path'] as String).uri.pathSegments.last,
                  subtitle: l['path'] as String,
                  onRemove: () => ctl.removeLocal(l['id'] as String),
                ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AlloyButton(
                    label: 'Add MBTiles file…',
                    icon: LucideIcons.database,
                    onPressed: () => _addLocal(context, ref, mbtiles: true),
                  ),
                  AlloyButton(
                    label: 'Add tile folder…',
                    icon: LucideIcons.folderOpen,
                    onPressed: () => _addLocal(context, ref, mbtiles: false),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Custom map sources',
          subtitle: 'Your own XYZ tile server or WMS service.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in s.custom)
                _SourceRow(
                  icon: c.kind == 'wms' ? LucideIcons.server : LucideIcons.globe,
                  title: c.name,
                  subtitle: c.kind == 'wms' ? 'WMS · ${c.layers}' : c.template,
                  onRemove: () => ctl.removeCustom(c.id),
                ),
              AlloyButton(
                label: 'Add XYZ or WMS source…',
                icon: LucideIcons.plus,
                onPressed: () async {
                  final c = await showDialog<CustomSource>(
                    context: context,
                    builder: (_) => const _CustomSourceDialog(),
                  );
                  if (c != null) ctl.addCustom(c);
                },
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Online map providers (optional)',
          subtitle: 'OpenStreetMap, Esri, Gaode and Baidu work without a key. Keys stay on this computer.',
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '${s.keys.length} of ${KeyService.all.length} keys entered',
                style: TextStyle(color: p.ink2, fontSize: 13),
              ),
              children: [for (final k in KeyService.all) _KeyField(service: k, saved: s.keys[k.id] ?? '')],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addLocal(BuildContext context, WidgetRef ref, {required bool mbtiles}) async {
    final id = 'local-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    try {
      final LocalTileSource src;
      if (mbtiles) {
        final f = await openFile(acceptedTypeGroups: [FileTypes.mbtiles]);
        if (f == null) return;
        src = MbTilesSource.open(id, f.path);
      } else {
        final dir = await getDirectoryPath(confirmButtonText: 'Use folder');
        if (dir == null) return;
        src = FolderSource(id, dir);
      }
      ref.read(mapSettingsProvider.notifier).addLocal(src);
      if (context.mounted) notify(context, 'Added "${src.name}". Choose it under Map layers.');
    } catch (e) {
      if (context.mounted) notify(context, e is FormatException ? e.message : '$e');
    }
  }
}

class _KeyField extends ConsumerStatefulWidget {
  const _KeyField({required this.service, required this.saved});
  final KeyService service;
  final String saved;

  @override
  ConsumerState<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends ConsumerState<_KeyField> {
  late final _c = TextEditingController(text: widget.saved);
  bool _show = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final engine = ref.watch(tileEngineProvider).value;
    final providers = MapProviders.builtIn.where((x) => x.key?.id == widget.service.id);
    final problem = engine == null
        ? null
        : providers
              .map((x) => engine.service.health(x.id))
              .where((h) => h.keyProblem && h.lastError != null)
              .firstOrNull;
    final dirty = _c.text.trim() != widget.saved;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: TextField(
                    controller: _c,
                    obscureText: !_show,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: widget.service.name,
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: _show ? 'Hide' : 'Show',
                        icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                ),
                AlloyButton(
                  label: 'Save',
                  primary: dirty,
                  onPressed: dirty
                      ? () {
                          ref.read(mapSettingsProvider.notifier).setKey(widget.service.id, _c.text);
                          setState(() {});
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              [
                'Get a key: ${widget.service.consoleUrl}',
                if (widget.service.note != null) widget.service.note!,
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: p.ink2),
            ),
            if (problem != null)
              Text(problem.lastError!, style: const TextStyle(fontSize: 12, color: AlloyPalette.warning))
            else if (widget.saved.isNotEmpty && !dirty)
              Text('Saved.', style: TextStyle(fontSize: 12, color: p.okInk)),
          ],
        ),
      ),
    );
  }
}

class _CacheCard extends ConsumerStatefulWidget {
  const _CacheCard();

  @override
  ConsumerState<_CacheCard> createState() => _CacheCardState();
}

class _CacheCardState extends ConsumerState<_CacheCard> {
  static const _limits = [512, 1024, 2048, 4096, 8192, 16384];

  static String _size(int bytes) => bytes >= 1 << 30
      ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB'
      : '${(bytes / (1 << 20)).toStringAsFixed(bytes < 10 << 20 ? 1 : 0)} MB';

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final engine = ref.watch(tileEngineProvider);
    final limit = ref.watch(mapSettingsProvider.select((s) => s.cacheLimitMb));
    final e = engine.value;
    if (e == null) {
      return Text(
        engine.hasError ? 'Tile server failed to start: ${engine.error}' : 'Starting…',
        style: TextStyle(color: p.ink2),
      );
    }
    final usage = e.service.cache.usage();
    final pinned = usage.where((u) => u.pinned).fold<int>(0, (n, u) => n + u.bytes);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            '${_size(e.service.cache.sizeBytes)} used · ${_size(pinned)} of it kept (overlays, downloaded areas)',
            style: AlloyText.mono(13),
          ),
          Text(e.cachePath, style: TextStyle(fontSize: 11, color: p.ink2)),
          Row(
            spacing: 10,
            children: [
              Text('Limit for browsing cache', style: TextStyle(color: p.ink2)),
              DropdownButton<int>(
                value: _limits.contains(limit) ? limit : 2048,
                items: [for (final l in _limits) DropdownMenuItem(value: l, child: Text(_size(l << 20)))],
                onChanged: (v) => ref.read(mapSettingsProvider.notifier).setCacheLimit(v!),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AlloyButton(
                label: 'Clear browsing cache',
                icon: LucideIcons.eraser,
                onPressed: () => setState(() => e.service.cache.clear(keepPinned: true)),
              ),
              AlloyButton(
                label: 'Also delete downloaded areas',
                icon: LucideIcons.trash2,
                onPressed: () async {
                  if (!await confirm(
                    this.context,
                    'Delete downloaded areas?',
                    'Areas downloaded for offline use will be removed. Overlays are kept.',
                    action: 'Delete',
                  )) {
                    return;
                  }
                  setState(() {
                    for (final u in e.service.cache.usage()) {
                      if (!u.source.startsWith('overlay-')) e.service.cache.clear(source: u.source);
                    }
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanAddress extends ConsumerWidget {
  const _LanAddress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(mapSettingsProvider.select((s) => s.shareOnLan));
    final port = ref.watch(tileEngineProvider).value?.server.port;
    if (!on || port == null) return const Text('Lets a tablet on the same network use this computer\'s map cache.');
    return FutureBuilder(
      future: NetworkInterface.list(type: InternetAddressType.IPv4),
      builder: (context, snap) {
        final addrs = [for (final i in snap.data ?? const <NetworkInterface>[]) ...i.addresses.map((a) => a.address)];
        return SelectableText(
          addrs.isEmpty
              ? 'Listening on port $port'
              : addrs.map((a) => 'http://$a:$port/tiles/<map>/{z}/{x}/{y}').join('\n'),
        );
      },
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.icon, required this.title, required this.subtitle, required this.onRemove});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 620),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(tooltip: 'Remove', icon: const Icon(LucideIcons.trash2, size: 18), onPressed: onRemove),
    ),
  );
}

class _CustomSourceDialog extends StatefulWidget {
  const _CustomSourceDialog();
  @override
  State<_CustomSourceDialog> createState() => _CustomSourceDialogState();
}

class _CustomSourceDialogState extends State<_CustomSourceDialog> {
  String _kind = 'xyz';
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _layers = TextEditingController();
  final _attribution = TextEditingController();
  final _maxZoom = TextEditingController(text: '19');
  String? _error;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return AlertDialog(
      backgroundColor: p.plate,
      title: const Text('Custom map source'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'xyz', label: Text('XYZ tiles')),
                ButtonSegment(value: 'wms', label: Text('WMS')),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.single),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', isDense: true),
            ),
            TextField(
              controller: _url,
              decoration: InputDecoration(
                labelText: _kind == 'xyz' ? 'URL template' : 'WMS service URL',
                hintText: _kind == 'xyz' ? 'https://example.com/{z}/{x}/{y}.png' : 'https://example.com/wms',
                helperText: _kind == 'xyz'
                    ? '{z} {x} {y}; also {-y} (TMS), {s} (a/b/c), {q} (quadkey)'
                    : 'Requested as EPSG:3857, PNG',
                isDense: true,
              ),
            ),
            if (_kind == 'wms')
              TextField(
                controller: _layers,
                decoration: const InputDecoration(labelText: 'Layer name(s)', isDense: true),
              ),
            Row(
              spacing: 10,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _maxZoom,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max zoom', isDense: true),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _attribution,
                    decoration: const InputDecoration(labelText: 'Attribution (shown on the map)', isDense: true),
                  ),
                ),
              ],
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AlloyPalette.warning)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final c = CustomSource(
              id: 'custom-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
              name: _name.text.trim(),
              kind: _kind,
              template: _url.text.trim(),
              layers: _layers.text.trim(),
              attribution: _attribution.text.trim(),
              maxZoom: (int.tryParse(_maxZoom.text) ?? 19).clamp(1, 23),
            );
            final err = c.validate();
            if (err != null) {
              setState(() => _error = err);
            } else {
              Navigator.pop(context, c);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
