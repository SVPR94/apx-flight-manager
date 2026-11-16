// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_flight_manager/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('Left panel dock has sequence Fly, Plan, Vehicle, Link, and Exit option', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    int? exitCodeCalled;

    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(tempDataDir(), exitHandler: (code) => exitCodeCalled = code),
        child: const FlightManagerApp(),
      ),
    );

    // Verify button sequence in the left panel dock:
    // Fly -> Plan -> Vehicle -> Link -> Settings -> Exit
    final flyFinder = find.text('Fly');
    final planFinder = find.text('Plan');
    final vehicleFinder = find.text('Vehicle');
    final linkFinder = find.text('Link');
    final settingsFinder = find.text('Settings');
    final exitFinder = find.text('Exit');

    expect(flyFinder, findsOneWidget);
    expect(planFinder, findsOneWidget);
    expect(vehicleFinder, findsOneWidget);
    expect(linkFinder, findsOneWidget);
    expect(settingsFinder, findsOneWidget);
    expect(exitFinder, findsOneWidget);

    // Verify vertical order in the column
    final flyY = tester.getTopLeft(flyFinder).dy;
    final planY = tester.getTopLeft(planFinder).dy;
    final vehicleY = tester.getTopLeft(vehicleFinder).dy;
    final linkY = tester.getTopLeft(linkFinder).dy;
    final settingsY = tester.getTopLeft(settingsFinder).dy;
    final exitY = tester.getTopLeft(exitFinder).dy;

    expect(flyY < planY, isTrue, reason: 'Fly is above Plan');
    expect(planY < vehicleY, isTrue, reason: 'Plan is above Vehicle');
    expect(vehicleY < linkY, isTrue, reason: 'Vehicle is above Link');
    expect(linkY < settingsY, isTrue, reason: 'Link is above Settings');
    expect(settingsY < exitY, isTrue, reason: 'Settings is above Exit');

    // Test Exit dialog flow - Cancel
    await tester.tap(exitFinder);
    await tester.pumpAndSettle();

    expect(find.text('Exit APX Flight Manager'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Exit App'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Exit APX Flight Manager'), findsNothing);
    expect(exitCodeCalled, isNull);

    // Test Exit dialog flow - Confirm
    await tester.tap(exitFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exit App'));
    await tester.pumpAndSettle();

    expect(exitCodeCalled, 0);
  });
}
