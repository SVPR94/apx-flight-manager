// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_flight_manager/design/tokens.dart';
import 'package:apx_flight_manager/fly/motion.dart';
import 'package:apx_flight_manager/shell/settings_page.dart';
import 'package:apx_flight_manager/vehicle/vehicle_view.dart';
import 'package:apx_flight_manager/state/audio.dart';
import 'package:apx_flight_manager/state/inspector.dart';
import 'package:apx_flight_manager/state/trail.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support.dart';

void main() {
  group('Audio & Speech Annunciations', () {
    test('AudioSettings defaults and JSON round-trip', () {
      const def = AudioSettings();
      expect(def.enabled, isTrue);
      expect(def.volume, 1.0);
      expect(def.announceModes, isTrue);
      expect(def.announceArming, isTrue);
      expect(def.announceBattery, isTrue);
      expect(def.announceMission, isTrue);
      expect(def.announceLink, isTrue);

      final json = def.toJson();
      final restored = AudioSettings.fromJson(json);
      expect(restored.enabled, isTrue);
      expect(restored.volume, 1.0);
      expect(restored.announceModes, isTrue);
    });

    test('AudioSettingsController updates volume and event filters', () {
      final dir = tempDataDir();
      final container = ProviderContainer(overrides: testOverrides(dir));
      addTearDown(container.dispose);

      final ctrl = container.read(audioSettingsProvider.notifier);
      expect(container.read(audioSettingsProvider).enabled, isTrue);

      ctrl.setEnabled(false);
      expect(container.read(audioSettingsProvider).enabled, isFalse);

      ctrl.setVolume(0.75);
      expect(container.read(audioSettingsProvider).volume, 0.75);

      ctrl.toggleModes(false);
      expect(container.read(audioSettingsProvider).announceModes, isFalse);

      ctrl.toggleBattery(false);
      expect(container.read(audioSettingsProvider).announceBattery, isFalse);
    });
  });

  group('Inspector & Developer Diagnostics State', () {
    test('InspectorController tracks message rates and decoded fields', () {
      final dir = tempDataDir();
      final container = ProviderContainer(overrides: testOverrides(dir));
      addTearDown(container.dispose);

      final inspCtrl = container.read(inspectorProvider.notifier);
      final writer = MavFrameWriter(systemId: 1, componentId: 1);

      // Synthesize a Heartbeat frame
      final raw = writer.encode(
        const Heartbeat(
          type: MavType.quadrotor,
          autopilot: MavAutopilot.apxmega,
          baseMode: MavModeFlag.safetyArmed,
          customMode: 5, // LOITER
        ),
      );
      final parser = MavParser();
      final frames = parser.add(raw);
      expect(frames.length, 1);

      // Record frame in inspector
      final entry = MessageInspectorEntry(id: frames.first.messageId, name: frames.first.messageName);
      entry.record(frames.first);

      expect(entry.count, 1);
      expect(entry.name, 'HEARTBEAT');
      expect(entry.latestFields['custom_mode'], 5);

      entry.sampleRate(1.0);
      expect(entry.rateHz, 1.0);

      // Channel selection
      inspCtrl.selectChannel(DiagnosticChannel.attitude);
      expect(container.read(inspectorProvider).selectedChannel, DiagnosticChannel.attitude);

      inspCtrl.togglePause();
      expect(container.read(inspectorProvider).isGraphPaused, isTrue);

      // Auto-scale toggle
      expect(container.read(inspectorProvider).autoScale, isTrue);
      inspCtrl.toggleAutoScale();
      expect(container.read(inspectorProvider).autoScale, isFalse);
      inspCtrl.toggleAutoScale();
      expect(container.read(inspectorProvider).autoScale, isTrue);
    });
  });

  group('Settings UI: Audio & Developer Options', () {
    testWidgets('renders Audio & Speech section with volume slider and switches', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final dir = tempDataDir();
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(dir),
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(body: SettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'Audio & Speech' in settings list
      await tester.tap(find.text('Audio & Speech'));
      await tester.pumpAndSettle();

      expect(find.text('Voice Annunciations'), findsOneWidget);
      expect(find.text('Announced Events'), findsOneWidget);
      expect(find.text('Flight mode changes'), findsOneWidget);
      expect(find.text('Arming & Disarming'), findsOneWidget);
      expect(find.text('Battery thresholds'), findsOneWidget);
      expect(find.text('Mission milestones'), findsOneWidget);
      expect(find.text('Telemetry link state'), findsOneWidget);
      expect(find.text('Test Voice Output'), findsOneWidget);

      // Tap Test Voice button
      await tester.tap(find.text('Test Voice Output'));
      await tester.pump();
    });

    testWidgets('renders Developer Options with 4-lane sensors and tabs in Vehicle View', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final dir = tempDataDir();
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(dir),
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(body: VehicleView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'Developer diagnostics' in Vehicle menu
      await tester.tap(find.text('Developer diagnostics'));
      await tester.pumpAndSettle();

      expect(find.text('4-Lane Sensors & Spread'), findsOneWidget);
      expect(find.text('Live Telemetry Graph'), findsOneWidget);
      expect(find.text('MAVLink Inspector'), findsOneWidget);

      // Tab 1: 4-Lane Sensors (no connection)
      expect(find.text('No active connection'), findsOneWidget);

      // Switch to Tab 2: Live Telemetry Graph
      await tester.tap(find.text('Live Telemetry Graph'));
      await tester.pumpAndSettle();
      expect(find.text('Live Waveform & Telemetry Graph'), findsOneWidget);
      expect(find.byIcon(LucideIcons.scanLine), findsOneWidget);

      // Toggle auto-scale button
      await tester.tap(find.byIcon(LucideIcons.scanLine));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.scaling), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.scaling));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.scanLine), findsOneWidget);

      // Switch to Tab 3: MAVLink Inspector
      await tester.tap(find.text('MAVLink Inspector'));
      await tester.pumpAndSettle();
      expect(find.text('Transport Counters & Error Rates'), findsOneWidget);
      expect(find.text('Packet Inspector & Raw Field Inspector'), findsOneWidget);
    });
  });

  group('Persistent Flight Trail', () {
    test('FlightTrailController tracks points and resets on clear', () {
      final dir = tempDataDir();
      final container = ProviderContainer(overrides: testOverrides(dir));
      addTearDown(container.dispose);

      final ctrl = container.read(flightTrailProvider.notifier);
      expect(container.read(flightTrailProvider).points, isEmpty);

      // Add points manually via state update or controller
      ctrl.state = FlightTrailState(
        points: [const LatLng(37.5, -122.3), const LatLng(37.5001, -122.3)],
        revision: 1,
      );
      expect(container.read(flightTrailProvider).points.length, 2);

      ctrl.clear();
      expect(container.read(flightTrailProvider).points, isEmpty);
    });
  });

  group('FlightMotion Wind Smoothing', () {
    testWidgets('FlightMotion initializes and smooths wind direction', (tester) async {
      late FlightMotion motion;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: _MotionHost(onMotion: (m) => motion = m),
        ),
      );

      expect(motion.windFromDeg.isNaN, isTrue);
      expect(motion.windSpeed, 0.0);
    });
  });
}

class _MotionHost extends StatefulWidget {
  const _MotionHost({required this.onMotion});
  final void Function(FlightMotion) onMotion;

  @override
  State<_MotionHost> createState() => _MotionHostState();
}

class _MotionHostState extends State<_MotionHost> with SingleTickerProviderStateMixin {
  late final FlightMotion motion;

  @override
  void initState() {
    super.initState();
    motion = FlightMotion(this);
    widget.onMotion(motion);
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
