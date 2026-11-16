// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_flight_manager/design/tokens.dart';
import 'package:apx_flight_manager/map/overlay_edit_layer.dart';
import 'package:apx_flight_manager/map/quad_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _square = [Offset(100, 100), Offset(200, 100), Offset(200, 200), Offset(100, 200)];

Matcher _near(Offset o, [double tol = 1e-6]) => predicate<Offset>((p) => (p - o).distance < tol, 'near $o');

void main() {
  group('QuadEdit', () {
    test('a side moves along its normal only, staying parallel', () {
      // Top side dragged up and sideways: only the upward part counts.
      final q = QuadEdit.moveSide(_square, 0, const Offset(30, -20));
      expect(q[0], _near(const Offset(100, 80)));
      expect(q[1], _near(const Offset(200, 80)));
      expect(q[2], _square[2]);
      expect(q[3], _square[3]);
    });

    test('a rotated side still moves parallel to itself', () {
      final r = QuadEdit.rotate(_square, const Offset(150, 150), math.pi / 6);
      final q = QuadEdit.moveSide(r, 1, const Offset(25, 0));
      final before = r[2] - r[1], after = q[2] - q[1];
      expect(after.direction, closeTo(before.direction, 1e-9));
      expect(after.distance, closeTo(before.distance, 1e-9));
    });

    test('rotation keeps the centre and the side lengths', () {
      final q = QuadEdit.rotate(_square, QuadEdit.centre(_square), math.pi / 4);
      expect(QuadEdit.centre(q), _near(QuadEdit.centre(_square)));
      for (var i = 0; i < 4; i++) {
        expect((q[(i + 1) % 4] - q[i]).distance, closeTo(100, 1e-9));
      }
    });

    test('turn is the signed angle swept around a point', () {
      const c = Offset.zero;
      expect(QuadEdit.turn(c, const Offset(0, -10), const Offset(10, 0)), closeTo(math.pi / 2, 1e-12));
      expect(QuadEdit.turn(c, const Offset(-10, 1), const Offset(-10, -1)), closeTo(0.2, 0.01));
    });

    test('the outward normal points away from the centre', () {
      expect(QuadEdit.outwardNormal(_square, 0), _near(const Offset(0, -1)));
      expect(QuadEdit.outwardNormal(_square, 1), _near(const Offset(1, 0)));
      expect(QuadEdit.outwardNormal(_square, 2), _near(const Offset(0, 1)));
      expect(QuadEdit.outwardNormal(_square, 3), _near(const Offset(-1, 0)));
    });
  });

  group('OverlayEditLayer on a map', () {
    const centre = LatLng(18.52, 73.85);
    late MapController map;
    late List<LatLng> corners;
    late GlobalKey mapKey;

    Future<void> pump(WidgetTester tester) async {
      map = MapController();
      mapKey = GlobalKey();
      corners = const [LatLng(18.522, 73.848), LatLng(18.522, 73.852), LatLng(18.518, 73.852), LatLng(18.518, 73.848)];
      var dragging = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: alloyTheme(AlloyPalette.graphite),
          home: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 800,
              height: 600,
              child: FlutterMap(
                key: mapKey,
                mapController: map,
                options: MapOptions(
                  initialCenter: centre,
                  initialZoom: 15,
                  interactionOptions: InteractionOptions(
                    flags: dragging ? InteractiveFlag.doubleTapZoom : InteractiveFlag.all,
                  ),
                ),
                children: [
                  OverlayEditLayer(
                    corners: corners,
                    mapKey: mapKey,
                    onChanged: (c) => setState(() => corners = c),
                    onDragStart: () => setState(() => dragging = true),
                    onDragEnd: () => setState(() => dragging = false),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> drag(WidgetTester tester, String key, Offset by) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(key))));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await g.moveBy(by / 5);
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    List<Offset> screen() => [for (final c in corners) map.camera.latLngToScreenOffset(c)];

    testWidgets('dragging a corner moves that corner, not the map', (tester) async {
      await pump(tester);
      final before = screen();
      await drag(tester, 'overlay_corner_0', const Offset(-40, -30));
      expect(map.camera.center, centre);
      final after = screen();
      expect(after[0], _near(before[0] + const Offset(-40, -30), 0.5));
      for (var i = 1; i < 4; i++) {
        expect(after[i], _near(before[i], 0.01));
      }
    });

    testWidgets('dragging the top side moves it straight up', (tester) async {
      await pump(tester);
      final before = screen();
      await drag(tester, 'overlay_side_0', const Offset(25, -40));
      expect(map.camera.center, centre);
      final after = screen();
      expect(after[0], _near(before[0] + const Offset(0, -40), 0.5));
      expect(after[1], _near(before[1] + const Offset(0, -40), 0.5));
      expect(after[2], _near(before[2], 0.01));
      expect(after[3], _near(before[3], 0.01));
    });

    testWidgets('the rotate grip turns the image about its centre', (tester) async {
      await pump(tester);
      final before = screen();
      await drag(tester, 'overlay_rotate', const Offset(120, 0));
      expect(map.camera.center, centre);
      final after = screen();
      expect(QuadEdit.centre(after), _near(QuadEdit.centre(before), 0.5));
      final turned = (after[1] - after[0]).direction - (before[1] - before[0]).direction;
      expect(turned, greaterThan(0.3)); // clockwise on screen
      for (var i = 0; i < 4; i++) {
        expect((after[(i + 1) % 4] - after[i]).distance, closeTo((before[(i + 1) % 4] - before[i]).distance, 0.5));
      }
    });

    testWidgets('the centre grip moves the whole image', (tester) async {
      await pump(tester);
      final before = screen();
      await drag(tester, 'overlay_move', const Offset(60, 35));
      expect(map.camera.center, centre);
      final after = screen();
      for (var i = 0; i < 4; i++) {
        expect(after[i], _near(before[i] + const Offset(60, 35), 0.5));
      }
    });

    testWidgets('dragging empty map still pans', (tester) async {
      await pump(tester);
      await tester.dragFrom(const Offset(700, 500), const Offset(-100, -60));
      await tester.pumpAndSettle();
      expect(map.camera.center, isNot(centre));
    });
  });
}
