// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
@Tags(['sitl'])
library;

import 'dart:math';

import 'package:apx_flight_manager/state/connection.dart';
import 'package:apx_flight_manager/state/fence.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:apx_vehicle/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support.dart';

/// The geofence end to end against the real APX firmware (SITL): the app's
/// FenceController uploads the polygon and FENCE_* parameters, the firmware
/// refuses to arm outside the polygon, and an altitude breach in flight is
/// reported back (FENCE_STATUS) and triggers the configured RTL.
void main() {
  test(
    'Fence upload, pre-arm check and altitude breach on a SITL vehicle',
    () async {
      final sitl = await ApxSitl.start();
      addTearDown(sitl.stop);
      final container = ProviderContainer(overrides: testOverrides(tempDataDir()));
      addTearDown(container.dispose);
      // Keep the auto-dispose-free providers alive the way the UI does.
      container.listen(fenceProvider, (_, _) {});
      container.listen(fenceBreachProvider, (_, _) {});

      await container.read(connectionProvider.notifier).connect(TcpConfig('127.0.0.1', sitl.tcpPort));
      final session = container.read(connectionProvider)!.session;
      final s = session.telemetry.snapshot;
      final texts = <String>[];
      final sub = session.telemetry.statusMessages.listen((m) => texts.add(m.text));
      addTearDown(sub.cancel);

      Future<void> until(bool Function() ok, String what, {int seconds = 30}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ok()) {
          if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what; status: $texts');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      await until(() => session.state.value == SessionState.ready, 'session ready');
      await until(() => s.hasPosition, 'GPS position');
      final fence = container.read(fenceProvider.notifier);

      // The controller follows the vehicle's FENCE_* parameters.
      await until(() => container.read(fenceProvider).altMax == session.parameters['FENCE_ALT_MAX']!.value, 'sync');

      // Metres → degrees around the vehicle.
      final home = LatLng(s.lat, s.lon);
      LatLng at(double north, double east) =>
          LatLng(home.latitude + north / 111319.5, home.longitude + east / (111319.5 * cos(home.latitude * pi / 180)));
      void polygon(List<LatLng> pts) {
        fence.clearPoints();
        pts.forEach(fence.addPoint);
      }

      // 1. Polygon that excludes the vehicle: arming must be refused.
      polygon([at(60, -20), at(60, 20), at(100, 20), at(100, -20)]);
      await fence.setAltMax(null, 8);
      await fence.setAction(null, 1); // RTL
      await fence.toggleEnabled(null, true);
      expect(await fence.uploadToVehicle(session), isNull);
      expect(session.parameters['FENCE_ENABLE']!.value, 1);
      expect(session.parameters['FENCE_ALT_MAX']!.value, 8);
      expect(session.parameters['FENCE_ACTION']!.value, 1);

      final denied = await session.commands.arm();
      expect(denied.accepted, isFalse);
      await until(() => texts.any((t) => t.contains('outside polygon')), 'pre-arm fence message');
      expect(s.armed, isFalse);

      // The mission must not have been replaced by the fence upload.
      final mission = await session.missions.download();
      expect(mission.where((i) => i.command == MavCmd.navFencePolygonVertexInclusion), isEmpty);

      // 2. Polygon around the vehicle, 8 m ceiling: arm, climb through it.
      polygon([at(-40, -40), at(-40, 40), at(40, 40), at(40, -40)]);
      expect(await fence.uploadToVehicle(session), isNull);
      expect((await session.commands.arm()).accepted, isTrue);
      await until(() => s.armed, 'armed');
      expect(s.fenceBreached, isFalse);
      expect(container.read(fenceBreachProvider), isNull);

      expect((await session.commands.takeoff(20)).accepted, isTrue);
      await until(() => s.fenceBreached == true, 'FENCE_STATUS breach', seconds: 40);
      expect(s.fenceBreachLabel, 'altitude limit');
      await until(() => s.customMode == 6, 'RTL after breach');
      expect(texts.any((t) => t.contains('Fence breach: Altitude')), isTrue, reason: '$texts');
      // The app's breach state follows the vehicle.
      await until(() => container.read(fenceBreachProvider) == 'altitude limit', 'app breach state');

      // 3. Disabling the fence from the app clears the breach on the vehicle.
      await fence.toggleEnabled(session, false);
      await until(() => s.fenceBreached == false, 'breach cleared', seconds: 10);

      // 4. No ceiling, polygon only: flying out of the boundary breaches it.
      await fence.setAltMax(null, 0);
      await fence.toggleEnabled(null, true);
      expect(await fence.uploadToVehicle(session), isNull);
      expect((await session.commands.setMode(4)).accepted, isTrue); // GUIDED
      await until(() => s.customMode == 4, 'GUIDED');
      final out = at(90, 0);
      await session.commands.guidedGoto(out.latitude, out.longitude, 12);
      await until(() => s.fenceBreached == true, 'boundary breach', seconds: 60);
      expect(s.fenceBreachLabel, 'boundary');
      await until(() => s.customMode == 6, 'RTL after boundary breach');
      expect(texts.any((t) => t.contains('Fence breach: Polygon')), isTrue, reason: '$texts');
      // RTL brings it back inside, and the breach clears.
      await until(() => s.fenceBreached == false, 'back inside the fence', seconds: 90);

      await session.commands.land();
      await until(() => !s.armed, 'landed', seconds: 90);
    },
    skip: ApxSitl.unavailableReason,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
