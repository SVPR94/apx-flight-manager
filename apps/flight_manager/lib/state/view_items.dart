// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage.dart';

/// Information describing a vehicle type for customization.
class VehicleTypeInfo {
  const VehicleTypeInfo(this.type, this.label);
  final int type;
  final String label;
}

const defaultVehicleTypes = <VehicleTypeInfo>[
  VehicleTypeInfo(MavType.quadrotor, 'Quadrotor'),
  VehicleTypeInfo(MavType.hexarotor, 'Hexarotor'),
  VehicleTypeInfo(MavType.octorotor, 'Octorotor'),
  VehicleTypeInfo(MavType.fixedWing, 'Fixed Wing'),
  VehicleTypeInfo(MavType.vtolQuadrotor, 'VTOL'),
  VehicleTypeInfo(MavType.helicopter, 'Helicopter'),
  VehicleTypeInfo(MavType.groundRover, 'Ground Rover'),
  VehicleTypeInfo(MavType.surfaceBoat, 'Surface Boat'),
  VehicleTypeInfo(MavType.generic, 'Generic'),
];

/// Configuration settings for view items display sizes and vehicle icons.
final class ViewItemSettings {
  const ViewItemSettings({
    this.droneIconSize = defaultDroneIconSize,
    this.pathSize = defaultPathSize,
    this.trailSize = defaultTrailSize,
    this.customVehicleIcons = const <int, String>{},
  });

  static const double defaultDroneIconSize = 56.0;
  static const double defaultPathSize = 4.5;
  static const double defaultTrailSize = 3.8;

  static const double minDroneIconSize = 24.0;
  static const double maxDroneIconSize = 120.0;
  static const double minPathSize = 1.0;
  static const double maxPathSize = 12.0;
  static const double minTrailSize = 1.0;
  static const double maxTrailSize = 12.0;

  final double droneIconSize;
  final double pathSize;
  final double trailSize;
  final Map<int, String> customVehicleIcons;

  ViewItemSettings copyWith({
    double? droneIconSize,
    double? pathSize,
    double? trailSize,
    Map<int, String>? customVehicleIcons,
  }) => ViewItemSettings(
    droneIconSize: droneIconSize ?? this.droneIconSize,
    pathSize: pathSize ?? this.pathSize,
    trailSize: trailSize ?? this.trailSize,
    customVehicleIcons: customVehicleIcons ?? this.customVehicleIcons,
  );

  Map<String, Object?> toJson() => {
    'droneIconSize': droneIconSize,
    'pathSize': pathSize,
    'trailSize': trailSize,
    'customVehicleIcons': {
      for (final entry in customVehicleIcons.entries) entry.key.toString(): entry.value,
    },
  };

  factory ViewItemSettings.fromJson(Map<String, Object?> json) {
    final rawIcons = json['customVehicleIcons'];
    final icons = <int, String>{};
    if (rawIcons is Map) {
      for (final entry in rawIcons.entries) {
        final k = entry.key is int ? entry.key as int : int.tryParse(entry.key.toString());
        if (k != null && entry.value is String) {
          icons[k] = entry.value as String;
        }
      }
    }
    return ViewItemSettings(
      droneIconSize: (json['droneIconSize'] as num?)?.toDouble() ?? defaultDroneIconSize,
      pathSize: (json['pathSize'] as num?)?.toDouble() ?? defaultPathSize,
      trailSize: (json['trailSize'] as num?)?.toDouble() ?? defaultTrailSize,
      customVehicleIcons: icons,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ViewItemSettings) return false;
    if (other.droneIconSize != droneIconSize ||
        other.pathSize != pathSize ||
        other.trailSize != trailSize ||
        other.customVehicleIcons.length != customVehicleIcons.length) {
      return false;
    }
    for (final entry in customVehicleIcons.entries) {
      if (other.customVehicleIcons[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    droneIconSize,
    pathSize,
    trailSize,
    Object.hashAll(customVehicleIcons.keys),
    Object.hashAll(customVehicleIcons.values),
  );
}

final class ViewItemSettingsController extends Notifier<ViewItemSettings> {
  static const _key = 'view_item_settings';

  @override
  ViewItemSettings build() {
    final raw = ref.read(settingsStoreProvider).get<Map>(_key);
    if (raw == null) return const ViewItemSettings();
    try {
      return ViewItemSettings.fromJson(raw.cast<String, Object?>());
    } catch (_) {
      return const ViewItemSettings();
    }
  }

  void _persist() {
    ref.read(settingsStoreProvider).set(_key, state.toJson());
  }

  void setDroneIconSize(double size) {
    state = state.copyWith(droneIconSize: size);
    _persist();
  }

  void setPathSize(double size) {
    state = state.copyWith(pathSize: size);
    _persist();
  }

  void setTrailSize(double size) {
    state = state.copyWith(trailSize: size);
    _persist();
  }

  void setCustomIcon(int vehicleType, String filePath) {
    final updated = Map<int, String>.from(state.customVehicleIcons);
    updated[vehicleType] = filePath;
    state = state.copyWith(customVehicleIcons: updated);
    _persist();
  }

  void clearCustomIcon(int vehicleType) {
    final updated = Map<int, String>.from(state.customVehicleIcons);
    updated.remove(vehicleType);
    state = state.copyWith(customVehicleIcons: updated);
    _persist();
  }

  void resetDefaults() {
    state = const ViewItemSettings();
    _persist();
  }
}

final viewItemSettingsProvider =
    NotifierProvider<ViewItemSettingsController, ViewItemSettings>(ViewItemSettingsController.new);
