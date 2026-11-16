// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter_test/flutter_test.dart';
import 'package:apx_flight_manager/state/units.dart';

void main() {
  group('UnitsSettings', () {
    test('default units are SI metric', () {
      const u = UnitsSettings();
      expect(u.altitude, AltitudeUnit.meters);
      expect(u.speed, SpeedUnit.metersPerSecond);
      expect(u.distance, DistanceUnit.metric);
      expect(u.temperature, TemperatureUnit.celsius);
    });

    test('metric altitude and speed conversions', () {
      const u = UnitsSettings();
      expect(u.convertAltitude(100.0), closeTo(100.0, 0.001));
      expect(u.convertSpeed(15.0), closeTo(15.0, 0.001));
      expect(u.formatDistance(450.0), '450 m');
      expect(u.formatDistance(1500.0), '1.50 km');
    });

    test('imperial conversions (feet, mph, miles, fahrenheit)', () {
      const u = UnitsSettings(
        altitude: AltitudeUnit.feet,
        speed: SpeedUnit.milesPerHour,
        distance: DistanceUnit.imperial,
        temperature: TemperatureUnit.fahrenheit,
      );

      expect(u.convertAltitude(100.0), closeTo(328.084, 0.01));
      expect(u.convertSpeed(10.0), closeTo(22.3694, 0.01));
      expect(u.convertTemperature(0.0), closeTo(32.0, 0.01));
      expect(u.convertTemperature(100.0), closeTo(212.0, 0.01));
      expect(u.formatDistance(100.0), '328 ft');
      expect(u.formatDistance(2000.0), '1.24 mi');
    });

    test('aviation knots conversion', () {
      const u = UnitsSettings(
        altitude: AltitudeUnit.feet,
        speed: SpeedUnit.knots,
        distance: DistanceUnit.imperial,
      );

      expect(u.convertSpeed(10.0), closeTo(19.4384, 0.01));
    });

    test('json serialization roundtrip', () {
      const u = UnitsSettings(
        altitude: AltitudeUnit.feet,
        speed: SpeedUnit.knots,
        distance: DistanceUnit.imperial,
        temperature: TemperatureUnit.fahrenheit,
      );

      final json = u.toJson();
      final restored = UnitsSettings.fromJson(json);

      expect(restored.altitude, AltitudeUnit.feet);
      expect(restored.speed, SpeedUnit.knots);
      expect(restored.distance, DistanceUnit.imperial);
      expect(restored.temperature, TemperatureUnit.fahrenheit);
    });
  });
}
