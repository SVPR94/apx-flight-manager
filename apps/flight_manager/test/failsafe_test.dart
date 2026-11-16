// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter_test/flutter_test.dart';
import 'package:apx_flight_manager/state/failsafe.dart';

void main() {
  group('FailsafeSettings', () {
    test('default failsafe thresholds and actions', () {
      const f = FailsafeSettings();
      expect(f.batteryLowVoltage, 14.8);
      expect(f.batteryLowAction, FailsafeAction.rtl);
      expect(f.batteryCriticalVoltage, 14.0);
      expect(f.batteryCriticalAction, FailsafeAction.land);
      expect(f.rcLossTimeoutSeconds, 3);
      expect(f.gcsLossTimeoutSeconds, 5);
      expect(f.geofenceEnabled, isTrue);
      expect(f.geofenceMaxAltitudeMeters, 120.0);
      expect(f.geofenceMaxRadiusMeters, 500.0);
    });

    test('json serialization roundtrip', () {
      const f = FailsafeSettings(
        batteryLowVoltage: 15.2,
        batteryLowAction: FailsafeAction.land,
        batteryCriticalVoltage: 14.2,
        batteryCriticalAction: FailsafeAction.terminate,
        gcsLossTimeoutSeconds: 8,
        gcsLossAction: FailsafeAction.brake,
        rcLossTimeoutSeconds: 4,
        rcLossAction: FailsafeAction.rtl,
        geofenceMaxAltitudeMeters: 100.0,
        geofenceMaxRadiusMeters: 400.0,
        geofenceEnabled: false,
        geofenceAction: FailsafeAction.land,
      );

      final json = f.toJson();
      final restored = FailsafeSettings.fromJson(json);

      expect(restored.batteryLowVoltage, 15.2);
      expect(restored.batteryLowAction, FailsafeAction.land);
      expect(restored.batteryCriticalVoltage, 14.2);
      expect(restored.batteryCriticalAction, FailsafeAction.terminate);
      expect(restored.gcsLossTimeoutSeconds, 8);
      expect(restored.gcsLossAction, FailsafeAction.brake);
      expect(restored.rcLossTimeoutSeconds, 4);
      expect(restored.rcLossAction, FailsafeAction.rtl);
      expect(restored.geofenceMaxAltitudeMeters, 100.0);
      expect(restored.geofenceMaxRadiusMeters, 400.0);
      expect(restored.geofenceEnabled, isFalse);
      expect(restored.geofenceAction, FailsafeAction.land);
    });
  });
}
