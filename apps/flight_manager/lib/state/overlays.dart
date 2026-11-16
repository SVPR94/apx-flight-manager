// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:apx_geo/apx_geo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_tiles.dart';
import 'storage.dart';

enum OverlayKind { geotiff, image, vector }

/// A file the user picked: name, bytes, and its path when the platform gives
/// one (desktop), which lets us find sidecar files (.prj, world files, .dbf).
typedef PickedFile = ({String name, String? path, Uint8List bytes});

/// Overlay line/fill colours: distinct from the accent and status colours.
const overlayColours = [0xFF7C5CE0, 0xFFD9468F, 0xFF2F7BD8, 0xFF5E9E2E, 0xFFB06A1E, 0xFF14967F];

/// What is saved about an overlay (settings.json → "overlays").
final class OverlaySpec {
  const OverlaySpec({
    required this.id,
    required this.name,
    required this.kind,
    this.revision = 0,
    this.visible = true,
    this.opacity = 1,
    this.bounds,
    this.files = const [],
    this.placement,
    this.colour = 0xFF7C5CE0,
    this.detail = '',
    this.maxZoom,
  });

  final String id, name;
  final OverlayKind kind;

  /// Bumped on every re‑render so the map reloads the new tiles.
  final int revision;
  final bool visible;
  final double opacity;
  final GeoBounds? bounds;

  /// File names inside `overlays/<id>/` (copies of what was imported).
  final List<String> files;
  final ImagePlacement? placement;
  final int colour;

  /// One line for the layer list, e.g. "WGS 84 / UTM zone 43N · 0.25 m/px".
  final String detail;

  /// Deepest rendered zoom (rasters); the map scales tiles up beyond it.
  final int? maxZoom;

  bool get isRaster => kind != OverlayKind.vector;

  /// Tile source id in the cache and on the tile server.
  String get sourceId => 'overlay-$id-r$revision';

  OverlaySpec copyWith({
    int? revision,
    bool? visible,
    double? opacity,
    GeoBounds? bounds,
    List<String>? files,
    ImagePlacement? placement,
    String? detail,
    String? name,
    int? maxZoom,
  }) => OverlaySpec(
    id: id,
    name: name ?? this.name,
    kind: kind,
    revision: revision ?? this.revision,
    visible: visible ?? this.visible,
    opacity: opacity ?? this.opacity,
    bounds: bounds ?? this.bounds,
    files: files ?? this.files,
    placement: placement ?? this.placement,
    colour: colour,
    detail: detail ?? this.detail,
    maxZoom: maxZoom ?? this.maxZoom,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'revision': revision,
    'visible': visible,
    'opacity': opacity,
    'bounds': bounds?.toJson(),
    'files': files,
    'placement': placement?.toJson(),
    'colour': colour,
    'detail': detail,
    'maxZoom': maxZoom,
  };

  factory OverlaySpec.fromJson(Map<String, Object?> j) => OverlaySpec(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: OverlayKind.values.byName(j['kind'] as String),
    revision: (j['revision'] as num?)?.toInt() ?? 0,
    visible: j['visible'] != false,
    opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
    bounds: j['bounds'] == null ? null : GeoBounds.fromJson((j['bounds'] as Map).cast()),
    files: (j['files'] as List? ?? const []).cast<String>(),
    placement: j['placement'] == null ? null : ImagePlacement.fromJson((j['placement'] as Map).cast()),
    colour: (j['colour'] as num?)?.toInt() ?? overlayColours.first,
    detail: j['detail'] as String? ?? '',
    maxZoom: (j['maxZoom'] as num?)?.toInt(),
  );
}

/// An overlay as the map sees it.
final class OverlayItem {
  const OverlayItem(this.spec, {this.layers = const [], this.progress, this.error});
  final OverlaySpec spec;

  /// Parsed features (vector overlays).
  final List<VectorLayer> layers;

  /// 0..1 while tiles are being rendered.
  final double? progress;
  final String? error;

  bool get busy => progress != null;

  OverlayItem copyWith({
    OverlaySpec? spec,
    List<VectorLayer>? layers,
    double? progress,
    bool clearProgress = false,
    String? error,
  }) => OverlayItem(
    spec ?? this.spec,
    layers: layers ?? this.layers,
    progress: clearProgress ? null : (progress ?? this.progress),
    error: error,
  );
}

