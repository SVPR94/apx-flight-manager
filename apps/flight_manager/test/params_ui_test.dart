// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_flight_manager/main.dart';
import 'package:apx_flight_manager/state/vehicle_params.dart';
import 'package:apx_flight_manager/vehicle/param_field.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A vehicle that only answers with whatever the test pushes.
final class _Channel implements VehicleChannel {
  final _in = StreamController<MavMessage>.broadcast(sync: true);
  @override
  int get targetSystem => 1;
  @override
  int get targetComponent => 1;
  @override
  Stream<MavMessage> get messages => _in.stream;
  @override
  Future<void> send(MavMessage message) async {}
  void push(MavMessage m) => _in.add(m);
}

Future<void> _open(WidgetTester tester, List<dynamic> overrides) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: [...testOverrides(tempDataDir()), ...overrides.cast()], child: FlightManagerApp()),
  );
}

void main() {
  testWidgets('All parameters builds only the visible rows and follows value changes', (tester) async {
    final ch = _Channel();
    final svc = ParameterService(ch);
    addTearDown(svc.dispose);
    final all = ParamMeta.all.values.toList();
    for (final (i, m) in all.indexed) {
      ch.push(
        ParamValue(
          paramId: m.name,
          paramValue: m.defaultValue,
          paramType: m.isInteger ? MavParamType.int32 : MavParamType.real32,
          paramCount: all.length,
          paramIndex: i,
        ),
      );
    }
    await _open(tester, [paramServiceProvider.overrideWithValue(svc)]);
    await tester.tap(find.text('Vehicle'));
    await tester.pump();
    await tester.tap(find.text('All parameters'));
    await tester.pump();
    expect(find.text('${all.length} on the vehicle · ${all.length} shown'), findsOneWidget);
    final built = find.byType(ParamField).evaluate().length;
    expect(built, inInclusiveRange(1, 40), reason: 'rows are lazy, not all ${all.length} at once');

    // A value pushed by the vehicle shows without a rebuild of the list.
    final first = (all.map((m) => m.name).toList()..sort()).first;
    final m = ParamMeta.of(first)!;
    final next = m.defaultValue == m.max ? m.min : m.max;
    ch.push(ParamValue(paramId: first, paramValue: next, paramType: MavParamType.real32, paramCount: all.length));
    await tester.pump();
    final field = find.descendant(of: find.byType(ParamField).first, matching: find.byType(TextField));
    expect(
      double.parse(tester.widget<TextField>(field).controller!.text),
      closeTo(next, 1e-3),
      reason: '$first follows the vehicle',
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
    expect(find.byType(ParamField).evaluate().length, lessThan(60));
    await tester.pump(const Duration(seconds: 1)); // revision debounce
  });

  testWidgets('parameter download shows progress on every page, then a retry if it fails', (tester) async {
    final progress = StateProvider<ParamLoadProgress>(
      (ref) => const ParamLoadProgress(ParamLoadState.loading, 87, 153),
    );
    await _open(tester, [paramProgressProvider.overrideWith((ref) => ref.watch(progress))]);
    expect(find.text('Reading parameters  87 / 153'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2), reason: 'top strip and capsule');
    await tester.tap(find.text('Plan'));
    await tester.pump();
    expect(find.text('Reading parameters  87 / 153'), findsOneWidget);

    final c = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    c.read(progress.notifier).state = const ParamLoadProgress(
      ParamLoadState.failed,
      150,
      153,
      '3 parameters could not be read',
    );
    await tester.pump();
    expect(find.text('3 parameters could not be read'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Retry'), findsNothing);
  });
}
