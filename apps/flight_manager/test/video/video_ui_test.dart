// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:apx_flight_manager/fly/fly_view.dart';
import 'package:apx_flight_manager/main.dart';
import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_flight_manager/video/video_fullscreen.dart';
import 'package:apx_flight_manager/video/video_layout.dart';
import 'package:apx_flight_manager/video/video_manager.dart';
import 'package:apx_flight_manager/video/video_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'fake_backend.dart';

void main() {
  late Directory data;
  late List<FakeVideoBackend> backends;

  setUp(() {
    data = tempDataDir();
    backends = [];
  });

  /// The app with video settings pre-stored (as after a restart).
  Future<void> pumpApp(WidgetTester tester, {VideoSettings? video, VideoLayout? layout}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = SettingsStore.open(data);
    if (video != null) store.set('video', video.toJson());
    if (layout != null) store.set('videoLayout', layout.toJson());
    store.flush();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(data),
          videoBackendFactoryProvider.overrideWithValue((s, {headless = false}) async {
            final b = FakeVideoBackend();
            backends.add(b);
            return b;
          }),
        ],
        child: const FlightManagerApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Unmounts the app so the manager's timers are cancelled.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  final videoPip = find.byKey(const ValueKey('fake-video'));

  testWidgets('Settings → Video: turning video on is saved and shows the configuration', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(find.text('Video streaming'), findsOneWidget);
    expect(find.text('Source'), findsNothing);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    // Default RTSP source with no URL: the error is shown, not a connection attempt.
    expect(find.text('Enter the stream address'), findsOneWidget);
    expect(backends, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'RTSP URL'), 'rtsp://192.168.144.25:8554/main.264');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Enter the stream address'), findsNothing);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    container.read(settingsStoreProvider).flush();
    final saved = VideoSettings.fromJson(
      SettingsStore.open(data).get<Map<String, Object?>>('video')!,
      const VideoSettings(),
    );
    expect(saved.enabled, isTrue);
    expect(saved.rtspUrl, 'rtsp://192.168.144.25:8554/main.264');
    await unmount(tester);
  });

  testWidgets('Fly view: video window over the map, swap, layouts and full screen without restarting', (tester) async {
    await pumpApp(tester, video: testVideoSettings(data));
    await tester.pump(const Duration(milliseconds: 100));
    expect(backends, hasLength(1));
    expect(backends.single.opened, hasLength(1));

    // Default layout: map with the video floating over it.
    expect(videoPip, findsOneWidget);
    expect(find.descendant(of: find.byType(FlyView), matching: find.byType(FlutterMap)), findsOneWidget);
    final pipBox = tester.getRect(videoPip);
    expect(pipBox.width, lessThan(500), reason: 'video is in the small window');

    // Tap the window: video becomes the main view, the map floats.
    await tester.tap(videoPip);
    await tester.pumpAndSettle();
    expect(tester.getRect(videoPip).width, greaterThan(1000));
    expect(find.byTooltip('Show the map'), findsOneWidget, reason: 'video tools replace map tools');
    expect(find.text('Map'), findsWidgets);

    // Layout menu: video only — the map stays mounted (state kept) but hidden.
    await tester.tap(find.byTooltip('Show the map'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Video only'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(FlyView), matching: find.byType(FlutterMap)), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FlyView),
        matching: find.byType(FlutterMap, skipOffstage: false),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(tester.getRect(videoPip).width, greaterThan(1000));

    // Full screen and back (Esc).
    await tester.tap(find.byTooltip('Full‑screen video'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoFullscreenPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(VideoFullscreenPage), findsNothing);

    // One stream through every change.
    expect(backends, hasLength(1));
    expect(backends.single.opened, hasLength(1));
    await unmount(tester);
  });

  testWidgets('Recording from the video tools shows REC and saves a file', (tester) async {
    final rec = tempDataDir();
    await pumpApp(
      tester,
      video: testVideoSettings(rec),
      layout: const VideoLayout(primary: FlyPrimary.video, pipVisible: false),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Record'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.textContaining('REC'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Stop recording'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.textContaining('Recording saved'), findsOneWidget);
    expect(rec.listSync().whereType<File>().where((f) => f.path.endsWith('.mkv')), hasLength(1));
    await unmount(tester);
  });
}