/// Imported overlays: GeoTIFFs and placed images become tile pyramids in the
/// tile cache (rendered on a background isolate); Shapefiles and GeoJSON are kept as
/// features and drawn as vectors.
final class OverlaysController extends Notifier<List<OverlayItem>> {
  @override
  List<OverlayItem> build() {
    final saved = ref.read(settingsStoreProvider).get<List>('overlays') ?? const [];
    final items = <OverlayItem>[];
    for (final j in saved) {
      try {
        items.add(OverlayItem(OverlaySpec.fromJson((j as Map).cast())));
      } catch (_) {
        // Skip an entry from an incompatible version rather than fail start‑up.
      }
    }
    ref.read(tileEngineProvider.future).then((e) {
      for (final i in items.where((i) => i.spec.isRaster)) {
        e.service.registerOverlay(i.spec.sourceId);
      }
    }, onError: (_) {});
    for (final i in items.where((i) => i.spec.kind == OverlayKind.vector)) {
      unawaited(_loadVectors(i.spec));
    }
    return items;
  }

  Directory _dir(String id) =>
      Directory('${ref.read(dataDirProvider).path}${Platform.pathSeparator}overlays${Platform.pathSeparator}$id');

  void _persist() => ref.read(settingsStoreProvider).set('overlays', [for (final i in state) i.spec.toJson()]);

  void _put(OverlayItem item) {
    final i = state.indexWhere((x) => x.spec.id == item.spec.id);
    state = i < 0 ? [...state, item] : ([...state]..[i] = item);
    _persist();
  }

  OverlayItem? byId(String id) => state.where((i) => i.spec.id == id).firstOrNull;

  String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  int _nextColour() => overlayColours[state.length % overlayColours.length];

  // ---- import ---------------------------------------------------------------

  Future<void> importGeoTiff(PickedFile file) async {
    final info = GeoTiff.readInfo(file.bytes); // fail fast with a readable error
    final spec = OverlaySpec(
      id: _newId(),
      name: _stem(file.name),
      kind: OverlayKind.geotiff,
      colour: _nextColour(),
      detail: info.crs.name,
    );
    _put(OverlayItem(spec, progress: 0));
    await _render(spec, file.bytes);
  }

  /// Georeference next to [image]: a GDAL/QGIS `.aux.xml`, or a world file
  /// with its `.prj`. Null when there is none (the user then places it).
  static ImagePlacement? worldFileFor(PickedFile image) {
    final path = image.path;
    if (path == null) return null;
    final aux = File('$path.aux.xml');
    if (aux.existsSync() && aux.readAsStringSync().contains('<GeoTransform>')) {
      return WorldFilePlacement.fromAuxXml(aux.readAsStringSync());
    }
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    final base = path.substring(0, dot);
    for (final ext in ImageOverlay.worldFileExtensions(path.substring(dot))) {
      final wf = _sibling(base, ext);
      if (wf == null) continue;
      final prj = _sibling(base, '.prj');
      return WorldFilePlacement.parse(wf.readAsStringSync(), prj: prj?.readAsStringSync());
    }
    return null;
  }

  Future<void> importImage(PickedFile file, ImagePlacement placement) async {
    final id = _newId();
    final dir = _dir(id)..createSync(recursive: true);
    final stored = 'image${file.name.substring(file.name.lastIndexOf('.'))}';
    File('${dir.path}${Platform.pathSeparator}$stored').writeAsBytesSync(file.bytes);
    final spec = OverlaySpec(
      id: id,
      name: _stem(file.name),
      kind: OverlayKind.image,
      files: [stored],
      placement: placement,
      colour: _nextColour(),
      detail: switch (placement) {
        CornerPlacement() => 'Placed by four corners',
        CentrePlacement() => 'Placed by centre and size',
        WorldFilePlacement() => 'World file',
      },
    );
    _put(OverlayItem(spec, progress: 0));
    await _render(spec, file.bytes);
  }

  /// Imports vector files: GeoJSON (.geojson/.json), or Shapefiles — a .zip,
  /// or a .shp with its .dbf/.prj/.cpg either picked together or (desktop)
  /// found next to it.
  Future<void> importVector(List<PickedFile> files) async {
    final parts = <String, PickedFile>{};
    for (final f in files) {
      parts[f.name.toLowerCase()] = f;
      if (f.name.toLowerCase().endsWith('.shp') && f.path != null) {
        final base = f.path!.substring(0, f.path!.length - 4);
        for (final ext in ['.dbf', '.prj', '.cpg', '.shx']) {
          final s = _sibling(base, ext);
          final name = '${_stem(f.name)}$ext'.toLowerCase();
          if (s != null && !parts.containsKey(name)) {
            parts[name] = (name: name, path: s.path, bytes: s.readAsBytesSync());
          }
        }
      }
    }
    if (!parts.keys.any(_isVectorMain)) {
      throw const FormatException(
        'Pick a GeoJSON file (.geojson), a .shp file (with its .dbf and .prj) or a .zip containing them.',
      );
    }
    final id = _newId();
    final dir = _dir(id)..createSync(recursive: true);
    for (final p in parts.values) {
      File('${dir.path}${Platform.pathSeparator}${p.name.toLowerCase()}').writeAsBytesSync(p.bytes);
    }
    final first = parts.values.firstWhere((p) => _isVectorMain(p.name.toLowerCase()));
    final spec = OverlaySpec(
      id: id,
      name: _stem(first.name),
      kind: OverlayKind.vector,
      files: [for (final p in parts.values) p.name.toLowerCase()],
      colour: _nextColour(),
    );
    _put(OverlayItem(spec, progress: 0));
    await _loadVectors(spec);
  }

