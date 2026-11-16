// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:io';

import 'package:apx_flight_manager/design/components.dart';
import 'package:apx_flight_manager/main.dart';
import 'package:apx_flight_manager/state/payloads.dart';
import 'package:apx_flight_manager/state/plan.dart';
import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_flight_manager/vehicle/vehicle_view.dart';
import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mission/apx_mission.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support.dart';

Future<ProviderContainer> _openApp(WidgetTester tester, Directory dir) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Open zoomed in on a field, as a user planning a mission would be.
  File('${dir.path}/settings.json').writeAsStringSync('{"mapView": {"lat": 18.52, "lon": 73.85, "zoom": 17}}');
  await tester.pumpWidget(ProviderScope(overrides: testOverrides(dir), child: FlightManagerApp()));
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// A map tap: flutter_map waits out the double‑tap window first.
Future<void> _tapMap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('Plan: tap waypoints, draw a survey, convert it to waypoints, undo', (tester) async {
    final dir = tempDataDir();
    final c = await _openApp(tester, dir);
    await tester.tap(find.text('Plan'));
    await tester.pump();
    expect(find.textContaining('Add waypoints or a pattern'), findsOneWidget);

    await tester.tap(find.byTooltip('Add waypoints'));
    await tester.pump();
    for (final p in const [Offset(700, 300), Offset(900, 300), Offset(900, 500)]) {
      await _tapMap(tester, p);
    }
    await tester.tap(find.text('Done'));
    await tester.pump();
    List<MissionElement> els() => c.read(planProvider).plan.elements;
    expect(els().whereType<WaypointElement>(), hasLength(3));
    // Numbered in vehicle order: take‑off is item 1, so waypoints are 2, 3, 4.
    expect(find.text('2  Waypoint'), findsOneWidget);
    expect(find.text('4  Waypoint'), findsOneWidget);

    await tester.tap(find.byTooltip('Survey an area'));
    await tester.pump();
    for (final p in const [Offset(1000, 250), Offset(1150, 250), Offset(1150, 400), Offset(1000, 400)]) {
      await _tapMap(tester, p);
    }
    expect(find.textContaining('4 placed'), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pump();
    final survey = els().whereType<SurveyElement>().single;
    expect(c.read(planProvider).selected, survey.id);
    expect(survey.payload.payloadId, 'sprayer', reason: 'new patterns use the first payload');
    final (compiled, issues) = c.read(compiledPlanProvider);
    expect(issues.where((i) => i.level == IssueLevel.error), isEmpty);
    expect(compiled.of(survey.id).where((i) => i.command == 216), isNotEmpty, reason: 'sprayer commands generated');
    // Not connected: upload is disabled.
    final upload = tester.widget<AlloyButton>(
      find.ancestor(of: find.text('Upload'), matching: find.byType(AlloyButton)),
    );
    expect(upload.onPressed, isNull);

    final list = find.descendant(of: find.byType(ReorderableListView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Convert to waypoints'), 100, scrollable: list);
    await tester.ensureVisible(find.text('Convert to waypoints'));
    await tester.pump();
    await tester.tap(find.text('Convert to waypoints'));
    await tester.pump();
    expect(els().whereType<SurveyElement>(), isEmpty);
    final exploded = c.read(compiledPlanProvider).$1;
    expect(exploded.toWire().toString(), compiled.toWire().toString(), reason: 'same mission after converting');

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(els().whereType<SurveyElement>(), hasLength(1));

    // The working plan is autosaved for the next start.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1300)));
    await tester.pump(const Duration(seconds: 2));
    final saved = File('${dir.path}/plans/current.apxplan');
    expect(saved.existsSync(), isTrue);
    expect(PlanFiles.fromApxPlan(saved.readAsStringSync()).elements.whereType<SurveyElement>(), hasLength(1));
    c.read(settingsStoreProvider).flush();
  });

  testWidgets('Plan: mouse drags move a corner and the whole pattern, not the map; delete all waypoints', (
    tester,
  ) async {
    final dir = tempDataDir();
    final c = await _openApp(tester, dir);
    await tester.tap(find.text('Plan'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add waypoints'));
    await tester.pump();
    for (final p in const [Offset(700, 300), Offset(800, 300)]) {
      await _tapMap(tester, p);
    }
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.tap(find.byTooltip('Survey an area'));
    await tester.pump();
    for (final p in const [Offset(1000, 250), Offset(1150, 250), Offset(1150, 400), Offset(1000, 400)]) {
      await _tapMap(tester, p);
    }
    await tester.tap(find.text('Finish'));
    await tester.pump();
    SurveyElement survey() => c.read(planProvider).plan.elements.whereType<SurveyElement>().single;
    final before = survey().polygon;

    Future<void> mouseDrag(Offset from, Offset by) async {
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: from);
      await g.down(from);
      await tester.pump();
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(from + by * (i / 8));
        await tester.pump();
      }
      await g.up();
      await g.removePointer();
      await tester.pump();
    }

    // Whole pattern: the move handle shifts every corner by the same amount.
    await mouseDrag(tester.getCenter(find.byIcon(LucideIcons.move)), const Offset(40, 0));
    final moved = survey().polygon;
    final dLon = moved[0].lon - before[0].lon;
    expect(dLon, greaterThan(0), reason: 'the pattern moved, not the map');
    for (var i = 0; i < before.length; i++) {
      expect(moved[i].lat, closeTo(before[i].lat, 1e-9));
      expect(moved[i].lon - before[i].lon, closeTo(dLon, 1e-9));
    }

    // One corner: starts on the handle, so the corner moves and the map stays.
    await mouseDrag(const Offset(1040, 250), const Offset(0, -50));
    final cornered = survey().polygon;
    expect(cornered[0].lat, greaterThan(moved[0].lat));
    for (var i = 1; i < moved.length; i++) {
      expect(cornered[i], moved[i]);
    }

    // Every waypoint at once, one undo step.
    await tester.tap(find.byTooltip('Delete…'));
    await tester.pump();
    await tester.tap(find.text('Delete all waypoints (2)'));
    await tester.pump();
    await tester.pump();
    final els = c.read(planProvider).plan.elements;
    expect(els.whereType<WaypointElement>(), isEmpty);
    expect(els.whereType<SurveyElement>(), hasLength(1));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(c.read(planProvider).plan.elements.whereType<WaypointElement>(), hasLength(2));
    await tester.pump(const Duration(seconds: 5)); // snackbar and tooltips time out
    c.read(settingsStoreProvider).flush();
  });

  testWidgets('Plan: corridor tool opens cleanly; corners delete by double-click or the right-click menu', (
    tester,
  ) async {
    final c = await _openApp(tester, tempDataDir());
    await tester.tap(find.text('Plan'));
    await tester.pump();
    // Choosing Corridor used to draw an empty line, which asserts (red screen).
    await tester.tap(find.byTooltip('Corridor along a path'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final p in const [Offset(700, 300), Offset(850, 320), Offset(800, 450)]) {
      await _tapMap(tester, p);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Finish'));
    await tester.pump();
    List<GeoPoint> path() => c.read(planProvider).plan.elements.whereType<CorridorElement>().single.path;
    final before = path();
    // The move handle sits clear of the path points: dragging it shifts all of them.
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final from = tester.getCenter(find.byIcon(LucideIcons.move));
    await g.addPointer(location: from);
    await g.down(from);
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(from + const Offset(0, 30) * (i / 6));
      await tester.pump();
    }
    await g.up();
    await g.removePointer();
    await tester.pump();
    final after = path();
    for (var i = 0; i < before.length; i++) {
      expect(after[i].lat, lessThan(before[i].lat), reason: 'point $i moved south with the handle');
      expect(after[i].lon, closeTo(before[i].lon, 1e-9));
    }

    // Map taps still arrive after a handle drag (they used to stop).
    await tester.tap(find.byTooltip('Survey an area'));
    await tester.pump();
    for (final p in const [Offset(1000, 250), Offset(1150, 250), Offset(1150, 400), Offset(1000, 400)]) {
      await _tapMap(tester, p);
    }
    expect(c.read(planProvider).draft, hasLength(4));
    await tester.tap(find.text('Finish'));
    await tester.pump();
    List<GeoPoint> corners() => c.read(planProvider).plan.elements.whereType<SurveyElement>().single.polygon;

    // Double-click a corner.
    await tester.tapAt(const Offset(1150, 400), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(1150, 400), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(corners(), hasLength(3));

    // Right-click: a menu; at the minimum it explains instead of deleting.
    await tester.tapAt(const Offset(1150, 250), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('Delete point'), findsOneWidget);
    expect(find.text('A survey area needs at least 3 corners.'), findsOneWidget);
    await tester.tapAt(const Offset(20, 880)); // dismiss
    await tester.pumpAndSettle();

    // With a fourth corner back, the menu deletes.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(corners(), hasLength(4));
    await tester.tapAt(const Offset(1000, 400), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete point'));
    await tester.pumpAndSettle();
    expect(corners(), hasLength(3));
    await tester.pump(const Duration(seconds: 5));
    c.read(settingsStoreProvider).flush();
  });

  testWidgets('Vehicle → Payloads: a new spreader is saved and offered to plans', (tester) async {
    final dir = tempDataDir();
    final c = await _openApp(tester, dir);
    await tester.tap(find.text('Vehicle'));
    await tester.pump();
    await tester.tap(find.text('Payloads'));
    await tester.pump();
    expect(find.textContaining('Uses the firmware sprayer'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.tap(find.text('Spreader / seeder').last);
    await tester.pump(); // menu closes, then runs onPressed after the frame
    await tester.pump();
    final payloads = c.read(payloadsProvider);
    expect(payloads.map((p) => p.kind), [PayloadKind.sprayer, PayloadKind.spreader]);
    expect(find.textContaining('spinner, SPRAY_SPIN_CH'), findsOneWidget);

    // The plan picks it up (Plan view keeps its payload list in step).
    await tester.tap(find.text('Plan'));
    await tester.pump();
    await tester.pump();
    expect(c.read(planProvider).plan.payloads.map((p) => p.kind), contains(PayloadKind.spreader));

    c.read(settingsStoreProvider).flush();
    final saved = jsonDecode(File('${dir.path}/settings.json').readAsStringSync()) as Map;
    expect((saved['payloads'] as List), hasLength(2));
  });

  testWidgets('Settings has General, Maps and About; drone setup points to Vehicle', (tester) async {
    await _openApp(tester, tempDataDir());
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.textContaining('is in the Vehicle space'), findsOneWidget);
    await tester.tap(find.text('Maps'));
    await tester.pump();
    expect(find.text('Offline and cache'), findsOneWidget);
    expect(find.text('Online map providers (optional)'), findsOneWidget);
  });

  test('every curated vehicle setting is a real APX parameter', () {
    for (final s in vehicleSections) {
      for (final v in s.$4) {
        expect(ParamMeta.of(v.name), isNotNull, reason: '${s.$1}: ${v.name}');
      }
    }
    expect(ParamMeta.all, hasLength(158));
  });
}
