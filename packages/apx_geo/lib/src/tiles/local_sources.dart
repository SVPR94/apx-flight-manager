// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../geo/geo_point.dart';
import '../geo/mercator.dart';

/// A base map read from local files instead of a server.
abstract class LocalTileSource {
  String get id;
  String get name;
  String get attribution;
  int get minZoom;
  int get maxZoom;
  GeoBounds? get bounds;

  /// Tile bytes and content type, or null if the source has no such tile.
  (Uint8List, String)? tile(TileId t);

  void close() {}

  Map<String, Object?> toJson();

  static LocalTileSource fromJson(Map<String, Object?> j) => switch (j['kind']) {
    'mbtiles' => MbTilesSource.open(j['id'] as String, j['path'] as String),
    'folder' => FolderSource(j['id'] as String, j['path'] as String, name: j['name'] as String?, tms: j['tms'] == true),
    _ => throw FormatException('Unknown local source ${j['kind']}'),
  };
}

String _sniff(Uint8List b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
  if (b.length > 2 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'image/webp';
  return 'application/octet-stream';
}

/// An MBTiles 1.x file (raster tiles; rows stored TMS, y up).
final class MbTilesSource extends LocalTileSource {
  MbTilesSource._(this.id, this.path, this._db) {
    final meta = {
      for (final r in _db.select('SELECT name, value FROM metadata')) r['name'] as String: r['value'] as String? ?? '',
    };
    final format = meta['format'] ?? 'png';
    if (format == 'pbf') {
      _db.close();
      throw const FormatException('This MBTiles file holds vector tiles (pbf); only raster MBTiles are supported.');
    }
    name = meta['name']?.isNotEmpty == true ? meta['name']! : File(path).uri.pathSegments.last;
    attribution = meta['attribution'] ?? '';
    final zr = _db.select('SELECT MIN(zoom_level) AS lo, MAX(zoom_level) AS hi FROM tiles').first;
    minZoom = int.tryParse(meta['minzoom'] ?? '') ?? (zr['lo'] as int? ?? 0);
    maxZoom = int.tryParse(meta['maxzoom'] ?? '') ?? (zr['hi'] as int? ?? 19);
    final b = (meta['bounds'] ?? '').split(',').map((s) => double.tryParse(s.trim())).toList();
    bounds = b.length == 4 && b.every((v) => v != null) ? GeoBounds(b[1]!, b[0]!, b[3]!, b[2]!) : null;
    _get = _db.prepare('SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?');
  }

  factory MbTilesSource.open(String id, String path) {
    if (!File(path).existsSync()) throw FileSystemException('MBTiles file not found', path);
    return MbTilesSource._(id, path, sqlite3.open(path, mode: OpenMode.readOnly));
  }

  @override
  final String id;
  final String path;
  final Database _db;
  late final PreparedStatement _get;
  @override
  late final String name, attribution;
  @override
  late final int minZoom, maxZoom;
  @override
  late final GeoBounds? bounds;

  @override
  (Uint8List, String)? tile(TileId t) {
    final rows = _get.select([t.z, t.x, (1 << t.z) - 1 - t.y]);
    if (rows.isEmpty) return null;
    final data = rows.first['tile_data'] as Uint8List;
    return (data, _sniff(data));
  }

  @override
  void close() {
    _get.close();
    _db.close();
  }

  @override
  Map<String, Object?> toJson() => {'kind': 'mbtiles', 'id': id, 'path': path};
}

/// A folder of tiles laid out z/x/y.png (or .jpg/.jpeg/.webp), as written by
/// most tile downloaders. [tms] flips y for folders written TMS‑style.
final class FolderSource extends LocalTileSource {
  FolderSource(this.id, this.path, {String? name, this.tms = false})
    : name = name ?? Directory(path).uri.pathSegments.where((s) => s.isNotEmpty).last {
    if (!Directory(path).existsSync()) throw FileSystemException('Tile folder not found', path);
    final zooms =
        Directory(path)
            .listSync()
            .map((e) => int.tryParse(e.uri.pathSegments.where((s) => s.isNotEmpty).last))
            .whereType<int>()
            .toList()
          ..sort();
    if (zooms.isEmpty) throw const FormatException('The folder has no zoom‑level sub‑folders (expected z/x/y.png).');
    minZoom = zooms.first;
    maxZoom = zooms.last;
  }

  @override
  final String id, name;
  final String path;
  final bool tms;
  @override
  late final int minZoom, maxZoom;
  @override
  String get attribution => '';
  @override
  GeoBounds? get bounds => null;

  static const _exts = ['png', 'jpg', 'jpeg', 'webp'];

  @override
  (Uint8List, String)? tile(TileId t) {
    final y = tms ? (1 << t.z) - 1 - t.y : t.y;
    for (final e in _exts) {
      final f = File(
        '$path${Platform.pathSeparator}${t.z}${Platform.pathSeparator}${t.x}${Platform.pathSeparator}$y.$e',
      );
      if (f.existsSync()) {
        final b = f.readAsBytesSync();
        return (b, _sniff(b));
      }
    }
    return null;
  }

  @override
  Map<String, Object?> toJson() => {'kind': 'folder', 'id': id, 'path': path, 'name': name, 'tms': tms};
}
