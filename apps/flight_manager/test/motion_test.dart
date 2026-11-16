// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_flight_manager/fly/motion.dart';
import 'package:apx_link/apx_link.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session that is never started: the test writes its snapshot directly.
VehicleSession _session() => VehicleSession(TcpLink('127.0.0.1', port: 9, label: 'test'));

const _frame = Duration(milliseconds: 16);

void main() {
  late VehicleSession session;
  late FlightMotion motion;
  late int notified;

  Future<void> setUpMotion(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    session = _session();
    motion = FlightMotion(const TestVSync());
    notified = 0;
    motion.addListener(() => notified++);
    addTearDown(motion.dispose);
  }

  void attitude(int bootMs, {double rollDeg = 0, double yawDeg = 0, double yawRateDeg = 0}) {
    session.telemetry.snapshot
      ..timeBootMs = bootMs
      ..roll = rollDeg * math.pi / 180
      ..yaw = yawDeg * math.pi / 180
      ..yawRate = yawRateDeg * math.pi / 180;
  }

  Future<void> frames(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(_frame);
    }
  }

  testWidgets('a new attitude sample is eased in over a few frames, not jumped to', (tester) async {
    await setUpMotion(tester);
    attitude(1, rollDeg: 10);
    motion.attach(session);
    await frames(tester, 2);
    expect(motion.roll, closeTo(10, 1e-6), reason: 'the first sample is shown as is');

    attitude(51, rollDeg: 20);
    await frames(tester, 1);
    expect(motion.roll, inExclusiveRange(10, 20), reason: 'one frame later it is on its way');
    final firstStep = motion.roll - 10;
    await frames(tester, 20);
    expect(motion.roll, closeTo(20, 0.05));
    expect(firstStep, lessThan(6), reason: 'no visible jump');
    motion.attach(null);
  });

  testWidgets('heading turns the short way across north and follows the yaw rate between samples', (tester) async {
    await setUpMotion(tester);
    attitude(1, yawDeg: 350);
    motion.attach(session);
    await frames(tester, 2);
    attitude(51, yawDeg: 10);
    final seen = <double>[];
    for (var i = 0; i < 20; i++) {
      await frames(tester, 1);
      seen.add(motion.heading);
    }
    expect(seen.every((h) => h >= 349 || h <= 11), isTrue, reason: 'never swings through south: $seen');
    expect(motion.heading, closeTo(10, 0.1));

    // Turning at 90°/s with samples late: the heading keeps moving (≤ 0.12 s ahead).
    attitude(101, yawDeg: 10, yawRateDeg: 90);
    await frames(tester, 12);
    expect(motion.heading, greaterThan(15));
    expect(motion.heading, lessThan(10 + 90 * 0.12 + 0.5));
    motion.attach(null);
  });

  testWidgets('position moves continuously between 10 Hz fixes', (tester) async {
    await setUpMotion(tester);
    attitude(1);
    session.telemetry.snapshot
      ..hasPosition = true
      ..lat = 18.52
      ..lon = 73.85
      ..vn = 10;
    motion.attach(session);
    await frames(tester, 2);
    final lats = <double>[];
    for (var i = 0; i < 6; i++) {
      await frames(tester, 1);
      lats.add(motion.lat);
    }
    for (var i = 1; i < lats.length; i++) {
      expect(lats[i], greaterThan(lats[i - 1]), reason: 'still moving north between fixes');
    }
    // Next fix 1 m north: no jump back.
    session.telemetry.snapshot.lat = 18.52 + 1 / 111320;
    await frames(tester, 1);
    expect(motion.lat, greaterThanOrEqualTo(lats.last - 1e-9));
    motion.attach(null);
  });

  testWidgets('a vehicle at rest stops drawing frames; a visible change wakes them', (tester) async {
    await setUpMotion(tester);
    attitude(1, rollDeg: 3, yawDeg: 45);
    session.telemetry.snapshot
      ..hasPosition = true
      ..lat = 18.52
      ..lon = 73.85
      ..altRel = 0;
    motion.attach(session);
    await frames(tester, 60);
    expect(motion.animating, isFalse, reason: 'settled: no per-frame ticker');
    final settled = notified;
    // Noise below what can be seen keeps it asleep.
    attitude(51, rollDeg: 3.03, yawDeg: 45.02);
    await frames(tester, 30);
    expect(notified, settled);
    expect(motion.animating, isFalse);
    // A real change wakes it and is eased in.
    attitude(101, rollDeg: 8, yawDeg: 45);
    await frames(tester, 3);
    expect(motion.animating, isTrue);
    await frames(tester, 40);
    expect(motion.roll, closeTo(8, 0.1));
    expect(motion.animating, isFalse);
    motion.attach(null);
  });
}
