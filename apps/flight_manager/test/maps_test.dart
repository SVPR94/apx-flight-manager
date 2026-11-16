// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apx_flight_manager/main.dart';
import 'package:apx_flight_manager/map/layers_panel.dart';
import 'package:apx_flight_manager/state/fence.dart';
import 'package:apx_flight_manager/state/map_tiles.dart';
import 'package:apx_flight_manager/state/overlays.dart';
import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_geo/apx_geo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support.dart';

const fixtures = '../../packages/apx_geo/test/fixtures';

PickedFile picked(String name) {
  final f = File('$fixtures/$name');
  return (name: name, path: f.absolute.path, bytes: f.readAsBytesSync());
}

ProviderContainer containerFor(Directory dir) {
  final c = ProviderContainer(overrides: testOverrides(dir, engine: true));
  addTearDown(c.dispose);
  return c;
}

/// flutter_test fakes all HTTP (every request gets 400); these tests talk to
/// the real loopback tile server.
final class _RealHttp extends HttpOverrides {}

/// GETs one tile from the running tile server.
Future<(int, List<int>)> fetch(TileEngine e, String source, TileId t) =>
    HttpOverrides.runWithHttpOverrides(() => _fetch(e, source, t), _RealHttp());

Future<(int, List<int>)> _fetch(TileEngine e, String source, TileId t) async {
  final client = HttpClient();
  try {
    final url = e
        .urlTemplate(source)
        .replaceAll('{z}', '${t.z}')
        .replaceAll('{x}', '${t.x}')
        .replaceAll('{y}', '${t.y}');
    final res = await (await client.getUrl(Uri.parse(url))).close();
    return (res.statusCode, await res.fold<List<int>>([], (a, b) => a..addAll(b)));
  } finally {
    client.close();
  }
}

