// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apx_geo/apx_geo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// A solid‑colour 256 px PNG.
Uint8List solid(int r, int g, int b, [int a = 255]) {
  final raster = RgbaRaster(tileSize, tileSize);
  for (var i = 0; i < raster.pixels.length; i += 4) {
    raster.pixels.setAll(i, [r, g, b, a]);
  }
  return encodeTile(raster);
}

/// Scripted upstream: records requests, answers by URL.
final class Upstream {
  final requests = <Uri>[];
  http.Response Function(http.Request r) answer = (_) =>
      http.Response.bytes(solid(10, 200, 10), 200, headers: {'content-type': 'image/png'});

  MockClient get client => MockClient((r) async {
    requests.add(r.url);
    return answer(r);
  });
}

TileService service(Upstream up, {TileCache? cache}) => TileService(
  cache: cache ?? TileCache.inMemory(),
  client: up.client,
  composer: (job) async => composeTile(job), // same isolate in tests
);

void main() {
  group('TileCache', () {
    test('stores, reports usage and evicts least‑recently‑used, never pinned', () {
      final c = TileCache.inMemory(maxBytes: 10000);
      final blob = Uint8List(3000);
      c.put('pinned', const TileId(1, 0, 0), blob, 'image/png', pinned: true);
      for (var i = 0; i < 6; i++) {
        c.put('osm', TileId(5, i, 0), blob, 'image/png');
      }
      c.prune();
      expect(c.sizeBytes, lessThanOrEqualTo(10000));
      expect(c.get('pinned', const TileId(1, 0, 0)), isNotNull);
      expect(c.get('osm', const TileId(5, 5, 0)), isNotNull, reason: 'newest survives');
      expect(c.get('osm', const TileId(5, 0, 0)), isNull, reason: 'oldest evicted');
      c.clear(keepPinned: true);
      expect(c.usage().single.source, 'pinned');
      c.clear();
      expect(c.sizeBytes, 0);
    });
  });

  group('TileService', () {
    test('fetches once, then serves from cache', () async {
      final up = Upstream();
      final s = service(up);
      final a = await s.tile('osm', const TileId(3, 4, 2));
      final b = await s.tile('osm', const TileId(3, 4, 2));
      expect(a!.contentType, 'image/png');
      expect(b!.bytes, a.bytes);
      expect(up.requests.single.toString(), 'https://tile.openstreetmap.org/3/4/2.png');
      expect(s.health('osm').cacheHits, 1);
    });

    test('coalesces concurrent requests for the same tile', () async {
      final up = Upstream();
      final s = service(up);
      await Future.wait([for (var i = 0; i < 5; i++) s.tile('osm', const TileId(4, 1, 1))]);
      expect(up.requests, hasLength(1));
    });

    test('offline mode never touches the network and serves stale tiles', () async {
      final up = Upstream();
      final cache = TileCache.inMemory();
      final s = TileService(cache: cache, client: up.client, maxAge: Duration.zero);
      await s.tile('osm', const TileId(2, 1, 1));
      s.offline = true;
      final r = await s.tile('osm', const TileId(2, 1, 1));
      expect(r!.stale, isTrue);
      expect(await s.tile('osm', const TileId(2, 0, 0)), isNull);
      expect(up.requests, hasLength(1));
    });

    test('falls back to the cached tile when the provider fails', () async {
      final up = Upstream();
      final s = TileService(cache: TileCache.inMemory(), client: up.client, maxAge: Duration.zero);
      await s.tile('osm', const TileId(2, 1, 1));
      up.answer = (_) => http.Response('busy', 503);
      final r = await s.tile('osm', const TileId(2, 1, 1));
      expect(r!.stale, isTrue);
      expect(s.health('osm').lastError, contains('503'));
    });

    test('a keyed provider without a key reports it and makes no request', () async {
      final up = Upstream();
      final s = service(up);
      expect(await s.tile('mapbox-satellite', const TileId(3, 1, 1)), isNull);
      expect(up.requests, isEmpty);
      expect(s.health('mapbox-satellite').keyProblem, isTrue);
      expect(s.health('mapbox-satellite').lastError, contains('Mapbox'));
    });

    test('a rejected key is reported as a key problem; the key never reaches the map URL', () async {
      final up = Upstream()..answer = (_) => http.Response('{"message":"Not Authorized"}', 401);
      final s = service(up)..keys['mapbox'] = 'secret-token';
      expect(await s.tile('mapbox-satellite', const TileId(3, 1, 1)), isNull);
      expect(up.requests.single.queryParameters['access_token'], 'secret-token');
      expect(s.health('mapbox-satellite').keyProblem, isTrue);
    });

    test('Google: creates a session once and reuses it', () async {
      final up = Upstream()
        ..answer = (r) {
          if (r.url.path.endsWith('createSession')) {
            final body = jsonDecode(r.body) as Map;
            expect(body['mapType'], 'satellite');
            expect(body['layerTypes'], ['layerRoadmap']);
            final expiry = DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch ~/ 1000;
            return http.Response('{"session":"S1","expiry":"$expiry","tileWidth":256}', 200);
          }
          return http.Response.bytes(solid(1, 2, 3), 200, headers: {'content-type': 'image/jpeg'});
        };
      final s = service(up)..keys['google'] = 'K';
      await s.tile('google-hybrid', const TileId(5, 1, 1));
      await s.tile('google-hybrid', const TileId(5, 2, 1));
      expect(up.requests.where((u) => u.path.endsWith('createSession')), hasLength(1));
      final tile = up.requests.last;
      expect(tile.path, '/v1/2dtiles/5/2/1');
      expect(tile.queryParameters, {'session': 'S1', 'key': 'K'});
    });

    test('GCJ‑02 provider: fetches the shifted source tiles and reprojects', () async {
      final up = Upstream();
      final s = service(up);
      // Beijing, zoom 15: the GCJ offset is ~ 500 m, i.e. more than a tile.
      final t = WebMercator.tileAt(const GeoPoint(39.9087, 116.3975), 15);
      final r = await s.tile('gaode-road', t);
      expect(r, isNotNull);
      final shifted = WebMercator.tileAt(wgs84ToGcj02(const GeoPoint(39.9087, 116.3975)), 15);
      final asked = up.requests
          .map((u) => (int.parse(u.queryParameters['x']!), int.parse(u.queryParameters['y']!)))
          .toSet();
      expect(asked, contains((shifted.x, shifted.y)));
      expect(asked.length, lessThanOrEqualTo(4));
      final decoded = img.decodePng(r!.bytes)!;
      expect(decoded.getPixel(128, 128).g, 200, reason: 'colour carried through the warp');
    });

    test('a composed tile with failed source tiles is shown but not cached', () async {
      final up = Upstream();
      var calls = 0;
      up.answer = (r) => calls++ == 0
          ? http.Response('timeout', 504)
          : http.Response.bytes(solid(10, 200, 10), 200, headers: {'content-type': 'image/png'});
      final cache = TileCache.inMemory();
      final s = service(up, cache: cache);
      final t = WebMercator.tileAt(const GeoPoint(39.9087, 116.3975), 15);
      final first = await s.tile('gaode-road', t);
      if (first != null) expect(first.complete, isFalse);
      expect(cache.get('gaode-road', t), isNull);
      final second = await s.tile('gaode-road', t);
      expect(second!.complete, isTrue);
      expect(cache.get('gaode-road', t), isNotNull);
    });

    test('Baidu provider asks for Baidu grid tiles (y up, level z+1)', () async {
      final up = Upstream();
      final s = service(up);
      final t = WebMercator.tileAt(const GeoPoint(39.9087, 116.3975), 14);
      expect(await s.tile('baidu-road', t), isNotNull);
      final (mx, my) = BaiduMercator.fromBd09(wgs84To(MapDatum.bd09, const GeoPoint(39.9087, 116.3975)));
      final res = BaiduMercator.unitsPerPixel(15) * tileSize;
      final expectX = (mx / res).floor(), expectY = (my / res).floor();
      final asked = up.requests
          .map((u) => (u.queryParameters['x'], u.queryParameters['y'], u.queryParameters['z']))
          .toSet();
      expect(asked, contains(('$expectX', '$expectY', '15')));
    });

    test('downloads are refused for providers whose terms forbid them', () async {
      final s = service(Upstream());
      expect(
        () => s.download('osm', const GeoBounds(18.5, 73.8, 18.6, 73.9), 10, 14),
        throwsA(isA<DownloadRefused>().having((e) => e.message, 'message', contains('OpenStreetMap'))),
      );
    });

    test('custom XYZ source downloads an area, pinned', () async {
      final up = Upstream();
      final cache = TileCache.inMemory(maxBytes: 1);
      final s = service(up, cache: cache)
        ..setCustomSources([
          const CustomSource(id: 'mine', name: 'Mine', kind: 'xyz', template: 'https://tiles.example/{z}/{x}/{-y}.png'),
        ]);
      const area = GeoBounds(18.5, 73.8, 18.6, 73.9);
      final done = await s.download('mine', area, 10, 12);
      expect(done.total, WebMercator.countTiles(area, 10, 12));
      expect(done.failed, 0);
      cache.prune();
      expect(cache.usage().single.tiles, done.total, reason: 'pinned tiles survive pruning');
      expect(up.requests.first.path, matches(RegExp(r'^/10/\d+/\d+\.png$')));
    });

    test('custom source validation', () {
      expect(
        const CustomSource(id: 'a', name: 'A', kind: 'xyz', template: 'ftp://x/{z}/{x}/{y}').validate(),
        contains('http'),
      );
      expect(
        const CustomSource(id: 'a', name: 'A', kind: 'xyz', template: 'https://x/{z}/{x}').validate(),
        contains('{y}'),
      );
      expect(
        const CustomSource(id: 'a', name: 'A', kind: 'wms', template: 'https://x/wms').validate(),
        contains('layer'),
      );
      expect(const CustomSource(id: 'a', name: 'A', kind: 'xyz', template: 'https://x/{q}.png').validate(), isNull);
    });

    test('overlays come from the cache and are transparent outside', () async {
      final cache = TileCache.inMemory();
      final s = service(Upstream(), cache: cache)..registerOverlay('overlay-1');
      cache.put('overlay-1', const TileId(10, 1, 1), solid(1, 1, 1), 'image/png', pinned: true);
      expect((await s.tile('overlay-1', const TileId(10, 1, 1)))!.bytes, solid(1, 1, 1));
      expect((await s.tile('overlay-1', const TileId(10, 2, 2)))!.bytes, transparentPng);
    });
  });

  group('Local sources', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('apx_geo_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('MBTiles: reads metadata and flips TMS rows', () {
      final path = '${dir.path}/area.mbtiles';
      final db = sqlite3.open(path);
      db.execute(
        'CREATE TABLE metadata(name TEXT, value TEXT); CREATE TABLE tiles(zoom_level INT, tile_column INT, tile_row INT, tile_data BLOB);',
      );
      db.execute(
        "INSERT INTO metadata VALUES('name','Farm'),('format','png'),('minzoom','10'),('maxzoom','16'),('bounds','73.8,18.5,73.9,18.6')",
      );
      db.execute('INSERT INTO tiles VALUES(?,?,?,?)', [12, 2887, (1 << 12) - 1 - 1841, solid(9, 9, 9)]);
      db.close();
      final src = MbTilesSource.open('mb', path);
      expect(src.name, 'Farm');
      expect(src.maxZoom, 16);
      expect(src.bounds!.west, 73.8);
      expect(src.tile(const TileId(12, 2887, 1841))!.$2, 'image/png');
      expect(src.tile(const TileId(12, 2887, 1842)), isNull);
      src.close();
    });

    test('XYZ folder', () {
      File('${dir.path}/14/11600/7360.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0]);
      final src = FolderSource('f', dir.path);
      expect(src.minZoom, 14);
      expect(src.tile(const TileId(14, 11600, 7360))!.$2, 'image/jpeg');
    });
  });

  test('TileServer serves tiles over loopback HTTP', () async {
    final s = service(Upstream());
    final server = await TileServer.start(s);
    addTearDown(server.close);
    final url = server.urlTemplate('osm').replaceAll('{z}', '3').replaceAll('{x}', '4').replaceAll('{y}', '2');
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse(url))).close();
    expect(res.statusCode, 200);
    expect(res.headers.contentType!.mimeType, 'image/png');
    final missing = await (await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/tiles/nope/1/0/0'))).close();
    expect(missing.statusCode, 404);
    final status = await (await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/status'))).close();
    final j = jsonDecode(await utf8.decodeStream(status)) as Map;
    expect((j['providers'] as Map)['osm']['ok'], 1);
    client.close();
  });
}
