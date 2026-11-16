// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_geo/apx_geo.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image/image.dart' as img;

import '../design/tokens.dart';
import '../state/overlays.dart';
import 'map_layers.dart';

/// File type groups for the pickers. macOS needs UTIs, Linux/Windows use
/// the extensions.
abstract final class FileTypes {
  static const geotiff = XTypeGroup(
    label: 'GeoTIFF',
    extensions: ['tif', 'tiff'],
    uniformTypeIdentifiers: ['public.tiff'],
  );
  static const image = XTypeGroup(
    label: 'Image',
    extensions: ['png', 'jpg', 'jpeg'],
    uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
  );
  static const shapefile = XTypeGroup(
    label: 'Shapefile',
    extensions: ['shp', 'shx', 'dbf', 'prj', 'cpg', 'zip'],
    uniformTypeIdentifiers: ['public.data', 'public.zip-archive'],
  );
  static const geojson = XTypeGroup(
    label: 'GeoJSON',
    extensions: ['geojson', 'json'],
    uniformTypeIdentifiers: ['public.json', 'public.data'],
  );
  static const mbtiles = XTypeGroup(label: 'MBTiles', extensions: ['mbtiles'], uniformTypeIdentifiers: ['public.data']);
}

Future<PickedFile> readPicked(XFile f) async =>
    (name: f.name, path: f.path.isEmpty ? null : f.path, bytes: await f.readAsBytes());

/// Asks where a plain image goes: centre + ground size + rotation, or four
/// corner coordinates. Defaults put it in the middle of the current view.
Future<ImagePlacement?> askImagePlacement(BuildContext context, Uint8List bytes, MapCamera camera) {
  final info = img.findDecoderForData(bytes)?.startDecode(bytes);
  final aspect = info == null || info.width == 0 ? 1.5 : info.width / info.height;
  final centre = toGeo(camera.center);
  final view = camera.visibleBounds;
  final viewWidth = haversineMetres(GeoPoint(centre.lat, view.west), GeoPoint(centre.lat, view.east));
  final w = math.max(10.0, (viewWidth * 0.5).roundToDouble());
  return showDialog<ImagePlacement>(
    context: context,
    builder: (_) => _PlacementDialog(
      initial: CentrePlacement(center: centre, widthMetres: w, heightMetres: (w / aspect).roundToDouble()),
    ),
  );
}

class _PlacementDialog extends StatefulWidget {
  const _PlacementDialog({required this.initial});
  final CentrePlacement initial;

  @override
  State<_PlacementDialog> createState() => _PlacementDialogState();
}

class _PlacementDialogState extends State<_PlacementDialog> {
  bool _corners = false;
  late final _lat = TextEditingController(text: widget.initial.center.lat.toStringAsFixed(7));
  late final _lon = TextEditingController(text: widget.initial.center.lon.toStringAsFixed(7));
  late final _w = TextEditingController(text: widget.initial.widthMetres.toStringAsFixed(0));
  late final _h = TextEditingController(text: widget.initial.heightMetres.toStringAsFixed(0));
  final _rot = TextEditingController(text: '0');
  late final List<TextEditingController> _cornerFields = [
    for (final c in widget.initial.corners(1, 1))
      TextEditingController(text: '${c.lat.toStringAsFixed(7)}, ${c.lon.toStringAsFixed(7)}'),
  ];
  String? _error;

  static const _cornerNames = ['Top left', 'Top right', 'Bottom right', 'Bottom left'];

