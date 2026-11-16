// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_flight_manager/design/components.dart';
import 'package:apx_flight_manager/design/fields.dart';
import 'package:apx_flight_manager/design/tokens.dart';
import 'package:apx_flight_manager/fly/instruments.dart';
import 'package:apx_flight_manager/fly/mode_ring.dart';
import 'package:apx_flight_manager/main.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Widget _themed(Widget child, [AlloyPalette p = AlloyPalette.silver]) => MaterialApp(
  theme: alloyTheme(p),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('opens on Fly with the connect form; UDP listen defaults to 14550', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(overrides: testOverrides(tempDataDir()), child: FlightManagerApp()));
    expect(find.text('Connect to a vehicle'), findsOneWidget);
    expect(find.text('5760'), findsOneWidget);
    // Only working spaces are in the dock.
    expect(find.text('Fly'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Vehicle'), findsOneWidget);
    expect(find.text('Logs'), findsNothing);

    await tester.tap(find.text('UDP listen'));
    await tester.pump();
    expect(find.text('14550'), findsOneWidget);
  });

  testWidgets('mode ring offers only real APX modes and returns the choice', (tester) async {
    int? chosen;
    await tester.pumpWidget(
      _themed(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => chosen = await showModeRing(context, apx01Profile, 0),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Loiter'), findsOneWidget);
    expect(find.text('= loiter'), findsOneWidget); // POS_HOLD shown as an alias
    expect(find.text('Agri Spray'), findsNothing); // placeholder in APX 0.1
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(chosen, 6);
  });

  testWidgets('instruments paint in both themes', (tester) async {
    for (final p in [AlloyPalette.silver, AlloyPalette.graphite]) {
      await tester.pumpWidget(
        _themed(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tape(title: 'GS', value: 4.8, step: 2),
              AttitudeIndicator(rollRad: 0.14, pitchRad: -0.05, headingDeg: 135, windFromDeg: 270),
              Tape(title: 'ALT', value: 15, step: 5, trend: 0.4),
              VehicleGlyph(arms: 6, headingDeg: 135),
            ],
          ),
          p,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('4.8'), findsOneWidget);
      expect(find.text('15.0'), findsOneWidget);
    }
  });

  testWidgets('slide to confirm fires only when dragged to the end', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      _themed(
        SizedBox(
          width: 300,
          child: SlideToConfirm(
            label: 'Slide to arm',
            icon: Icons.power_settings_new,
            onConfirmed: () async => fired++,
          ),
        ),
      ),
    );
    final knob = find.byIcon(Icons.power_settings_new);

    await tester.drag(knob, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(fired, 0, reason: 'half a slide springs back');

    await tester.drag(knob, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  testWidgets('number fields keep significant zeros and trim only decimals', (tester) async {
    Future<String> shown(double v, {int decimals = 1}) async {
      await tester.pumpWidget(
        _themed(NumField(key: UniqueKey(), label: 'x', value: v, decimals: decimals, onChanged: (_) {})),
      );
      return tester.widget<TextField>(find.byType(TextField)).controller!.text;
    }

    expect(await shown(360, decimals: 0), '360');
    expect(await shown(0, decimals: 0), '0');
    expect(await shown(20), '20');
    expect(await shown(20.5), '20.5');
    expect(await shown(0.25, decimals: 3), '0.25');
    expect(await shown(100, decimals: 2), '100');
  });

  testWidgets('field labels sit inside the box, never across its edge', (tester) async {
    // An outline label straddles the border: half over the white fill, half
    // over the panel behind, which reads as a muddy patch on glass.
    for (final p in [AlloyPalette.silver, AlloyPalette.graphite]) {
      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: 200,
            child: NumField(label: 'Altitude', value: 20, onChanged: (_) {}),
          ),
          p,
        ),
      );
      final field = tester.getRect(find.byType(InputDecorator));
      final label = tester.getRect(find.text('Altitude'));
      expect(label.top, greaterThanOrEqualTo(field.top + 2), reason: 'label inside the field (${p.brightness})');
      final focused = await tester.startGesture(tester.getCenter(find.byType(TextField)));
      await focused.up();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Altitude')).top,
        greaterThanOrEqualTo(field.top + 2),
        reason: 'also when focused',
      );
    }
  });
}