  Future<void> _loadVectors(OverlaySpec spec) async {
    final dir = _dir(spec.id);
    final files = <String, Uint8List>{};
    for (final f in spec.files) {
      final file = File('${dir.path}${Platform.pathSeparator}$f');
      if (file.existsSync()) files[f] = file.readAsBytesSync();
    }
    try {
      final layers = await Isolate.run(_vectorTask(files));
      final all = layers.map((l) => l.bounds).whereType<GeoBounds>();
      final bounds = all.isEmpty ? null : all.reduce((a, b) => a.union(b));
      final count = layers.fold<int>(0, (n, l) => n + l.features.length);
      final current = byId(spec.id);
      if (current == null) return;
      _put(
        current.copyWith(
          spec: current.spec.copyWith(bounds: bounds, detail: '$count features · ${layers.first.crsName}'),
          layers: layers,
          clearProgress: true,
        ),
      );
    } catch (e) {
      final current = byId(spec.id);
      if (current != null) _put(current.copyWith(clearProgress: true, error: _message(e)));
    }
  }

  /// Renders a raster overlay's pyramid on a background isolate.
  Future<void> _render(OverlaySpec spec, Uint8List bytes) async {
    final engine = await ref.read(tileEngineProvider.future);
    final job = RenderJob(engine.cachePath, spec.sourceId, spec.kind == OverlayKind.geotiff, bytes, spec.placement);
    try {
      final result = await runWithProgress(_renderTask(job), (p) {
        final i = byId(spec.id);
        if (i != null) state = [for (final x in state) x.spec.id == spec.id ? x.copyWith(progress: p) : x];
      });
      engine.service
        ..registerOverlay(spec.sourceId)
        ..cache.refreshSize();
      final current = byId(spec.id);
      if (current == null) {
        engine.service.cache.clear(source: spec.sourceId); // removed while rendering
        return;
      }
      final detail = '${spec.detail} · ${result.detail}';
      _put(
        current.copyWith(
          spec: current.spec.copyWith(bounds: result.bounds, detail: detail, maxZoom: result.maxZoom),
          clearProgress: true,
        ),
      );
    } catch (e) {
      final current = byId(spec.id);
      if (current != null) _put(current.copyWith(clearProgress: true, error: _message(e)));
    }
  }

  // ---- edits ----------------------------------------------------------------

  void setVisible(String id, bool v) => _edit(id, (s) => s.copyWith(visible: v));
  void setOpacity(String id, double v) => _edit(id, (s) => s.copyWith(opacity: v));

  void _edit(String id, OverlaySpec Function(OverlaySpec) f) {
    final i = byId(id);
    if (i != null) _put(i.copyWith(spec: f(i.spec)));
  }

  /// Moves the overlay at [from] so it ends up at index [to].
  void reorder(int from, int to) {
    final list = [...state];
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    state = list;
    _persist();
  }

  /// Re‑places an image overlay (corner handles, or edited numbers).
  Future<void> updatePlacement(String id, ImagePlacement placement) async {
    final item = byId(id);
    if (item == null || item.spec.kind != OverlayKind.image) return;
    final engine = await ref.read(tileEngineProvider.future);
    final old = item.spec.sourceId;
    final spec = item.spec.copyWith(
      revision: item.spec.revision + 1,
      placement: placement,
      detail: 'Placed by four corners',
    );
    _put(item.copyWith(spec: spec, progress: 0));
    final file = File('${_dir(id).path}${Platform.pathSeparator}${spec.files.first}');
    await _render(spec, file.readAsBytesSync());
    engine.service
      ..unregisterOverlay(old)
      ..cache.clear(source: old);
  }

