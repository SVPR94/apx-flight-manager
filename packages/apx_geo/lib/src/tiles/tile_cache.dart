// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../geo/mercator.dart';

/// A cached tile.
final class CachedTile {
  const CachedTile(this.bytes, this.contentType, this.fetched);
  final Uint8List bytes;
  final String contentType;
  final DateTime fetched;
}

/// Space used by one source.
final class CacheUsage {
  const CacheUsage(this.source, this.tiles, this.bytes, {required this.pinned});
  final String source;
  final int tiles, bytes;
  final bool pinned;
}

/// Tile store on SQLite (one file, safe to copy between machines).
///
/// Tiles fetched while browsing are evicted least‑recently‑used once the
/// cache passes [maxBytes]. Pinned tiles (downloaded areas, rendered
/// overlays) are never evicted; they go only when their source is cleared.
final class TileCache {
  TileCache._(this._db, this.maxBytes) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS tiles(
        source TEXT NOT NULL, z INTEGER NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL,
        data BLOB NOT NULL, type TEXT NOT NULL, fetched INTEGER NOT NULL, used INTEGER NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(source, z, x, y)) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS tiles_lru ON tiles(pinned, used);
    ''');
    _get = _db.prepare('SELECT data, type, fetched, used FROM tiles WHERE source=? AND z=? AND x=? AND y=?');
    _touch = _db.prepare('UPDATE tiles SET used=? WHERE source=? AND z=? AND x=? AND y=?');
    _put = _db.prepare('''
      INSERT INTO tiles(source, z, x, y, data, type, fetched, used, pinned) VALUES(?,?,?,?,?,?,?,?,?)
      ON CONFLICT(source, z, x, y) DO UPDATE SET data=excluded.data, type=excluded.type, fetched=excluded.fetched,
        used=excluded.used, pinned=max(pinned, excluded.pinned)''');
    _bytes = _db.select('SELECT COALESCE(SUM(LENGTH(data)), 0) FROM tiles').first.columnAt(0) as int;
  }

  /// Opens (creating if needed) the cache at [path].
  factory TileCache.open(String path, {int maxBytes = 1 << 30}) {
    File(path).parent.createSync(recursive: true);
    final db = sqlite3.open(path);
    // WAL + a busy timeout let an overlay import write from another isolate
    // while the tile server reads.
    db.execute('PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=10000;');
    return TileCache._(db, maxBytes);
  }

  factory TileCache.inMemory({int maxBytes = 1 << 30}) => TileCache._(sqlite3.openInMemory(), maxBytes);

  final Database _db;
  int maxBytes;
  late final PreparedStatement _get, _touch, _put;
  int _bytes = 0;
  int _sincePrune = 0;

  int get sizeBytes => _bytes;

  /// Re‑reads the total size (after another connection wrote to the file).
  void refreshSize() =>
      _bytes = _db.select('SELECT COALESCE(SUM(LENGTH(data)), 0) FROM tiles').first.columnAt(0) as int;

  CachedTile? get(String source, TileId t) {
    final rows = _get.select([source, t.z, t.x, t.y]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final now = _nowSec();
    // Record use at most hourly: LRU needs no finer grain, and it saves a write per hit.
    if (now - (r['used'] as int) > 3600) _touch.execute([now, source, t.z, t.x, t.y]);
    return CachedTile(
      r['data'] as Uint8List,
      r['type'] as String,
      DateTime.fromMillisecondsSinceEpoch((r['fetched'] as int) * 1000),
    );
  }

  bool contains(String source, TileId t) =>
      _db.select('SELECT 1 FROM tiles WHERE source=? AND z=? AND x=? AND y=?', [source, t.z, t.x, t.y]).isNotEmpty;

  void put(String source, TileId t, Uint8List bytes, String contentType, {bool pinned = false}) {
    final old = _db.select('SELECT LENGTH(data) FROM tiles WHERE source=? AND z=? AND x=? AND y=?', [
      source,
      t.z,
      t.x,
      t.y,
    ]);
    final now = _nowSec();
    _put.execute([source, t.z, t.x, t.y, bytes, contentType, now, now, pinned ? 1 : 0]);
    _bytes += bytes.length - (old.isEmpty ? 0 : old.first.columnAt(0) as int);
    if (++_sincePrune >= 200 || _bytes > maxBytes * 1.1) {
      _sincePrune = 0;
      prune();
    }
  }

  /// Writes many tiles in one transaction (overlay pyramids, area downloads).
  void putAll(String source, Iterable<(TileId, Uint8List, String)> tiles, {bool pinned = true}) {
    _db.execute('BEGIN');
    try {
      for (final (t, b, type) in tiles) {
        put(source, t, b, type, pinned: pinned);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Drops least‑recently‑used unpinned tiles until under [maxBytes].
  void prune() {
    if (_bytes <= maxBytes) return;
    final excess = _bytes - (maxBytes * 0.9).round();
    final victims = _db.select('''
      SELECT source, z, x, y, LENGTH(data) AS n FROM tiles WHERE pinned=0 ORDER BY used LIMIT 5000''');
    var freed = 0;
    _db.execute('BEGIN');
    for (final v in victims) {
      if (freed >= excess) break;
      _db.execute('DELETE FROM tiles WHERE source=? AND z=? AND x=? AND y=?', [v['source'], v['z'], v['x'], v['y']]);
      freed += v['n'] as int;
    }
    _db.execute('COMMIT');
    _bytes -= freed;
  }

  List<CacheUsage> usage() => [
    for (final r in _db.select(
      'SELECT source, COUNT(*) AS n, SUM(LENGTH(data)) AS b, MAX(pinned) AS p FROM tiles GROUP BY source ORDER BY b DESC',
    ))
      CacheUsage(r['source'] as String, r['n'] as int, r['b'] as int, pinned: (r['p'] as int) == 1),
  ];

  /// Removes one source's tiles, or everything when [source] is null.
  /// [keepPinned] leaves downloaded areas and overlays in place.
  void clear({String? source, bool keepPinned = false}) {
    final where = [if (source != null) 'source=?', if (keepPinned) 'pinned=0'];
    _db.execute('DELETE FROM tiles${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}', [?source]);
    _bytes = _db.select('SELECT COALESCE(SUM(LENGTH(data)), 0) FROM tiles').first.columnAt(0) as int;
  }

  void close() {
    _get.close();
    _touch.close();
    _put.close();
    _db.close();
  }

  static int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
