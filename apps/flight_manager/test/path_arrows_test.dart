// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_flight_manager/map/path_arrows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' hide Path;

void main() {
  const testColor = Color(0xFF00FF00);

  group('computePathArrows - Basic Path Handling', () {
    test('returns empty list for empty points list', () {
      final arrows = computePathArrows([], color: testColor);
      expect(arrows, isEmpty);
    });

    test('returns empty list for single point list', () {
      final arrows = computePathArrows(
        [const LatLng(37.0, -122.0)],
        color: testColor,
      );
      expect(arrows, isEmpty);
    });

    test('returns empty list when consecutive points are identical', () {
      final arrows = computePathArrows(
        [const LatLng(37.0, -122.0), const LatLng(37.0, -122.0)],
        color: testColor,
      );
      expect(arrows, isEmpty);
    });
  });

  group('computePathArrows - Midpoint, Bearing, and Color', () {
    test('computes arrow for northward segment >= 25.0m', () {
      // 0.001 deg latitude is approx 111.3 meters
      const p1 = LatLng(37.000, -122.0);
      const p2 = LatLng(37.001, -122.0);

      final arrows = computePathArrows([p1, p2], color: testColor);
      expect(arrows.length, equals(1));

      final arrow = arrows.first;
      expect(arrow.color, equals(testColor));
      expect(arrow.midpoint.latitude, closeTo(37.0005, 1e-6));
      expect(arrow.midpoint.longitude, closeTo(-122.0, 1e-6));
      // Northward travel bearing should be 0.0 degrees
      expect(arrow.bearingDeg, closeTo(0.0, 1e-3));
    });

    test('computes arrow for eastward segment >= 25.0m', () {
      const p1 = LatLng(0.0, 0.0);
      const p2 = LatLng(0.0, 0.001); // ~111.3 meters east

      final arrows = computePathArrows([p1, p2], color: testColor);
      expect(arrows.length, equals(1));

      final arrow = arrows.first;
      expect(arrow.color, equals(testColor));
      expect(arrow.midpoint.latitude, closeTo(0.0, 1e-6));
      expect(arrow.midpoint.longitude, closeTo(0.0005, 1e-6));
      // Eastward travel bearing should be 90.0 degrees
      expect(arrow.bearingDeg, closeTo(90.0, 1e-3));
    });

    test('computes arrow for southward segment >= 25.0m', () {
      const p1 = LatLng(37.001, -122.0);
      const p2 = LatLng(37.000, -122.0);

      final arrows = computePathArrows([p1, p2], color: testColor);
      expect(arrows.length, equals(1));

      final arrow = arrows.first;
      expect(arrow.color, equals(testColor));
      expect(arrow.midpoint.latitude, closeTo(37.0005, 1e-6));
      expect(arrow.midpoint.longitude, closeTo(-122.0, 1e-6));
      // Southward travel bearing should be 180.0 degrees
      expect(arrow.bearingDeg, closeTo(180.0, 1e-3));
    });

    test('computes arrow for westward segment >= 25.0m', () {
      const p1 = LatLng(0.0, 0.001);
      const p2 = LatLng(0.0, 0.0);

      final arrows = computePathArrows([p1, p2], color: testColor);
      expect(arrows.length, equals(1));

      final arrow = arrows.first;
      expect(arrow.color, equals(testColor));
      expect(arrow.midpoint.latitude, closeTo(0.0, 1e-6));
      expect(arrow.midpoint.longitude, closeTo(0.0005, 1e-6));
      // Westward travel bearing should be 270.0 degrees
      expect(arrow.bearingDeg, closeTo(270.0, 1e-3));
    });
  });

  group('computePathArrows - Clutter Filter by Ground Distance', () {
    test('suppresses arrows on segments shorter than 25.0m by default', () {
      // 0.0001 deg latitude is approx 11.1 meters (< 25.0m)
      const p1 = LatLng(37.0000, -122.0);
      const p2 = LatLng(37.0001, -122.0);

      final arrows = computePathArrows([p1, p2], color: testColor);
      expect(arrows, isEmpty);
    });

    test('respects custom minDistanceMeters parameter', () {
      // 0.0003 deg latitude is approx 33.4 meters
      const p1 = LatLng(37.0000, -122.0);
      const p2 = LatLng(37.0003, -122.0);

      // Default threshold (25.0m) allows it
      final allowed = computePathArrows([p1, p2], color: testColor);
      expect(allowed.length, equals(1));

      // Higher threshold (50.0m) suppresses it
      final suppressed = computePathArrows(
        [p1, p2],
        color: testColor,
        minDistanceMeters: 50.0,
      );
      expect(suppressed, isEmpty);
    });
  });

  group('computePathArrows - Clutter Filter by Screen Pixels', () {
    test('suppresses arrows when segment screen length is below minScreenPixels', () {
      // Points ~111m apart
      const p1 = LatLng(37.000, -122.0);
      const p2 = LatLng(37.001, -122.0);

      // Zoom level 5: 111 meters is tiny on screen (< 1 pixel)
      final farCamera = MapCamera(
        crs: const Epsg3857(),
        center: const LatLng(37.0, -122.0),
        zoom: 5.0,
        rotation: 0.0,
        nonRotatedSize: const Size(800, 600),
      );

      final zoomedOutArrows = computePathArrows(
        [p1, p2],
        color: testColor,
        camera: farCamera,
        minScreenPixels: 45.0,
      );
      expect(zoomedOutArrows, isEmpty);

      // Zoom level 19: 111 meters is hundreds of pixels on screen (> 45.0px)
      final closeCamera = MapCamera(
        crs: const Epsg3857(),
        center: const LatLng(37.0, -122.0),
        zoom: 19.0,
        rotation: 0.0,
        nonRotatedSize: const Size(800, 600),
      );

      final zoomedInArrows = computePathArrows(
        [p1, p2],
        color: testColor,
        camera: closeCamera,
        minScreenPixels: 45.0,
      );
      expect(zoomedInArrows.length, equals(1));
    });
  });

  group('computePathArrows - Multi-Segment Paths', () {
    test('filters each segment independently in a multi-point route', () {
      // P0 -> P1: ~111m (North, kept)
      // P1 -> P2: ~11m (East, <25m, suppressed)
      // P2 -> P3: ~111m (South, kept)
      const p0 = LatLng(37.0000, -122.0000);
      const p1 = LatLng(37.0010, -122.0000); // 111m N
      const p2 = LatLng(37.0010, -121.9999); // ~8.9m E (suppressed)
      const p3 = LatLng(37.0000, -121.9999); // 111m S

      final arrows = computePathArrows(
        [p0, p1, p2, p3],
        color: testColor,
      );

      expect(arrows.length, equals(2));

      // Segment 0: p0 -> p1
      expect(arrows[0].midpoint.latitude, closeTo(37.0005, 1e-6));
      expect(arrows[0].midpoint.longitude, closeTo(-122.0000, 1e-6));
      expect(arrows[0].bearingDeg, closeTo(0.0, 1e-3));

      // Segment 2: p2 -> p3
      expect(arrows[1].midpoint.latitude, closeTo(37.0005, 1e-6));
      expect(arrows[1].midpoint.longitude, closeTo(-121.9999, 1e-6));
      expect(arrows[1].bearingDeg, closeTo(180.0, 1e-3));
    });
  });

  group('DirectionArrow & FlightPathArrowsLayer Widget Tests', () {
    testWidgets('DirectionArrow widget renders CustomPaint without errors', (tester) async {
      await tester.pumpWidget(
        const DirectionArrow(color: testColor, size: 24.0),
      );
      expect(find.byType(DirectionArrow), findsOneWidget);
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('FlightPathArrowsLayer renders MarkerLayer with arrows inside FlutterMap', (tester) async {
      const p1 = LatLng(37.000, -122.0);
      const p2 = LatLng(37.002, -122.0); // ~222m

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(37.001, -122.0),
                initialZoom: 18.0,
              ),
              children: const [
                FlightPathArrowsLayer(
                  runs: [
                    ([p1, p2], testColor),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(FlightPathArrowsLayer), findsOneWidget);
      expect(find.byType(DirectionArrow), findsOneWidget);
    });

    testWidgets('FlightPathArrowsLayer renders nothing for short segments', (tester) async {
      const p1 = LatLng(37.0000, -122.0);
      const p2 = LatLng(37.0001, -122.0); // ~11m (< 25m)

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(37.000, -122.0),
                initialZoom: 18.0,
              ),
              children: const [
                FlightPathArrowsLayer(
                  runs: [
                    ([p1, p2], testColor),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(FlightPathArrowsLayer), findsOneWidget);
      expect(find.byType(DirectionArrow), findsNothing);
    });
  });
}
