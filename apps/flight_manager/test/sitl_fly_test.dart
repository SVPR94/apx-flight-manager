// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
@Tags(['sitl'])
library;

import 'package:apx_flight_manager/design/components.dart';
import 'package:apx_flight_manager/main.dart';
import 'package:apx_flight_manager/shell/shell.dart';
import 'package:apx_flight_manager/state/connection.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:apx_vehicle/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Drives the real Fly view against the real APX firmware (SITL):
/// connect → arm → take off → land, using the same slide gestures a pilot uses.
void main() {
  testWidgets(
    'Fly view arms, takes off and lands a SITL vehicle',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final sitl = (await tester.runAsync(ApxSitl.start))!;
      addTearDown(() => tester.runAsync(sitl.stop));

      await tester.pumpWidget(ProviderScope(overrides: testOverrides(tempDataDir()), child: FlightManagerApp()));
      final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
      await tester.runAsync(
        () => container.read(connectionProvider.notifier).connect(TcpConfig('127.0.0.1', sitl.tcpPort)),
      );
      final session = container.read(connectionProvider)!.session;

      // Real I/O runs outside the fake clock; pump the UI while waiting.
      Future<void> until(bool Function() ok, {int seconds = 30}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ok()) {
          if (DateTime.now().isAfter(end)) fail('Timed out; step: ${session.step.value}');
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> slide(String label) async {
        final track = find.ancestor(of: find.text(label), matching: find.byType(SlideToConfirm));
        final knob = find.descendant(of: track, matching: find.byType(GestureDetector)).last;
        await tester.drag(knob, const Offset(600, 0));
        await tester.pump();
      }

      await until(() => session.state.value == SessionState.ready);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('STABILIZE'), findsOneWidget);
      expect(find.text('DISARMED'), findsOneWidget);
      expect(find.text('Slide to arm'), findsOneWidget);

      await slide('Slide to arm');
      await until(() => session.telemetry.snapshot.armed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('ARMED'), findsOneWidget);
      expect(find.text('Slide to take off'), findsOneWidget);

      await slide('Slide to take off');
      await until(() => session.telemetry.snapshot.altRel > 3, seconds: 30);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('GUIDED'), findsOneWidget); // APX switches to Guided for take‑off
      expect(find.text('Slide to return home'), findsOneWidget);

      await tester.tap(find.text('Land'));
      await until(() => !session.telemetry.snapshot.armed, seconds: 60);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Slide to arm'), findsOneWidget);

      await tester.runAsync(() => container.read(connectionProvider.notifier).disconnect());
      await tester.pump(const Duration(milliseconds: 100));
    },
    skip: ApxSitl.unavailableReason != null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