void main() {
  group('Map settings and tile engine', () {
    test('settings apply to the running service live and persist', () async {
      final dir = tempDataDir();
      final c = containerFor(dir);
      final engine = await c.read(tileEngineProvider.future);
      final ctl = c.read(mapSettingsProvider.notifier);

      ctl.setOffline(true);
      ctl.setKey('mapbox', '  pk.test  ');
      ctl.setBaseMap('esri-imagery');
      ctl.addCustom(
        const CustomSource(id: 'c1', name: 'Farm WMS', kind: 'wms', template: 'https://x/wms', layers: 'ortho'),
      );
      expect(engine.service.offline, isTrue);
      expect(engine.service.keys['mapbox'], 'pk.test');
      expect(engine.service.provider('c1')!.name, 'Farm WMS');
      expect(c.read(currentBaseMapProvider).name, 'Esri World Imagery');

      c.read(settingsStoreProvider).flush();
      final saved = jsonDecode(File('${dir.path}/settings.json').readAsStringSync()) as Map;
      expect(saved['maps']['baseMap'], 'esri-imagery');
      expect(saved['maps']['keys'], {'mapbox': 'pk.test'});

      // A fresh start reads the same settings back.
      final again = containerFor(dir);
      expect(again.read(mapSettingsProvider).offline, isTrue);
      expect(again.read(currentBaseMapProvider).id, 'esri-imagery');
      ctl.removeCustom('c1');
      expect(c.read(baseMapChoicesProvider).any((b) => b.id == 'c1'), isFalse);
    });

    test('keyed providers are flagged until a key is saved', () {
      final c = containerFor(tempDataDir());
      BaseMapChoice google() => c.read(baseMapChoicesProvider).firstWhere((b) => b.id == 'google-satellite');
      expect(google().needsKey, KeyService.google);
      c.read(mapSettingsProvider.notifier).setKey('google', 'AIza-test');
      expect(google().needsKey, isNull);
    });

    test('an MBTiles file becomes a base map served by the tile server', () async {
      final dir = tempDataDir();
      final c = containerFor(dir);
      final engine = await c.read(tileEngineProvider.future);
      final mb = '${dir.path}/area.mbtiles';
      final png = encodeTile(
        RgbaRaster(tileSize, tileSize, Uint8List(tileSize * tileSize * 4)..fillRange(0, tileSize * tileSize * 4, 200)),
      );
      final db = sqlite3.open(mb);
      db.execute(
        'CREATE TABLE metadata(name TEXT, value TEXT); CREATE TABLE tiles(zoom_level INT, tile_column INT, tile_row INT, tile_data BLOB);',
      );
      db.execute("INSERT INTO metadata VALUES('name','Field block'),('format','png')");
      db.execute('INSERT INTO tiles VALUES(?,?,?,?)', [3, 5, 4, png]);
      db.close();
      c.read(mapSettingsProvider.notifier).addLocal(MbTilesSource.open('local-1', mb));
      expect(c.read(baseMapChoicesProvider).firstWhere((b) => b.id == 'local-1').name, 'Field block');
      final (status, body) = await fetch(engine, 'local-1', const TileId(3, 5, 3));
      expect(status, 200);
      expect(body.length, png.length);
    });
  });

  group('Overlays', () {
    test('GeoTIFF import renders a pyramid in the background and the server serves it', () async {
      final c = containerFor(tempDataDir());
      final engine = await c.read(tileEngineProvider.future);
      await c.read(overlaysProvider.notifier).importGeoTiff(picked('utm43n.tif'));
      final o = c.read(overlaysProvider).single;
      expect(o.error, isNull);
      expect(o.busy, isFalse);
      expect(o.spec.maxZoom, 20);
      expect(o.spec.detail, contains('UTM zone 43N'));
      expect(o.spec.bounds!.contains(const GeoPoint(18.5195, 73.8505)), isTrue);

      final t = WebMercator.tileAt(o.spec.bounds!.center, 20);
      final (status, body) = await fetch(engine, o.spec.sourceId, t);
      expect(status, 200);
      final tile = img.decodePng(Uint8List.fromList(body))!;
      expect(tile.getPixel(128, 128).a, 255, reason: 'centre of the image is drawn');
      // Outside the overlay: transparent, not an error.
      final (s2, b2) = await fetch(engine, o.spec.sourceId, const TileId(20, 0, 0));
      expect(s2, 200);
      expect(img.decodePng(Uint8List.fromList(b2))!.getPixel(5, 5).a, 0);
    });

    test('image re‑placement renders a new revision and drops the old tiles', () async {
      final c = containerFor(tempDataDir());
      final engine = await c.read(tileEngineProvider.future);
      final ctl = c.read(overlaysProvider.notifier);
      final e = jsonDecode(File('$fixtures/expected.json').readAsStringSync())['photo.png'];
      final corners = [for (final p in e['corners'] as List) GeoPoint(p[0], p[1])];
      await ctl.importImage(picked('photo.png'), CornerPlacement(corners));
      final first = c.read(overlaysProvider).single.spec;
      expect(engine.service.cache.usage().map((u) => u.source), contains(first.sourceId));

      final moved = [for (final p in corners) GeoPoint(p.lat + 0.001, p.lon)];
      await ctl.updatePlacement(first.id, CornerPlacement(moved));
      final second = c.read(overlaysProvider).single.spec;
      expect(second.revision, first.revision + 1);
      final sources = engine.service.cache.usage().map((u) => u.source);
      expect(sources, contains(second.sourceId));
      expect(sources, isNot(contains(first.sourceId)));
      expect(second.bounds!.south, greaterThan(first.bounds!.south));
    });

    test('a world file next to an image is found and used', () {
      final p = OverlaysController.worldFileFor(picked('ortho.png'));
      expect(p, isA<WorldFilePlacement>());
      expect((p as WorldFilePlacement).crs.name, contains('UTM zone 43N'));
      expect(OverlaysController.worldFileFor(picked('photo.png')), isNull);
      // GDAL/QGIS exports carry an .aux.xml instead.
      final aux = OverlaysController.worldFileFor(picked('export.png'));
      expect((aux as WorldFilePlacement).crs.epsg, 32643);
    });

    test('a Shapefile picked alone brings its .dbf/.prj and survives a restart', () async {
      final dir = tempDataDir();
      final c = containerFor(dir);
      await c.read(overlaysProvider.notifier).importVector([picked('fields_utm.shp')]);
      final o = c.read(overlaysProvider).single;
      expect(o.error, isNull);
      expect(o.layers.single.features, hasLength(2));
      expect(o.layers.single.features.first.attributes['NAME'], 'Café field 田');
      expect(o.spec.files, containsAll(['fields_utm.shp', 'fields_utm.dbf', 'fields_utm.prj']));
      c.read(settingsStoreProvider).flush();

      final again = containerFor(dir);
      expect(again.read(overlaysProvider).single.spec.name, 'fields_utm');
      for (var i = 0; i < 100 && again.read(overlaysProvider).single.layers.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(again.read(overlaysProvider).single.layers.single.features, hasLength(2));
    });

    test('a GeoJSON file imports as a vector overlay and survives a restart', () async {
      final dir = tempDataDir();
      final c = containerFor(dir);
      await c.read(overlaysProvider.notifier).importVector([picked('mixed.geojson')]);
      final o = c.read(overlaysProvider).single;
      expect(o.error, isNull);
      expect(o.spec.name, 'mixed');
      expect(o.spec.kind, OverlayKind.vector);
      expect(o.spec.files, ['mixed.geojson']);
      expect(o.layers.single.name, 'field survey');
      expect(o.spec.detail, contains('WGS 84'));
      expect(o.spec.bounds, isNotNull);
      c.read(settingsStoreProvider).flush();

      final again = containerFor(dir);
      for (var i = 0; i < 100 && again.read(overlaysProvider).single.layers.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(again.read(overlaysProvider).single.layers.single.features, hasLength(o.layers.single.features.length));
    });

    test('bad files fail with a readable message and leave nothing behind', () async {
      final c = containerFor(tempDataDir());
      final ctl = c.read(overlaysProvider.notifier);
      await expectLater(ctl.importGeoTiff(picked('photo.png')), throwsFormatException);
      await expectLater(ctl.importVector([picked('photo.png')]), throwsA(isA<FormatException>()));
      expect(c.read(overlaysProvider), isEmpty);
    });

    test('remove deletes tiles and copied files', () async {
      final dir = tempDataDir();
      final c = containerFor(dir);
      final engine = await c.read(tileEngineProvider.future);
      final ctl = c.read(overlaysProvider.notifier);
      await ctl.importImage(
        picked('photo.png'),
        const CentrePlacement(center: GeoPoint(18.52, 73.85), widthMetres: 60, heightMetres: 40),
      );
      final o = c.read(overlaysProvider).single.spec;
      await ctl.remove(o.id);
      expect(c.read(overlaysProvider), isEmpty);
      expect(engine.service.cache.usage().where((u) => u.source == o.sourceId), isEmpty);
      expect(Directory('${dir.path}/overlays/${o.id}').existsSync(), isFalse);
    });
  });

  testWidgets('Layers panel lists maps by provider and switching is remembered', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = tempDataDir();
    await tester.pumpWidget(ProviderScope(overrides: testOverrides(dir), child: FlightManagerApp()));

    await tester.tap(find.byTooltip('Map layers'));
    await tester.pump();
    expect(find.text('Map layers'), findsOneWidget);
    for (final group in ['Esri', 'Google', 'Microsoft', 'Mapbox', 'China']) {
      expect(find.text(group), findsOneWidget, reason: 'group heading $group');
    }
    expect(find.text('OpenStreetMap'), findsNWidgets(2)); // heading and the map itself
    expect(find.text('needs key'), findsWidgets);

    final panelList = find.descendant(of: find.byType(LayersPanel), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Google Satellite'), 80, scrollable: panelList);
    await tester.tap(find.text('Google Satellite'));
    await tester.pump();
    expect(find.textContaining('Add a Google Map Tiles API key'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Esri World Imagery'), -80, scrollable: panelList);
    await tester.tap(find.text('Esri World Imagery'));
    await tester.pump();
    await tester.scrollUntilVisible(find.textContaining('doesn\'t allow area downloads'), 80, scrollable: panelList);
    expect(find.textContaining('Esri World Imagery doesn\'t allow area downloads'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(settingsStoreProvider).flush();
    final saved = jsonDecode(File('${dir.path}/settings.json').readAsStringSync()) as Map;
    expect(saved['maps']['baseMap'], 'esri-imagery');
  });

  testWidgets('drawing a fence inside a Shapefile polygon adds points and shows no popup', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = tempDataDir();
    await tester.pumpWidget(ProviderScope(overrides: testOverrides(dir, engine: true), child: FlightManagerApp()));
    final c = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    await tester.runAsync(() async {
      await c.read(tileEngineProvider.future);
      await c.read(overlaysProvider.notifier).importVector([picked('fields_utm.shp')]);
    });
    await tester.pump();
    final ring =
        (c.read(overlaysProvider).single.layers.single.features.first.geometry as VectorPolygons).polygons.first.outer;
    final inside = LatLng(
      ring.map((p) => p.lat).reduce((a, b) => a + b) / ring.length,
      ring.map((p) => p.lon).reduce((a, b) => a + b) / ring.length,
    );

    // Put the field 400 px left of centre, clear of the connect form.
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap).first).mapController!;
    map.move(inside, 18);
    await tester.pump();
    final mapBox = tester.getRect(find.byType(FlutterMap).first);
    map.move(map.camera.screenOffsetToLatLng(map.camera.size.center(Offset.zero) + const Offset(400, 0)), 18);
    await tester.pump();
    final at = mapBox.topLeft + map.camera.latLngToScreenOffset(inside);
    expect(at.dx, lessThan(mapBox.center.dx - 300));

    c.read(fenceProvider.notifier).startDrawing();
    await tester.pump();
    for (final d in const [Offset.zero, Offset(30, 0), Offset(30, 30)]) {
      await tester.tapAt(at + d);
      await tester.pump(const Duration(milliseconds: 500)); // past the double‑tap window
    }
    expect(find.byType(AlertDialog), findsNothing);
    expect(c.read(fenceProvider).points, hasLength(3));
  });
}