  Future<void> remove(String id) async {
    final item = byId(id);
    if (item == null) return;
    state = state.where((i) => i.spec.id != id).toList();
    _persist();
    if (item.spec.isRaster) {
      final engine = await ref.read(tileEngineProvider.future);
      engine.service
        ..unregisterOverlay(item.spec.sourceId)
        ..cache.clear(source: item.spec.sourceId);
    }
    final dir = _dir(id);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  static File? _sibling(String base, String ext) {
    for (final e in {ext, ext.toUpperCase()}) {
      final f = File('$base$e');
      if (f.existsSync()) return f;
    }
    return null;
  }

  static String _stem(String name) {
    final slash = name.lastIndexOf(RegExp(r'[\\/]'));
    final n = name.substring(slash + 1);
    final dot = n.lastIndexOf('.');
    return dot > 0 ? n.substring(0, dot) : n;
  }

  static String _message(Object e) => switch (e) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final path) => '$message${path == null ? '' : ': $path'}',
    _ => e.toString(),
  };
}

final overlaysProvider = NotifierProvider<OverlaysController, List<OverlayItem>>(OverlaysController.new);

// ---- background work ----------------------------------------------------------
//
// Closures sent to another isolate carry their whole captured scope, so they
// are built here, at top level, from sendable data only — never inside the
// notifier, whose scope holds Riverpod state.

List<VectorLayer> Function() _vectorTask(Map<String, Uint8List> files) =>
    () => readVectorFiles(files);

RenderResult Function(void Function(double)) _renderTask(RenderJob job) =>
    (report) => renderRasterOverlay(job, report);

/// Inputs for [renderRasterOverlay].
final class RenderJob {
  const RenderJob(this.cachePath, this.sourceId, this.geotiff, this.bytes, this.placement);
  final String cachePath, sourceId;
  final bool geotiff;
  final Uint8List bytes;
  final ImagePlacement? placement;
}

typedef RenderResult = ({GeoBounds bounds, String detail, int maxZoom});

RenderResult renderRasterOverlay(RenderJob job, void Function(double) report) {
  final raster = job.geotiff
      ? GeoTiff.read(job.bytes)
      : ImageOverlay.place(ImageOverlay.decode(job.bytes), job.placement!);
  final cache = TileCache.open(job.cachePath);
  try {
    final n = renderOverlayToCache(raster, cache, job.sourceId, progress: (d, t) => report(t == 0 ? 1 : d / t));
    final res = raster.metresPerPixel;
    return (
      bounds: raster.bounds,
      detail: '${res < 1 ? res.toStringAsFixed(2) : res.toStringAsFixed(1)} m/px · $n tiles',
      maxZoom: raster.nativeZoom,
    );
  } finally {
    cache.close();
  }
}

/// A file that is a vector layer by itself (not a Shapefile sidecar).
bool _isVectorMain(String lowerName) =>
    lowerName.endsWith('.shp') ||
    lowerName.endsWith('.zip') ||
    lowerName.endsWith('.geojson') ||
    lowerName.endsWith('.json');

List<VectorLayer> readVectorFiles(Map<String, Uint8List> files) {
  final layers = <VectorLayer>[];
  for (final e in files.entries.where((e) => e.key.endsWith('.geojson') || e.key.endsWith('.json'))) {
    final dot = e.key.lastIndexOf('.');
    layers.add(GeoJson.read(name: e.key.substring(0, dot), bytes: e.value));
  }
  for (final e in files.entries.where((e) => e.key.endsWith('.zip'))) {
    layers.addAll(Shapefile.readZip(e.value));
  }
  for (final e in files.entries.where((e) => e.key.endsWith('.shp'))) {
    final base = e.key.substring(0, e.key.length - 4);
    String? text(String ext) => files['$base.$ext'] == null ? null : String.fromCharCodes(files['$base.$ext']!);
    layers.add(Shapefile.read(name: base, shp: e.value, dbf: files['$base.dbf'], prj: text('prj'), cpg: text('cpg')));
  }
  if (layers.isEmpty) throw const FormatException('No Shapefile or GeoJSON found.');
  return layers;
}

/// Runs [work] on a background isolate, forwarding its progress reports
/// (throttled to 1 % steps) to [onProgress] on this isolate.
Future<T> runWithProgress<T>(T Function(void Function(double) report) work, void Function(double) onProgress) async {
  final port = ReceivePort();
  final send = port.sendPort;
  final sub = port.listen((m) {
    if (m is double) onProgress(m);
  });
  try {
    return await Isolate.run(_reporting(work, send));
  } finally {
    await sub.cancel();
    port.close();
  }
}

T Function() _reporting<T>(T Function(void Function(double)) work, SendPort send) => () {
  var last = -1.0;
  return work((p) {
    if (p - last >= 0.01 || p >= 1) {
      last = p;
      send.send(p);
    }
  });
};
