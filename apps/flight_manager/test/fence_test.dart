// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_flight_manager/state/fence.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support.dart';

void main() {
  group('FenceState & FenceController', () {
    test('default state has valid defaults', () {
      const state = FenceState();
      expect(state.enabled, isFalse);
      expect(state.points, isEmpty);
      expect(state.altMax, 50.0);
      expect(state.action, 1);
      expect(state.isDrawing, isFalse);
      expect(state.hasValidPolygon, isFalse);
    });

    test('adding and clearing points', () {
      final container = ProviderContainer(overrides: testOverrides(tempDataDir()));
      addTearDown(container.dispose);

      final ctrl = container.read(fenceProvider.notifier);

      expect(container.read(fenceProvider).points, isEmpty);
      expect(container.read(fenceProvider).hasValidPolygon, isFalse);

      ctrl.addPoint(const LatLng(37.7749, -122.4194));
      ctrl.addPoint(const LatLng(37.7750, -122.4180));
      expect(container.read(fenceProvider).points.length, 2);
      expect(container.read(fenceProvider).hasValidPolygon, isFalse);

      ctrl.addPoint(const LatLng(37.7740, -122.4185));
      expect(container.read(fenceProvider).points.length, 3);
      expect(container.read(fenceProvider).hasValidPolygon, isTrue);

      ctrl.undoPoint();
      expect(container.read(fenceProvider).points.length, 2);
      expect(container.read(fenceProvider).hasValidPolygon, isFalse);

      ctrl.clearPoints();
      expect(container.read(fenceProvider).points, isEmpty);
    });

    test('updating point vertex position', () {
      final container = ProviderContainer(overrides: testOverrides(tempDataDir()));
      addTearDown(container.dispose);

      final ctrl = container.read(fenceProvider.notifier);
      ctrl.addPoint(const LatLng(10.0, 10.0));
      ctrl.addPoint(const LatLng(10.0, 20.0));
      ctrl.addPoint(const LatLng(20.0, 20.0));

      ctrl.updatePoint(1, const LatLng(15.0, 25.0));
      expect(container.read(fenceProvider).points[1].latitude, 15.0);
      expect(container.read(fenceProvider).points[1].longitude, 25.0);
    });

    test('drawing mode flow', () {
      final container = ProviderContainer(overrides: testOverrides(tempDataDir()));
      addTearDown(container.dispose);

      final ctrl = container.read(fenceProvider.notifier);
      expect(container.read(fenceProvider).isDrawing, isFalse);

      ctrl.startDrawing();
      expect(container.read(fenceProvider).isDrawing, isTrue);

      ctrl.addPoint(const LatLng(0, 0));
      ctrl.addPoint(const LatLng(0, 1));
      ctrl.addPoint(const LatLng(1, 1));

      ctrl.finishDrawing();
      expect(container.read(fenceProvider).isDrawing, isFalse);
      expect(container.read(fenceProvider).hasValidPolygon, isTrue);
    });

    test('altitude ceiling with 0 meaning no limit', () {
      final container = ProviderContainer(overrides: testOverrides(tempDataDir()));
      addTearDown(container.dispose);

      final ctrl = container.read(fenceProvider.notifier);
      ctrl.setAltMax(null, 0.0);
      expect(container.read(fenceProvider).altMax, 0.0);

      ctrl.setAltMax(null, 120.0);
      expect(container.read(fenceProvider).altMax, 120.0);
    });

    test('moving fence translates vertices and repositions centroid', () {
      final container = ProviderContainer(overrides: testOverrides(tempDataDir()));
      addTearDown(container.dispose);

      final ctrl = container.read(fenceProvider.notifier);
      ctrl.addPoint(const LatLng(10.0, 10.0));
      ctrl.addPoint(const LatLng(10.0, 20.0));
      ctrl.addPoint(const LatLng(20.0, 20.0));
      ctrl.addPoint(const LatLng(20.0, 10.0));

      final center = container.read(fenceProvider).center;
      expect(center, isNotNull);
      expect(center!.latitude, closeTo(15.0, 0.001));
      expect(center.longitude, closeTo(15.0, 0.001));

      // Translate by dLat=5, dLon=-5
      ctrl.translate(5.0, -5.0);
      final newCenter = container.read(fenceProvider).center;
      expect(newCenter!.latitude, closeTo(20.0, 0.001));
      expect(newCenter.longitude, closeTo(10.0, 0.001));
      expect(container.read(fenceProvider).points[0].latitude, closeTo(15.0, 0.001));
      expect(container.read(fenceProvider).points[0].longitude, closeTo(5.0, 0.001));

      // Move to target center (0, 0)
      ctrl.moveTo(const LatLng(0, 0));
      final zeroCenter = container.read(fenceProvider).center;
      expect(zeroCenter!.latitude, closeTo(0.0, 0.001));
      expect(zeroCenter.longitude, closeTo(0.0, 0.001));

      // Toggle moving mode
      expect(container.read(fenceProvider).isMoving, isFalse);
      ctrl.startMoving();
      expect(container.read(fenceProvider).isMoving, isTrue);
      ctrl.finishMoving();
      expect(container.read(fenceProvider).isMoving, isFalse);
    });
  });
}
