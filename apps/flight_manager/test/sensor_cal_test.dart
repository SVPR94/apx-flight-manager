// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:apx_flight_manager/design/tokens.dart';
import 'package:apx_flight_manager/vehicle/sensor_calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Widget _wrap(Widget child, Directory dir) => ProviderScope(
  overrides: testOverrides(dir),
  child: MaterialApp(
    theme: alloyTheme(AlloyPalette.silver),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('SensorCalibrationPage renders tabs and allows guided calibration', (tester) async {
    final dir = tempDataDir();
    await tester.pumpWidget(_wrap(const SensorCalibrationPage(), dir));
    await tester.pump();

    // Verify main header and tabs
    expect(find.text('Sensor Calibration'), findsOneWidget);
    expect(find.text('Magnetometer (Compass)'), findsOneWidget);
    expect(find.text('Accelerometer (Level)'), findsOneWidget);
    expect(find.text('Gyroscope (Stillness)'), findsOneWidget);
    expect(find.text('Barometer (Pressure)'), findsOneWidget);

    // Default active is Compass
    expect(find.text('APX Compass (CalMag) Routine'), findsOneWidget);
    expect(find.text('Horizontal Circle (Yaw)'), findsOneWidget);
    expect(find.text('Vertical Tilt (Pitch/Roll)'), findsOneWidget);

    // Switch to Accelerometer tab
    await tester.tap(find.text('Accelerometer (Level)'));
    await tester.pump();
    expect(find.text('APX Accelerometer (CalAccel) Level Trim'), findsOneWidget);

    // Switch to Gyroscope tab
    await tester.tap(find.text('Gyroscope (Stillness)'));
    await tester.pump();
    expect(find.text('APX Gyroscope (CalGyro) Stillness Calibration'), findsOneWidget);

    // Start Gyroscope calibration
    await tester.tap(find.text('Start Gyroscope Calibration'));
    await tester.pump();
    expect(find.text('Abort Calibration'), findsOneWidget);

    // Abort
    await tester.tap(find.text('Abort Calibration'));
    await tester.pump();
    expect(find.text('Calibration aborted by user.'), findsOneWidget);
  });
}
