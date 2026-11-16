// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage.dart';

enum AltitudeUnit {
  meters('Meters (m)', 'm', 1.0),
  feet('Feet (ft)', 'ft', 3.28084);

  const AltitudeUnit(this.label, this.symbol, this.toUnit);
  final String label, symbol;
  final double toUnit; // multiplier from meters
}

enum SpeedUnit {
  metersPerSecond('m/s', 'm/s', 1.0),
  kilometersPerHour('km/h', 'km/h', 3.6),
  milesPerHour('mph', 'mph', 2.23694),
  knots('knots (kt)', 'kt', 1.94384);

  const SpeedUnit(this.label, this.symbol, this.toUnit);
  final String label, symbol;
  final double toUnit; // multiplier from m/s
}

enum DistanceUnit {
  metric('Metric (m / km)'),
  imperial('Imperial (ft / mi)');

  const DistanceUnit(this.label);
  final String label;
}

enum TemperatureUnit {
  celsius('Celsius (°C)', '°C'),
  fahrenheit('Fahrenheit (°F)', '°F');

  const TemperatureUnit(this.label, this.symbol);
  final String label, symbol;
}

/// Preferences for physical measurement units across all GCS screens.
final class UnitsSettings {
  const UnitsSettings({
    this.altitude = AltitudeUnit.meters,
    this.speed = SpeedUnit.metersPerSecond,
    this.distance = DistanceUnit.metric,
    this.temperature = TemperatureUnit.celsius,
  });

  final AltitudeUnit altitude;
  final SpeedUnit speed;
  final DistanceUnit distance;
  final TemperatureUnit temperature;

  UnitsSettings copyWith({
    AltitudeUnit? altitude,
    SpeedUnit? speed,
    DistanceUnit? distance,
    TemperatureUnit? temperature,
  }) => UnitsSettings(
    altitude: altitude ?? this.altitude,
    speed: speed ?? this.speed,
    distance: distance ?? this.distance,
    temperature: temperature ?? this.temperature,
  );

  Map<String, Object?> toJson() => {
    'altitude': altitude.name,
    'speed': speed.name,
    'distance': distance.name,
    'temperature': temperature.name,
  };

  factory UnitsSettings.fromJson(Map<String, Object?> json) => UnitsSettings(
    altitude: AltitudeUnit.values.byName(json['altitude'] as String? ?? AltitudeUnit.meters.name),
    speed: SpeedUnit.values.byName(json['speed'] as String? ?? SpeedUnit.metersPerSecond.name),
    distance: DistanceUnit.values.byName(json['distance'] as String? ?? DistanceUnit.metric.name),
    temperature: TemperatureUnit.values.byName(json['temperature'] as String? ?? TemperatureUnit.celsius.name),
  );

  /// Convert altitude from meters.
  double convertAltitude(double meters) => meters.isNaN ? double.nan : meters * altitude.toUnit;

  /// Convert speed from m/s.
  double convertSpeed(double mps) => mps.isNaN ? double.nan : mps * speed.toUnit;

  /// Convert temperature from Celsius.
  double convertTemperature(double celsius) =>
      celsius.isNaN ? double.nan : (temperature == TemperatureUnit.celsius ? celsius : (celsius * 9 / 5 + 32));

  /// Formatted distance string (e.g. "124 m", "1.4 km", "420 ft", "1.2 mi").
  String formatDistance(double meters) {
    if (meters.isNaN) return '—';
    if (distance == DistanceUnit.metric) {
      if (meters >= 1000) {
        return '${(meters / 1000).toStringAsFixed(2)} km';
      }
      return '${meters.toStringAsFixed(0)} m';
    } else {
      final feet = meters * 3.28084;
      if (feet >= 5280) {
        return '${(feet / 5280).toStringAsFixed(2)} mi';
      }
      return '${feet.toStringAsFixed(0)} ft';
    }
  }
}

final class UnitsController extends Notifier<UnitsSettings> {
  static const _key = 'units_settings';

  @override
  UnitsSettings build() {
    final raw = ref.read(settingsStoreProvider).get<Map<String, Object?>>(_key);
    if (raw == null) return const UnitsSettings();
    try {
      return UnitsSettings.fromJson(raw);
    } catch (_) {
      return const UnitsSettings();
    }
  }

  void update(UnitsSettings Function(UnitsSettings current) fn) {
    state = fn(state);
    ref.read(settingsStoreProvider).set(_key, state.toJson());
  }

  void setAltitude(AltitudeUnit u) => update((s) => s.copyWith(altitude: u));
  void setSpeed(SpeedUnit u) => update((s) => s.copyWith(speed: u));
  void setDistance(DistanceUnit u) => update((s) => s.copyWith(distance: u));
  void setTemperature(TemperatureUnit u) => update((s) => s.copyWith(temperature: u));

  void setPresetMetric() => update(
    (s) => const UnitsSettings(
      altitude: AltitudeUnit.meters,
      speed: SpeedUnit.metersPerSecond,
      distance: DistanceUnit.metric,
      temperature: TemperatureUnit.celsius,
    ),
  );

  void setPresetImperial() => update(
    (s) => const UnitsSettings(
      altitude: AltitudeUnit.feet,
      speed: SpeedUnit.milesPerHour,
      distance: DistanceUnit.imperial,
      temperature: TemperatureUnit.fahrenheit,
    ),
  );

  void setPresetAviation() => update(
    (s) => const UnitsSettings(
      altitude: AltitudeUnit.feet,
      speed: SpeedUnit.knots,
      distance: DistanceUnit.imperial,
      temperature: TemperatureUnit.celsius,
    ),
  );
}

final unitsProvider = NotifierProvider<UnitsController, UnitsSettings>(UnitsController.new);
