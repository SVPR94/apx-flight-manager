// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../geo/china.dart';
import '../geo/geo_point.dart';
import '../geo/mercator.dart';
import '../raster/raster.dart';
import 'compose.dart';
import 'local_sources.dart';
import 'provider.dart';
import 'tile_cache.dart';

/// One tile answer.
final class TileResult {
  const TileResult(this.bytes, this.contentType, {this.stale = false, this.complete = true});
  final Uint8List bytes;
  final String contentType;

  /// False when a composed tile is missing source tiles that failed to load:
  /// it is shown but not cached, so it heals on the next request.
  final bool complete;

  /// Served from cache past its refresh age because the provider couldn't
  /// be reached (or offline mode is on).
  final bool stale;
}

/// Health of one provider as seen by the tile server, for the UI.
final class ProviderHealth {
  int ok = 0;
  int failed = 0;
  int cacheHits = 0;
  String? lastError;
  DateTime? lastErrorAt;

  /// The last request was refused for credentials (missing or bad key).
  bool keyProblem = false;
}

/// Progress of an offline area download.
final class DownloadProgress {
  const DownloadProgress(this.done, this.total, this.failed);
  final int done, total, failed;
}

/// Thrown when a download is not allowed or too large.
final class DownloadRefused implements Exception {
  const DownloadRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Resolves map tiles for every source: cache, online providers (with
/// reprojection for Chinese datums), local MBTiles/folders and rendered
/// overlays. Transport‑agnostic; [TileServer] puts HTTP in front of it.
final class TileService {
  TileService({
    required this.cache,
    http.Client? client,
    this.userAgent = 'APXFlightManager/0.1.0 (ground control station)',
    this.maxAge = const Duration(days: 30),
    this.perProviderConcurrency = 4,
    Future<Uint8List?> Function(ComposeJob job)? composer,
  }) : _client = client ?? http.Client(),
       _compose = composer ?? ((job) => Isolate.run(() => composeTile(job))) {
    setCustomSources(const []);
  }

  final TileCache cache;
  final String userAgent;
  final Duration maxAge;
  final int perProviderConcurrency;
  final http.Client _client;
  final Future<Uint8List?> Function(ComposeJob) _compose;

  /// API keys by [KeyService.id].
  final keys = <String, String>{};

  /// Serve only what is cached; never touch the network.
  bool offline = false;

  final _providers = <String, MapProvider>{};
  final _local = <String, LocalTileSource>{};
  final _overlays = <String>{};
  final _health = <String, ProviderHealth>{};
  final _inflight = <String, Future<TileResult?>>{};
  final _gates = <String, _Gate>{};
  final _sessions = <String, (String, DateTime)>{};

  Iterable<MapProvider> get providers => _providers.values;
  Iterable<LocalTileSource> get localSources => _local.values;
  MapProvider? provider(String id) => _providers[id];
  ProviderHealth health(String id) => _health.putIfAbsent(id, ProviderHealth.new);

  void setCustomSources(List<CustomSource> custom) {
    _providers
      ..clear()
      ..addEntries(MapProviders.builtIn.map((p) => MapEntry(p.id, p)))
      ..addEntries(custom.map((c) => MapEntry(c.id, c.toProvider())));
  }

  void addLocalSource(LocalTileSource s) {
    _local.remove(s.id)?.close();
    _local[s.id] = s;
  }

  void removeLocalSource(String id) => _local.remove(id)?.close();

  /// Overlay pyramids live in the cache under [sourceId]; tiles outside the
  /// overlay come back transparent rather than as errors.
  void registerOverlay(String sourceId) => _overlays.add(sourceId);
  void unregisterOverlay(String sourceId) => _overlays.remove(sourceId);

  /// Whether a key is needed and missing for [p].
  bool missingKey(MapProvider p) => p.key != null && (keys[p.key!.id]?.trim().isEmpty ?? true);

  Future<TileResult?> tile(String source, TileId t) {
    if (!t.isValid) return Future.value(null);
    if (_overlays.contains(source)) {
      final c = cache.get(source, t);
      return Future.value(c == null ? TileResult(transparentPng, 'image/png') : TileResult(c.bytes, c.contentType));
    }
    final local = _local[source];
    if (local != null) {
      final r = local.tile(t);
      return Future.value(r == null ? null : TileResult(r.$1, r.$2));
    }
    final p = _providers[source];
    if (p == null || t.z > p.maxZoom || t.z < p.minZoom) return Future.value(null);
    final k = '$source/$t';
    return _inflight[k] ??= _resolve(p, t).whenComplete(() {
      _inflight.remove(k);
    });
  }

  Future<TileResult?> _resolve(MapProvider p, TileId t, {bool pin = false}) async {
    final cached = cache.get(p.id, t);
    final fresh = cached != null && DateTime.now().difference(cached.fetched) < maxAge;
    if (cached != null && (fresh || offline)) {
      health(p.id).cacheHits++;
      if (pin) cache.put(p.id, t, cached.bytes, cached.contentType, pinned: true);
      return TileResult(cached.bytes, cached.contentType, stale: !fresh);
    }
    if (offline || missingKey(p)) {
      if (missingKey(p)) _fail(p.id, 'Needs a ${p.key!.name} key (Settings → Maps).', key: true);
      return cached == null ? null : TileResult(cached.bytes, cached.contentType, stale: true);
    }
    final fetched = p.passthrough ? await _fetchDirect(p, t) : await _fetchComposed(p, t);
    if (fetched != null) {
      if (fetched.complete) cache.put(p.id, t, fetched.bytes, fetched.contentType, pinned: pin);
      return fetched;
    }
    return cached == null ? null : TileResult(cached.bytes, cached.contentType, stale: true);
  }

  Future<TileResult?> _fetchDirect(MapProvider p, TileId t) async {
    final auth = await _auth(p);
    if (auth == null) return null;
    final r = (await _get(p, p.url(t.z, t.x, t.y, auth))).tile;
    return r == null ? null : TileResult(r.$1, r.$2);
  }

  /// Fetches and caches one provider‑grid source tile (layer 'base' or
  /// 'labels'); source tiles are cached on their own so neighbouring output
  /// tiles reuse them.
  Future<({Uint8List? bytes, bool failed})> _sourceTile(
    MapProvider p,
    String layer,
    int level,
    int col,
    int row,
    TileAuth auth,
  ) async {
    final y = p.grid == TileGrid.baidu ? -row - 1 : row;
    final key = '${p.id}@$layer';
    final id = TileId(level, col, y);
    final hit = cache.get(key, id);
    if (hit != null && DateTime.now().difference(hit.fetched) < maxAge) return (bytes: hit.bytes, failed: false);
    final url = (layer == 'labels' ? p.labels! : p.url)(level, col, y, auth);
    final r = await _get(p, url);
    if (r.tile == null) return (bytes: hit?.bytes, failed: r.failed);
    cache.put(key, id, r.tile!.$1, r.tile!.$2);
    return (bytes: r.tile!.$1, failed: false);
  }

  Future<TileResult?> _fetchComposed(MapProvider p, TileId t) async {
    final auth = await _auth(p);
    if (auth == null) return null;
    final warp = !(p.datum == MapDatum.wgs84 && p.grid == TileGrid.webMercator);
    final f = warp ? footprint(t, p.datum, p.grid, p.maxZoom) : SourceFootprint(t.z, t.x, t.y, 1, 1);
    if (f == null) return null;
    final cells = f.cells.toList();
    final base = await Future.wait([for (final (c, r) in cells) _sourceTile(p, 'base', f.level, c, r, auth)]);
    final labels = p.labels == null
        ? null
        : await Future.wait([for (final (c, r) in cells) _sourceTile(p, 'labels', f.level, c, r, auth)]);
    if (base.every((b) => b.bytes == null)) return null;
    final partial = base.any((b) => b.failed) || (labels?.any((b) => b.failed) ?? false);
    final bytes = await _compose(
      ComposeJob(
        z: t.z,
        x: t.x,
        y: t.y,
        datum: p.datum,
        grid: p.grid,
        footprint: f,
        base: [for (final b in base) b.bytes],
        labels: labels == null ? null : [for (final l in labels) l.bytes],
        jpeg: p.imagery,
        warp: warp,
      ),
    );
    if (bytes == null) return null;
    return TileResult(bytes, p.imagery ? 'image/jpeg' : 'image/png', complete: !partial);
  }

  Future<TileAuth?> _auth(MapProvider p) async {
    final key = p.key == null ? null : keys[p.key!.id]?.trim();
    final spec = p.googleSession;
    if (spec == null) return TileAuth(key: key);
    final s = _sessions[p.id];
    if (s != null && s.$2.isAfter(DateTime.now().add(const Duration(minutes: 5))))
      return TileAuth(key: key, session: s.$1);
    try {
      final r = await _client
          .post(
            Uri.parse('https://tile.googleapis.com/v1/createSession?key=$key'),
            headers: {'Content-Type': 'application/json', 'User-Agent': userAgent},
            body: jsonEncode(spec.body),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        final msg = _googleError(r.body) ?? 'HTTP ${r.statusCode}';
        _fail(p.id, 'Google rejected the session: $msg', key: r.statusCode == 400 || r.statusCode == 403);
        return null;
      }
      final j = jsonDecode(r.body) as Map<String, Object?>;
      final expiry = DateTime.fromMillisecondsSinceEpoch(int.parse(j['expiry'].toString()) * 1000);
      _sessions[p.id] = (j['session'] as String, expiry);
      return TileAuth(key: key, session: j['session'] as String);
    } catch (e) {
      _fail(p.id, 'Could not reach Google: $e');
      return null;
    }
  }

  static String? _googleError(String body) {
    try {
      return ((jsonDecode(body) as Map)['error'] as Map)['message'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// One upstream GET. `tile` is null both when the provider has no tile
  /// there (404, not a failure) and when the request failed (`failed`).
  Future<({(Uint8List, String)? tile, bool failed})> _get(MapProvider p, String url) async {
    final gate = _gates.putIfAbsent(p.id, () => _Gate(perProviderConcurrency));
    await gate.enter();
    try {
      final r = await _client
          .get(Uri.parse(url), headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 20));
      final type = r.headers['content-type'] ?? '';
      if (r.statusCode == 200 && type.startsWith('image/') && r.bodyBytes.isNotEmpty) {
        final h = health(p.id)
          ..ok += 1
          ..keyProblem = false;
        if (h.lastErrorAt != null && DateTime.now().difference(h.lastErrorAt!) > const Duration(seconds: 30)) {
          h.lastError = null;
        }
        return (tile: (r.bodyBytes, type.split(';').first), failed: false);
      }
      if (r.statusCode == 404 || r.statusCode == 204) return (tile: null, failed: false);
      final keyIssue = r.statusCode == 401 || r.statusCode == 403;
      if (keyIssue && p.googleSession != null) _sessions.remove(p.id);
      _fail(
        p.id,
        keyIssue
            ? 'HTTP ${r.statusCode}: the provider refused the key or this app.'
            : 'HTTP ${r.statusCode}${type.startsWith('image/') ? '' : ' ($type)'}',
        key: keyIssue,
      );
      return (tile: null, failed: true);
    } on TimeoutException {
      _fail(p.id, 'Timed out');
      return (tile: null, failed: true);
    } catch (e) {
      _fail(p.id, 'Network error: ${e.toString().split('\n').first}');
      return (tile: null, failed: true);
    } finally {
      gate.leave();
    }
  }

  void _fail(String id, String message, {bool key = false}) {
    health(id)
      ..failed += 1
      ..lastError = message
      ..lastErrorAt = DateTime.now()
      ..keyProblem = key;
  }

  /// Tile budget for one offline download.
  static const maxDownloadTiles = 150000;

  /// Downloads [bounds] from zoom [minZoom] to [maxZoom] into the cache,
  /// pinned so browsing never evicts it. Refused for providers whose terms
  /// forbid bulk download (OpenStreetMap, Google, …).
  Future<DownloadProgress> download(
    String providerId,
    GeoBounds bounds,
    int minZoom,
    int maxZoom, {
    void Function(DownloadProgress)? onProgress,
    bool Function()? cancelled,
  }) async {
    final p = _providers[providerId];
    if (p == null) throw DownloadRefused('Unknown map $providerId');
    if (!p.allowsBulkDownload && !p.custom) {
      throw DownloadRefused(
        '${p.name} does not allow downloading areas for offline use. Its tiles are still cached as you browse.',
      );
    }
    if (offline) throw const DownloadRefused('Turn off offline mode to download.');
    final hi = maxZoom.clamp(minZoom, p.maxZoom);
    final total = WebMercator.countTiles(bounds, minZoom, hi);
    if (total > maxDownloadTiles) {
      throw DownloadRefused(
        'That is $total tiles; the limit is $maxDownloadTiles. Choose a smaller area or lower zoom.',
      );
    }
    var done = 0, failed = 0;
    final queue = [for (var z = minZoom; z <= hi; z++) ...WebMercator.tilesCovering(bounds, z)];
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length && !(cancelled?.call() ?? false)) {
        final t = queue[next++];
        final r = await _resolve(p, t, pin: true);
        if (r == null || !r.complete) failed++;
        done++;
        onProgress?.call(DownloadProgress(done, total, failed));
      }
    }

    await Future.wait([for (var i = 0; i < perProviderConcurrency; i++) worker()]);
    return DownloadProgress(done, total, failed);
  }

  void close() {
    for (final s in _local.values) {
      s.close();
    }
    _client.close();
  }
}

/// A 256×256 fully transparent PNG.
final Uint8List transparentPng = encodeTile(RgbaRaster(tileSize, tileSize));

final class _Gate {
  _Gate(this._free);
  int _free;
  final _waiting = <Completer<void>>[];

  Future<void> enter() {
    if (_free > 0) {
      _free--;
      return Future.value();
    }
    final c = Completer<void>();
    _waiting.add(c);
    return c.future;
  }

  void leave() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _free++;
    }
  }
}