  ImagePlacement? _build() {
    double? n(TextEditingController c) => double.tryParse(c.text.trim());
    if (!_corners) {
      final la = n(_lat), lo = n(_lon), w = n(_w), h = n(_h), r = n(_rot) ?? 0;
      if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180) {
        return _fail('Enter the centre as latitude and longitude in degrees.');
      }
      if (w == null || h == null || w <= 0 || h <= 0) return _fail('Width and height must be positive metres.');
      return CentrePlacement(center: GeoPoint(la, lo), widthMetres: w, heightMetres: h, rotationDeg: r);
    }
    final pts = <GeoPoint>[];
    for (final (i, c) in _cornerFields.indexed) {
      final parts = c.text.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).map(double.tryParse).toList();
      if (parts.length != 2 || parts.contains(null) || parts[0]!.abs() > 90 || parts[1]!.abs() > 180) {
        return _fail('${_cornerNames[i]}: enter "latitude, longitude".');
      }
      pts.add(GeoPoint(parts[0]!, parts[1]!));
    }
    try {
      final p = CornerPlacement(pts);
      // Reject degenerate (crossed or collinear) corners now, not at render time.
      ImageOverlay.place(RgbaRaster(2, 2), p);
      return p;
    } catch (_) {
      return _fail('Those corners don\'t form a usable four‑sided shape. Check their order.');
    }
  }

  ImagePlacement? _fail(String m) {
    setState(() => _error = m);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final num = const TextInputType.numberWithOptions(decimal: true, signed: true);
    final fmt = [FilteringTextInputFormatter.allow(RegExp(r'[-0-9., ]'))];
    Widget field(String label, TextEditingController c, {String? suffix}) => TextField(
      controller: c,
      keyboardType: num,
      inputFormatters: fmt,
      decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
    );
    return AlertDialog(
      backgroundColor: p.plate,
      title: const Text('Place image'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              'No world file was found next to this image. Say where it goes; you can drag its corners on the map afterwards.',
              style: TextStyle(color: p.ink2),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Centre & size')),
                ButtonSegment(value: true, label: Text('Four corners')),
              ],
              selected: {_corners},
              onSelectionChanged: (v) => setState(() => _corners = v.single),
            ),
            if (!_corners) ...[
              Row(
                spacing: 10,
                children: [
                  Expanded(child: field('Centre latitude', _lat)),
                  Expanded(child: field('Centre longitude', _lon)),
                ],
              ),
              Row(
                spacing: 10,
                children: [
                  Expanded(child: field('Width', _w, suffix: 'm')),
                  Expanded(child: field('Height', _h, suffix: 'm')),
                  Expanded(child: field('Rotation', _rot, suffix: '°')),
                ],
              ),
            ] else
              for (final (i, c) in _cornerFields.indexed) field('${_cornerNames[i]} (lat, lon)', c),
            if (_error != null) Text(_error!, style: const TextStyle(color: AlloyPalette.warning)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final r = _build();
            if (r != null) Navigator.pop(context, r);
          },
          child: const Text('Place'),
        ),
      ],
    );
  }
}

/// Offline download of the visible area for the current map.
Future<void> showDownloadDialog(BuildContext context, TileService service, String providerId, MapCamera camera) {
  final b = camera.visibleBounds;
  final bounds = GeoBounds(b.south, b.west, b.north, b.east);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _DownloadDialog(service: service, providerId: providerId, bounds: bounds, zoom: camera.zoom.floor()),
  );
}

class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.service, required this.providerId, required this.bounds, required this.zoom});
  final TileService service;
  final String providerId;
  final GeoBounds bounds;
  final int zoom;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  late final int _max = widget.service.provider(widget.providerId)?.maxZoom ?? 19;
  late RangeValues _range = RangeValues(
    widget.zoom.clamp(0, _max).toDouble(),
    math.min(widget.zoom + 3, _max).toDouble(),
  );
  DownloadProgress? _progress;
  String? _message;
  bool _cancel = false;
  bool _running = false;

  int get _count => WebMercator.countTiles(widget.bounds, _range.start.round(), _range.end.round());

  Future<void> _start() async {
    setState(() {
      _running = true;
      _message = null;
    });
    try {
      final r = await widget.service.download(
        widget.providerId,
        widget.bounds,
        _range.start.round(),
        _range.end.round(),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelled: () => _cancel,
      );
      _message = _cancel
          ? 'Stopped after ${r.done} of ${r.total} tiles.'
          : 'Done: ${r.done - r.failed} tiles saved${r.failed > 0 ? ', ${r.failed} unavailable' : ''}.';
    } on DownloadRefused catch (e) {
      _message = e.message;
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final pr = _progress;
    return AlertDialog(
      backgroundColor: p.plate,
      title: const Text('Download for offline use'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              'The area on screen, zoom ${_range.start.round()} to ${_range.end.round()}.',
              style: TextStyle(color: p.ink2),
            ),
            RangeSlider(
              values: _range,
              min: 0,
              max: _max.toDouble(),
              divisions: _max,
              labels: RangeLabels('${_range.start.round()}', '${_range.end.round()}'),
              onChanged: _running ? null : (v) => setState(() => _range = v),
            ),
            Text(
              '$_count tiles${_count > TileService.maxDownloadTiles ? ' — over the ${TileService.maxDownloadTiles} limit' : ''}',
              style: AlloyText.mono(13, color: _count > TileService.maxDownloadTiles ? AlloyPalette.warning : p.ink),
            ),
            if (pr != null) LinearProgressIndicator(value: pr.total == 0 ? null : pr.done / pr.total),
            if (pr != null && _running) Text('${pr.done} / ${pr.total}', style: AlloyText.mono(12, color: p.ink2)),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
      actions: [
        if (_running)
          TextButton(onPressed: () => setState(() => _cancel = true), child: const Text('Stop'))
        else ...[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          if (_message == null)
            FilledButton(
              onPressed: _count > TileService.maxDownloadTiles ? null : _start,
              child: const Text('Download'),
            ),
        ],
      ],
    );
  }
}

/// Confirms a destructive action.
Future<bool> confirm(BuildContext context, String title, String body, {String action = 'Remove'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: c.alloy.plate,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

/// A short error/notice in a snack bar.
void notify(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
