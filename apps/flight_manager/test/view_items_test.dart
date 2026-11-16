// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:apx_flight_manager/design/tokens.dart';
import 'package:apx_flight_manager/fly/fly_view.dart';
import 'package:apx_flight_manager/fly/instruments.dart';
import 'package:apx_flight_manager/plan/plan_view.dart';
import 'package:apx_flight_manager/shell/settings_page.dart';
import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_flight_manager/state/view_items.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Valid 1x1 transparent PNG bytes for testing image rendering.
const _transparent1x1PngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('view_items_test_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ViewItemSettings Model', () {
    test('default constructor initializes expected default sizes', () {
      const settings = ViewItemSettings();
      expect(settings.droneIconSize, equals(56.0));
      expect(settings.pathSize, equals(4.5));
      expect(settings.trailSize, equals(3.8));
      expect(settings.customVehicleIcons, isEmpty);
    });

    test('copyWith modifies selected fields and preserves others', () {
      const initial = ViewItemSettings();
      final updated = initial.copyWith(
        droneIconSize: 72.0,
        pathSize: 6.0,
        customVehicleIcons: {MavType.quadrotor: '/path/to/quad.png'},
      );

      expect(updated.droneIconSize, equals(72.0));
      expect(updated.pathSize, equals(6.0));
      expect(updated.trailSize, equals(3.8));
      expect(updated.customVehicleIcons[MavType.quadrotor], equals('/path/to/quad.png'));
    });

    test('toJson and fromJson serialize and deserialize correctly', () {
      const original = ViewItemSettings(
        droneIconSize: 80.0,
        pathSize: 7.5,
        trailSize: 5.2,
        customVehicleIcons: {
          MavType.quadrotor: '/icons/quad.png',
          MavType.hexarotor: '/icons/hexa.png',
        },
      );

      final json = original.toJson();
      expect(json['droneIconSize'], equals(80.0));
      expect(json['pathSize'], equals(7.5));
      expect(json['trailSize'], equals(5.2));
      expect(json['customVehicleIcons'], isA<Map>());
      final iconMap = json['customVehicleIcons'] as Map;
      expect(iconMap['${MavType.quadrotor}'], equals('/icons/quad.png'));
      expect(iconMap['${MavType.hexarotor}'], equals('/icons/hexa.png'));

      final restored = ViewItemSettings.fromJson(json);
      expect(restored, equals(original));
      expect(restored.customVehicleIcons[MavType.quadrotor], equals('/icons/quad.png'));
      expect(restored.customVehicleIcons[MavType.hexarotor], equals('/icons/hexa.png'));
    });

    test('fromJson falls back to defaults on missing or malformed fields', () {
      final empty = ViewItemSettings.fromJson({});
      expect(empty.droneIconSize, equals(56.0));
      expect(empty.pathSize, equals(4.5));
      expect(empty.trailSize, equals(3.8));
      expect(empty.customVehicleIcons, isEmpty);

      final partial = ViewItemSettings.fromJson({
        'droneIconSize': 64,
        'customVehicleIcons': {'not_an_int': '/path.png', '2': '/valid.png'},
      });
      expect(partial.droneIconSize, equals(64.0));
      expect(partial.pathSize, equals(4.5));
      expect(partial.customVehicleIcons.length, equals(1));
      expect(partial.customVehicleIcons[2], equals('/valid.png'));
    });

    test('equality and hashCode work as expected', () {
      const a = ViewItemSettings(droneIconSize: 40.0, customVehicleIcons: {1: 'a'});
      const b = ViewItemSettings(droneIconSize: 40.0, customVehicleIcons: {1: 'a'});
      const c = ViewItemSettings(droneIconSize: 42.0, customVehicleIcons: {1: 'a'});
      const d = ViewItemSettings(droneIconSize: 40.0, customVehicleIcons: {1: 'b'});

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });
  });

  group('ViewItemSettingsController & Persistence', () {
    test('updates sizes and persists to SettingsStore', () {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      final notifier = container.read(viewItemSettingsProvider.notifier);
      expect(container.read(viewItemSettingsProvider).droneIconSize, equals(56.0));

      notifier.setDroneIconSize(75.0);
      expect(container.read(viewItemSettingsProvider).droneIconSize, equals(75.0));

      notifier.setPathSize(8.0);
      expect(container.read(viewItemSettingsProvider).pathSize, equals(8.0));

      notifier.setTrailSize(6.5);
      expect(container.read(viewItemSettingsProvider).trailSize, equals(6.5));

      // Flush store and verify on a fresh container
      container.read(settingsStoreProvider).flush();

      final container2 = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container2.dispose);

      final restored = container2.read(viewItemSettingsProvider);
      expect(restored.droneIconSize, equals(75.0));
      expect(restored.pathSize, equals(8.0));
      expect(restored.trailSize, equals(6.5));
    });

    test('manages custom vehicle icons and persists them', () {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      final notifier = container.read(viewItemSettingsProvider.notifier);

      notifier.setCustomIcon(MavType.quadrotor, '/custom/quad.png');
      notifier.setCustomIcon(MavType.fixedWing, '/custom/wing.png');

      var state = container.read(viewItemSettingsProvider);
      expect(state.customVehicleIcons[MavType.quadrotor], equals('/custom/quad.png'));
      expect(state.customVehicleIcons[MavType.fixedWing], equals('/custom/wing.png'));

      notifier.clearCustomIcon(MavType.quadrotor);
      state = container.read(viewItemSettingsProvider);
      expect(state.customVehicleIcons.containsKey(MavType.quadrotor), isFalse);
      expect(state.customVehicleIcons[MavType.fixedWing], equals('/custom/wing.png'));

      container.read(settingsStoreProvider).flush();

      final container2 = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container2.dispose);

      final restored = container2.read(viewItemSettingsProvider);
      expect(restored.customVehicleIcons[MavType.fixedWing], equals('/custom/wing.png'));
      expect(restored.customVehicleIcons.containsKey(MavType.quadrotor), isFalse);
    });

    test('resetDefaults restores all default settings and persists', () {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      final notifier = container.read(viewItemSettingsProvider.notifier);
      notifier.setDroneIconSize(100.0);
      notifier.setPathSize(11.0);
      notifier.setTrailSize(9.0);
      notifier.setCustomIcon(MavType.quadrotor, '/icon.png');

      notifier.resetDefaults();

      final state = container.read(viewItemSettingsProvider);
      expect(state.droneIconSize, equals(56.0));
      expect(state.pathSize, equals(4.5));
      expect(state.trailSize, equals(3.8));
      expect(state.customVehicleIcons, isEmpty);

      container.read(settingsStoreProvider).flush();

      final container2 = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container2.dispose);

      final restored = container2.read(viewItemSettingsProvider);
      expect(restored, equals(const ViewItemSettings()));
    });
  });

  group('VehicleGlyph Widget', () {
    test('VehicleGlyph.armsOf returns correct arm counts', () {
      expect(VehicleGlyph.armsOf(MavType.quadrotor), equals(4));
      expect(VehicleGlyph.armsOf(MavType.hexarotor), equals(6));
      expect(VehicleGlyph.armsOf(MavType.octorotor), equals(8));
      expect(VehicleGlyph.armsOf(MavType.fixedWing), equals(4));
      expect(VehicleGlyph.armsOf(null), equals(4));
    });

    testWidgets('renders vector CustomPaint fallback when no custom icon is set', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: alloyTheme(AlloyPalette.silver),
          home: const Scaffold(
            body: VehicleGlyph(
              arms: 4,
              headingDeg: 45.0,
              size: 56.0,
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(Image), findsNothing);

      final transformFinder = find.descendant(
        of: find.byType(VehicleGlyph),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);
    });

    testWidgets('renders vector fallback when custom icon file does not exist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: alloyTheme(AlloyPalette.silver),
          home: const Scaffold(
            body: VehicleGlyph(
              headingDeg: 90.0,
              size: 56.0,
              vehicleType: MavType.quadrotor,
              customIconPath: '/non/existent/path/icon.png',
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('renders Image.file when valid transparent PNG file is provided', (tester) async {
      final iconFile = File('${tempDir.path}/test_icon.png');
      iconFile.writeAsBytesSync(_transparent1x1PngBytes);

      await tester.pumpWidget(
        MaterialApp(
          theme: alloyTheme(AlloyPalette.silver),
          home: Scaffold(
            body: VehicleGlyph(
              headingDeg: 180.0,
              size: 64.0,
              vehicleType: MavType.quadrotor,
              customIconPath: iconFile.path,
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      final img = tester.widget<Image>(find.byType(Image));
      expect(img.width, equals(64.0));
      expect(img.height, equals(64.0));
      expect(img.fit, equals(BoxFit.contain));

      final transformFinder = find.descendant(
        of: find.byType(VehicleGlyph),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);
    });

    testWidgets('resolves custom vehicle icon reactively from viewItemSettingsProvider', (tester) async {
      final iconFile = File('${tempDir.path}/reactive_icon.png');
      iconFile.writeAsBytesSync(_transparent1x1PngBytes);

      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(
              body: VehicleGlyph(
                headingDeg: 0.0,
                size: 56.0,
                vehicleType: MavType.hexarotor,
              ),
            ),
          ),
        ),
      );

      // Initially no custom icon
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);

      // Set custom icon for hexarotor
      container.read(viewItemSettingsProvider.notifier).setCustomIcon(MavType.hexarotor, iconFile.path);
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();

      // Now renders custom Image
      expect(find.byType(Image), findsOneWidget);

      // Clear custom icon
      container.read(viewItemSettingsProvider.notifier).clearCustomIcon(MavType.hexarotor);
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();

      // Falls back to CustomPaint
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('Settings UI: ViewItemsSection', () {
    testWidgets('displays sliders, vehicle type selector, and reset button', (tester) async {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(
              body: SingleChildScrollView(child: ViewItemsSection()),
            ),
          ),
        ),
      );

      expect(find.text('View Items'), findsOneWidget);
      expect(find.text('Drone Icon Size'), findsOneWidget);
      expect(find.text('Flight Plan Path Size'), findsOneWidget);
      expect(find.text('Vehicle Trail Line Size'), findsOneWidget);
      expect(find.text('Custom Vehicle Icons'), findsOneWidget);
      expect(find.text('Reset to Defaults'), findsOneWidget);

      expect(find.byKey(const Key('drone_icon_size_slider')), findsOneWidget);
      expect(find.byKey(const Key('path_size_slider')), findsOneWidget);
      expect(find.byKey(const Key('trail_size_slider')), findsOneWidget);
      expect(find.byKey(const Key('vehicle_type_dropdown')), findsOneWidget);
    });

    testWidgets('changing slider values updates ViewItemSettings state', (tester) async {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(
              body: SingleChildScrollView(child: ViewItemsSection()),
            ),
          ),
        ),
      );

      // Update Drone Icon Size via controller and verify UI reflection
      container.read(viewItemSettingsProvider.notifier).setDroneIconSize(84.0);
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();
      expect(find.text('84 px'), findsOneWidget);

      // Update Path Size via controller and verify UI reflection
      container.read(viewItemSettingsProvider.notifier).setPathSize(7.2);
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();
      expect(find.text('7.2 px'), findsOneWidget);

      // Update Trail Size via controller and verify UI reflection
      container.read(viewItemSettingsProvider.notifier).setTrailSize(5.5);
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();
      expect(find.text('5.5 px'), findsOneWidget);

      // Test Reset to Defaults button
      await tester.tap(find.text('Reset to Defaults'));
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();

      final resetState = container.read(viewItemSettingsProvider);
      expect(resetState.droneIconSize, equals(56.0));
      expect(resetState.pathSize, equals(4.5));
      expect(resetState.trailSize, equals(3.8));
    });

    testWidgets('custom icon path input updates custom vehicle icon setting', (tester) async {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(
              body: SingleChildScrollView(child: ViewItemsSection()),
            ),
          ),
        ),
      );

      final pathField = find.byKey(const Key('custom_icon_path_field'));
      expect(pathField, findsOneWidget);

      await tester.enterText(pathField, '/images/my_quad.png');
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();

      expect(
        container.read(viewItemSettingsProvider).customVehicleIcons[MavType.quadrotor],
        equals('/images/my_quad.png'),
      );
      expect(find.text('Custom PNG Graphic Set'), findsOneWidget);
      expect(find.text('Clear Icon'), findsOneWidget);

      // Tapping Clear Icon
      await tester.tap(find.text('Clear Icon'));
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();

      expect(
        container.read(viewItemSettingsProvider).customVehicleIcons.containsKey(MavType.quadrotor),
        isFalse,
      );
      expect(find.text('Default Vector Glyph Active'), findsOneWidget);
    });

    testWidgets('SettingsPage integrates View Items in navigation sidebar', (tester) async {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(
              body: SettingsPage(initialSection: 5),
            ),
          ),
        ),
      );

      // View Items section is displayed
      expect(find.text('Drone Icon Size'), findsOneWidget);
      expect(find.text('Flight Plan Path Size'), findsOneWidget);
      expect(find.text('Vehicle Trail Line Size'), findsOneWidget);
      expect(find.text('Custom Vehicle Icons'), findsOneWidget);

      // Sidebar also displays View Items
      expect(find.widgetWithText(ListTile, 'View Items'), findsOneWidget);
    });
  });

  group('Dynamic View Sizing Reactive Updates', () {
    testWidgets('modifying droneIconSize dynamically updates size in VehicleGlyph', (tester) async {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              final size = ref.watch(viewItemSettingsProvider).droneIconSize;
              return MaterialApp(
                theme: alloyTheme(AlloyPalette.silver),
                home: Scaffold(
                  body: Center(
                    child: VehicleGlyph(
                      headingDeg: 0,
                      size: size,
                      vehicleType: MavType.quadrotor,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      final glyphSizedBoxFinder = find.descendant(
        of: find.byType(VehicleGlyph),
        matching: find.byType(SizedBox),
      );
      var sizedBox = tester.widget<SizedBox>(glyphSizedBoxFinder.first);
      expect(sizedBox.width, equals(56.0));
      expect(sizedBox.height, equals(56.0));

      // Dynamically update size to 96
      container.read(viewItemSettingsProvider.notifier).setDroneIconSize(96.0);
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();

      sizedBox = tester.widget<SizedBox>(glyphSizedBoxFinder.first);
      expect(sizedBox.width, equals(96.0));
      expect(sizedBox.height, equals(96.0));
    });
  });

  group('FlyView & PlanView Dynamic Size Integration', () {
    testWidgets('FlyView mounts and dynamically reflects view item settings updates', (tester) async {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(
              body: FlyView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlyView), findsOneWidget);

      // Dynamically update view item sizes
      container.read(viewItemSettingsProvider.notifier).setDroneIconSize(72.0);
      container.read(viewItemSettingsProvider.notifier).setPathSize(6.5);
      container.read(viewItemSettingsProvider.notifier).setTrailSize(5.0);
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();

      expect(container.read(viewItemSettingsProvider).droneIconSize, equals(72.0));
      expect(container.read(viewItemSettingsProvider).pathSize, equals(6.5));
      expect(container.read(viewItemSettingsProvider).trailSize, equals(5.0));
    });

    testWidgets('PlanView mounts and dynamically reflects view item settings updates', (tester) async {
      final container = ProviderContainer(
        overrides: testOverrides(tempDir),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: alloyTheme(AlloyPalette.silver),
            home: const Scaffold(
              body: PlanView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlanView), findsOneWidget);

      container.read(viewItemSettingsProvider.notifier).setPathSize(8.0);
      container.read(viewItemSettingsProvider.notifier).setDroneIconSize(64.0);
      container.read(settingsStoreProvider).flush();
      await tester.pumpAndSettle();

      expect(container.read(viewItemSettingsProvider).pathSize, equals(8.0));
      expect(container.read(viewItemSettingsProvider).droneIconSize, equals(64.0));
    });
  });
}
