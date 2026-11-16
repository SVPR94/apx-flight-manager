// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apx_flight_manager/design/tokens.dart';
import 'package:apx_flight_manager/vehicle/motor_diagram.dart';

void main() {
  group('MotorLayout', () {
    test('Quad X layout produces 4 motors with alternating rotations', () {
      final motors = getMotorLayout(FrameClass.quad, FrameType.x);
      expect(motors, hasLength(4));

      // M1: Front-Right CCW
      expect(motors[0].number, 1);
      expect(motors[0].isCw, isFalse);
      expect(motors[0].angleDeg, 45);

      // M2: Rear-Left CCW
      expect(motors[1].number, 2);
      expect(motors[1].isCw, isFalse);
      expect(motors[1].angleDeg, 225);

      // M3: Front-Left CW
      expect(motors[2].number, 3);
      expect(motors[2].isCw, isTrue);
      expect(motors[2].angleDeg, 315);

      // M4: Rear-Right CW
      expect(motors[3].number, 4);
      expect(motors[3].isCw, isTrue);
      expect(motors[3].angleDeg, 135);
    });

    test('Quad + layout produces 4 cardinal motors', () {
      final motors = getMotorLayout(FrameClass.quad, FrameType.plus);
      expect(motors, hasLength(4));
      expect(motors[0].angleDeg, 0); // Front
      expect(motors[1].angleDeg, 180); // Rear
      expect(motors[2].angleDeg, 270); // Left
      expect(motors[3].angleDeg, 90); // Right
    });

    test('Hexa and Octa produce 6 and 8 motors respectively', () {
      final hexa = getMotorLayout(FrameClass.hexa, FrameType.x);
      expect(hexa, hasLength(6));

      final octa = getMotorLayout(FrameClass.octa, FrameType.x);
      expect(octa, hasLength(8));
    });
  });

  group('MotorLayoutDiagram Widget', () {
    testWidgets('renders properly with animated propellers and handles motor selection', (tester) async {
      int? selectedMotor;

      await tester.pumpWidget(
        MaterialApp(
          theme: alloyTheme(AlloyPalette.graphite),
          home: Scaffold(
            body: Center(
              child: MotorLayoutDiagram(
                frameClass: FrameClass.quad,
                frameType: FrameType.x,
                highlightedMotor: 1,
                size: 300,
                onMotorSelected: (m) => selectedMotor = m,
              ),
            ),
          ),
        ),
      );

      // Initial frame renders CustomPaint and AnimatedBuilder
      expect(find.byType(MotorLayoutDiagram), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // Pump 1 second of animation frames for propeller spin
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Tap the diagram
      await tester.tap(find.byType(MotorLayoutDiagram));
      await tester.pump();
      expect(selectedMotor, isNull);
    });
  });
}
