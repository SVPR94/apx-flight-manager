// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';
import 'dart:typed_data';

import 'package:apx_flight_manager/design/tokens.dart';
import 'package:apx_flight_manager/fly/fly_view.dart';
import 'package:apx_flight_manager/state/connection.dart';
import 'package:apx_flight_manager/state/fence.dart';
import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_flight_manager/state/trail.dart';
import 'package:apx_flight_manager/state/view_items.dart';
import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _FakeLink extends Link {
  _FakeLink() : super(const LinkDescriptor(LinkKind.tcp, 'Fake', '127.0.0.1'));

  @override
  Future<void> openTransport() async {
    state.value = LinkState.up;
  }

  @override
  Future<void> closeTransport() async {
    state.value = LinkState.closed;
  }

  @override
  Future<void> writeTransport(Uint8List frame) async {}
}

class _TestConnectionController extends ConnectionController {
  _TestConnectionController(this._conn);

  final Connection _conn;

  @override
  Connection? build() => _conn;
}

void main() {
  group('Geofence Drag & Interaction Suppression Tests (R4)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('fence_drag_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('Dragging a vertex updates fence coordinates in fenceProvider', (tester) async {
      final mapController = MapController();
      final mapKey = GlobalKey();

      final initialPoints = [
        const LatLng(10.050, 10.050),
        const LatLng(10.050, 10.055),
        const LatLng(10.055, 10.055),
      ];

      late ProviderContainer container;
      var dragStarted = false;
      var dragEnded = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataDirProvider.overrideWithValue(tempDir),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.graphite),
                home: Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: FlutterMap(
                      key: mapKey,
                      mapController: mapController,
                      options: const MapOptions(
                        initialCenter: LatLng(10.05, 10.05),
                        initialZoom: 14.0,
                      ),
                      children: [
                        GeofenceMapLayer(
                          mapKey: mapKey,
                          map: mapController,
                          onDragStart: () => dragStarted = true,
                          onDragEnd: () => dragEnded = true,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      // Initialize fence points and start drawing mode
      for (final pt in initialPoints) {
        container.read(fenceProvider.notifier).addPoint(pt);
      }
      container.read(fenceProvider.notifier).startDrawing();
      await tester.pumpAndSettle();

      expect(container.read(fenceProvider).points.length, equals(3));
      expect(container.read(fenceProvider).isDrawing, isTrue);

      // Find the first vertex marker (index 0)
      final marker0 = find.byKey(const ValueKey('fence_vertex_0'));
      expect(marker0, findsOneWidget);

      // Start drag gesture on vertex 0
      final gesture = await tester.startGesture(tester.getCenter(marker0));
      expect(dragStarted, isTrue);

      // Move marker by screen offset
      await gesture.moveBy(const Offset(50, -50));
      await tester.pump();

      final updatedPt0 = container.read(fenceProvider).points[0];
      expect(updatedPt0.latitude, isNot(equals(10.050)));
      expect(updatedPt0.longitude, isNot(equals(10.050)));

      // Vertices 1 and 2 must remain unchanged
      expect(container.read(fenceProvider).points[1], equals(const LatLng(10.050, 10.055)));
      expect(container.read(fenceProvider).points[2], equals(const LatLng(10.055, 10.055)));

      // End drag
      await gesture.up();
      await tester.pump();
      expect(dragEnded, isTrue);
    });

    testWidgets('Dragging the central move handle translates all fence points', (tester) async {
      final mapController = MapController();
      final mapKey = GlobalKey();

      final initialPoints = [
        const LatLng(10.050, 10.050),
        const LatLng(10.050, 10.055),
        const LatLng(10.055, 10.055),
      ];

      late ProviderContainer container;
      var dragStarted = false;
      var dragEnded = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataDirProvider.overrideWithValue(tempDir),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.graphite),
                home: Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: FlutterMap(
                      key: mapKey,
                      mapController: mapController,
                      options: const MapOptions(
                        initialCenter: LatLng(10.05, 10.05),
                        initialZoom: 14.0,
                      ),
                      children: [
                        GeofenceMapLayer(
                          mapKey: mapKey,
                          map: mapController,
                          onDragStart: () => dragStarted = true,
                          onDragEnd: () => dragEnded = true,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      for (final pt in initialPoints) {
        container.read(fenceProvider.notifier).addPoint(pt);
      }
      container.read(fenceProvider.notifier).startDrawing();
      await tester.pumpAndSettle();

      final initialCenter = container.read(fenceProvider).center!;

      // Find the central move handle
      final moveHandle = find.byKey(const ValueKey('fence_move_handle'));
      expect(moveHandle, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(moveHandle));
      expect(dragStarted, isTrue);

      await gesture.moveBy(const Offset(40, 40));
      await tester.pump();

      final newPoints = container.read(fenceProvider).points;
      final newCenter = container.read(fenceProvider).center!;

      final deltaLat = newCenter.latitude - initialCenter.latitude;
      final deltaLon = newCenter.longitude - initialCenter.longitude;

      expect(deltaLat.abs(), greaterThan(0.0001));
      expect(deltaLon.abs(), greaterThan(0.0001));

      // All points must be translated by exactly the centroid delta
      for (var i = 0; i < 3; i++) {
        expect(newPoints[i].latitude - initialPoints[i].latitude, closeTo(deltaLat, 1e-5));
        expect(newPoints[i].longitude - initialPoints[i].longitude, closeTo(deltaLon, 1e-5));
      }

      await gesture.up();
      await tester.pump();
      expect(dragEnded, isTrue);
    });

    testWidgets('Map interaction flags correctly suppress map dragging when fence drag is active', (tester) async {
      final mapController = MapController();
      final mapKey = GlobalKey();

      final initialPoints = [
        const LatLng(10.050, 10.050),
        const LatLng(10.050, 10.055),
        const LatLng(10.055, 10.055),
      ];

      late ProviderContainer container;
      var draggingFence = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataDirProvider.overrideWithValue(tempDir),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              container = ProviderScope.containerOf(context);
              final flags = draggingFence ? InteractiveFlag.doubleTapZoom : InteractiveFlag.all;
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.graphite),
                home: Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: FlutterMap(
                      key: mapKey,
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: const LatLng(10.05, 10.05),
                        initialZoom: 14.0,
                        interactionOptions: InteractionOptions(flags: flags),
                      ),
                      children: [
                        GeofenceMapLayer(
                          mapKey: mapKey,
                          map: mapController,
                          onDragStart: () => setState(() => draggingFence = true),
                          onDragEnd: () => setState(() => draggingFence = false),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      for (final pt in initialPoints) {
        container.read(fenceProvider.notifier).addPoint(pt);
      }
      container.read(fenceProvider.notifier).startDrawing();
      await tester.pumpAndSettle();

      // Before dragging: draggingFence is false, flags include InteractiveFlag.drag
      expect(draggingFence, isFalse);
      var flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, isNot(0));

      // Pointer down on vertex marker triggers onDragStart
      final marker0 = find.byKey(const ValueKey('fence_vertex_0'));
      final gesture = await tester.startGesture(tester.getCenter(marker0));
      await tester.pump();

      // While dragging: draggingFence is true, map dragging is suppressed
      expect(draggingFence, isTrue);
      flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.doubleTapZoom));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, equals(0));

      // Move marker
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();

      // Pointer up triggers onDragEnd
      await gesture.up();
      await tester.pump();

      // After dragging: draggingFence is false, InteractiveFlag.all is restored
      expect(draggingFence, isFalse);
      flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, isNot(0));
    });

    testWidgets('FlyView suppresses map dragging while vertex drag is active', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = SettingsStore.open(tempDir);
      store.set('mapView', {'lat': 20.0, 'lon': 0.0, 'zoom': 7.0});
      store.flush();

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataDirProvider.overrideWithValue(tempDir),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.graphite),
                home: const Scaffold(
                  body: FlyView(),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Place vertices to the west of center so they are not covered by ConnectForm
      const p0 = LatLng(20.0, -6.0);
      const p1 = LatLng(20.0, -5.8);
      const p2 = LatLng(20.2, -5.8);

      container.read(fenceProvider.notifier).addPoint(p0);
      container.read(fenceProvider.notifier).addPoint(p1);
      container.read(fenceProvider.notifier).addPoint(p2);
      container.read(fenceProvider.notifier).startDrawing();
      await tester.pumpAndSettle();

      // Initial state: map interaction flags allows all interactions including drag
      var flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, isNot(0));

      // Drag vertex 0
      final vertex0 = find.byKey(const ValueKey('fence_vertex_0'));
      expect(vertex0, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(vertex0));
      await tester.pump();

      // Map drag must now be suppressed
      flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.doubleTapZoom));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, equals(0));

      // Move vertex
      await gesture.moveBy(const Offset(25, 25));
      await tester.pump();

      // Release vertex
      await gesture.up();
      await tester.pump();

      // Flags must be restored
      flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, isNot(0));
    });

    testWidgets('FlyView suppresses map dragging while central move handle drag is active', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = SettingsStore.open(tempDir);
      store.set('mapView', {'lat': 20.0, 'lon': 0.0, 'zoom': 7.0});
      store.flush();

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataDirProvider.overrideWithValue(tempDir),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.graphite),
                home: const Scaffold(
                  body: FlyView(),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      const p0 = LatLng(20.0, -6.0);
      const p1 = LatLng(20.0, -5.8);
      const p2 = LatLng(20.2, -5.8);

      container.read(fenceProvider.notifier).addPoint(p0);
      container.read(fenceProvider.notifier).addPoint(p1);
      container.read(fenceProvider.notifier).addPoint(p2);
      container.read(fenceProvider.notifier).startDrawing();
      await tester.pumpAndSettle();

      // Find central move handle
      final moveHandle = find.byKey(const ValueKey('fence_move_handle'));
      expect(moveHandle, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(moveHandle));
      await tester.pump();

      // Map drag must now be suppressed
      var flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.doubleTapZoom));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, equals(0));

      // Move handle
      await gesture.moveBy(const Offset(20, -20));
      await tester.pump();

      // Release handle
      await gesture.up();
      await tester.pump();

      // Flags restored
      flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, isNot(0));
    });

    testWidgets('Pointer cancel restores map interaction flags and resets drag state', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = SettingsStore.open(tempDir);
      store.set('mapView', {'lat': 20.0, 'lon': 0.0, 'zoom': 7.0});
      store.flush();

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataDirProvider.overrideWithValue(tempDir),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.graphite),
                home: const Scaffold(
                  body: FlyView(),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      const p0 = LatLng(20.0, -6.0);
      const p1 = LatLng(20.0, -5.8);
      const p2 = LatLng(20.2, -5.8);

      container.read(fenceProvider.notifier).addPoint(p0);
      container.read(fenceProvider.notifier).addPoint(p1);
      container.read(fenceProvider.notifier).addPoint(p2);
      container.read(fenceProvider.notifier).startDrawing();
      await tester.pumpAndSettle();

      final vertex0 = find.byKey(const ValueKey('fence_vertex_0'));
      final gesture = await tester.startGesture(tester.getCenter(vertex0));
      await tester.pump();

      var flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.doubleTapZoom));

      // Cancel pointer event
      await gesture.cancel();
      await tester.pump();

      flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, isNot(0));
    });

    testWidgets('Dragging a geofence vertex works reliably when intersecting a flight trail line', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = SettingsStore.open(tempDir);
      store.set('mapView', {'lat': 20.0, 'lon': 0.0, 'zoom': 7.0});
      store.flush();

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataDirProvider.overrideWithValue(tempDir),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.graphite),
                home: const Scaffold(
                  body: FlyView(),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      const p0 = LatLng(20.0, -6.0);
      const p1 = LatLng(20.0, -5.8);
      const p2 = LatLng(20.2, -5.8);

      container.read(fenceProvider.notifier).addPoint(p0);
      container.read(fenceProvider.notifier).addPoint(p1);
      container.read(fenceProvider.notifier).addPoint(p2);
      container.read(fenceProvider.notifier).startDrawing();
      await tester.pumpAndSettle();

      // Set trail size to a large stroke width to verify hit testing pass-through
      container.read(viewItemSettingsProvider.notifier).setTrailSize(12.0);

      // Populate a vehicle flight trail line directly intersecting vertex 0
      final trailPoints = [
        const LatLng(19.8, -6.2),
        const LatLng(20.0, -6.0), // Directly coincides with vertex 0
        const LatLng(20.2, -5.8),
      ];
      container.read(flightTrailProvider.notifier).setPoints(trailPoints);
      await tester.pumpAndSettle();

      // Find vertex 0 marker
      final vertex0 = find.byKey(const ValueKey('fence_vertex_0'));
      expect(vertex0, findsOneWidget);

      final initialP0 = container.read(fenceProvider).points[0];
      expect(initialP0, equals(p0));

      // Drag vertex 0 through the center of the vertex marker which lies on the trail line
      final gesture = await tester.startGesture(tester.getCenter(vertex0));
      await tester.pump();

      // Map dragging must be suppressed because vertex drag is active
      var flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.doubleTapZoom));

      // Drag vertex to new position
      await gesture.moveBy(const Offset(40, -40));
      await tester.pump();

      // Verify coordinate was updated despite overlapping trail polyline
      final movedP0 = container.read(fenceProvider).points[0];
      expect(movedP0.latitude, isNot(equals(p0.latitude)));
      expect(movedP0.longitude, isNot(equals(p0.longitude)));

      // End drag
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify map interaction restored
      flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
    });

    testWidgets('Dragging a geofence vertex works reliably when intersecting a mission route', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = SettingsStore.open(tempDir);
      store.set('mapView', {'lat': 20.0, 'lon': 0.0, 'zoom': 7.0});
      store.flush();

      final link = _FakeLink();
      final session = VehicleSession(link);
      // Mission waypoints where the route segment directly intersects vertex 0 (20.0, -6.0)
      session.vehicleMission = [
        const WireMissionItem(
          seq: 0,
          command: MavCmd.navWaypoint,
          frame: MavFrame.globalRelativeAlt,
          current: 0,
          autocontinue: 1,
          param1: 0,
          param2: 0,
          param3: 0,
          param4: 0,
          x: 198000000,
          y: -62000000,
          z: 30,
        ),
        const WireMissionItem(
          seq: 1,
          command: MavCmd.navWaypoint,
          frame: MavFrame.globalRelativeAlt,
          current: 1,
          autocontinue: 1,
          param1: 0,
          param2: 0,
          param3: 0,
          param4: 0,
          x: 198000000,
          y: -62000000,
          z: 30,
        ),
        const WireMissionItem(
          seq: 2,
          command: MavCmd.navWaypoint,
          frame: MavFrame.globalRelativeAlt,
          current: 0,
          autocontinue: 1,
          param1: 0,
          param2: 0,
          param3: 0,
          param4: 0,
          x: 202000000,
          y: -58000000,
          z: 30,
        ),
      ];
      final alerts = AlertsEngine();
      final connection = Connection(TcpConfig('127.0.0.1', 5760), session, alerts);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataDirProvider.overrideWithValue(tempDir),
            connectionProvider.overrideWith(() => _TestConnectionController(connection)),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.graphite),
                home: const Scaffold(
                  body: FlyView(),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      const p0 = LatLng(20.0, -6.0);
      const p1 = LatLng(20.0, -5.8);
      const p2 = LatLng(20.2, -5.8);

      container.read(fenceProvider.notifier).addPoint(p0);
      container.read(fenceProvider.notifier).addPoint(p1);
      container.read(fenceProvider.notifier).addPoint(p2);
      container.read(fenceProvider.notifier).startDrawing();
      await tester.pumpAndSettle();

      // Set path size to large width to verify IgnorePointer pass-through
      container.read(viewItemSettingsProvider.notifier).setPathSize(12.0);
      await tester.pumpAndSettle();

      // Find vertex 0 marker
      final vertex0 = find.byKey(const ValueKey('fence_vertex_0'));
      expect(vertex0, findsOneWidget);

      final initialP0 = container.read(fenceProvider).points[0];
      expect(initialP0, equals(p0));

      // Drag vertex 0 through the center of the vertex marker which coincides with the mission route
      final gesture = await tester.startGesture(tester.getCenter(vertex0));
      await tester.pump();

      // Map dragging must be suppressed because vertex drag is active
      var flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.doubleTapZoom));

      // Move vertex
      await gesture.moveBy(const Offset(40, -40));
      await tester.pump();

      // Verify coordinate was updated reliably
      final movedP0 = container.read(fenceProvider).points[0];
      expect(movedP0.latitude, isNot(equals(p0.latitude)));
      expect(movedP0.longitude, isNot(equals(p0.longitude)));

      // End drag
      await gesture.up();
      await tester.pumpAndSettle();

      // Map dragging flag restored
      flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
    });
  });
}
