// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_mavlink/apx_mavlink.dart';

/// Single radar sensor reading and channel metadata.
final class RadarSensorData {
  RadarSensorData({
    required this.channel,
    this.orientation = 0,
    this.distanceM = double.nan,
    this.signalQuality = 0,
    this.healthy = false,
    this.valid = false,
    this.updated,
    this.minDistanceM = 0.1,
    this.maxDistanceM = 50.0,
    this.angleDeg = 0,
  });

  /// Channel index (0..9).
  final int channel;

  /// Sensor orientation code (matching MAVLink MavSensorOrientation).
  int orientation;

  /// Measured distance in meters.
  double distanceM;

  /// Signal quality percentage (0..100%).
  int signalQuality;

  /// Whether sensor hardware reports healthy operation.
  bool healthy;

  /// Whether current distance measurement is valid.
  bool valid;

  /// Timestamp of the last received measurement.
  DateTime? updated;

  /// Minimum rated distance in meters.
  double minDistanceM;

  /// Maximum rated distance in meters.
  double maxDistanceM;

  /// Sensor azimuth/pointing angle in degrees relative to vehicle body.
  int angleDeg;

  /// Returns true if no update has arrived within [timeout].
  bool isExpired(DateTime now, {Duration timeout = const Duration(milliseconds: 500)}) {
    if (updated == null) return true;
    return now.difference(updated!) > timeout;
  }

  /// Mutates the reading with new measurement data.
  void update({
    required double distance,
    int? quality,
    bool? isValid,
    bool? isHealthy,
    int? newOrientation,
    int? angle,
    double? minM,
    double? maxM,
    DateTime? timestamp,
  }) {
    distanceM = distance;
    if (quality != null) {
      signalQuality = quality.clamp(0, 100);
    }
    if (newOrientation != null) {
      orientation = newOrientation;
    }
    if (angle != null) {
      angleDeg = angle;
    }
    if (minM != null) {
      minDistanceM = minM;
    }
    if (maxM != null) {
      maxDistanceM = maxM;
    }
    valid = isValid ?? (distance.isFinite && distance > 0 && signalQuality > 10);
    healthy = isHealthy ?? true;
    updated = timestamp ?? DateTime.now();
  }

  /// Resets reading to uninitialized state.
  void reset() {
    distanceM = double.nan;
    signalQuality = 0;
    healthy = false;
    valid = false;
    updated = null;
    angleDeg = 0;
  }
}

/// Downward radar terrain follower with tilt compensation and attitude gating.
final class TerrainFollower {
  TerrainFollower({
    this.maxTiltDeg = 35.0,
    this.targetClearanceM = 2.0,
    this.smoothingAlpha = 0.2,
    this.mountingOffsetZ = 0.0,
  });

  /// Maximum allowable tilt angle in degrees before terrain updates are gated.
  double maxTiltDeg;

  /// Desired ground clearance altitude in meters.
  double targetClearanceM;

  /// Low-pass filter smoothing coefficient for ground elevation tracking.
  double smoothingAlpha;

  /// Downward sensor mounting position along body Z axis in meters.
  double mountingOffsetZ;

  /// Estimated ground terrain elevation above MSL in meters.
  double terrainElevationMsl = double.nan;

  /// Most recent raw un-smoothed terrain elevation above MSL in meters.
  double lastRawTerrainMsl = double.nan;

  /// Most recent calculated vertical ground clearance (AGL) in meters.
  double lastGroundClearanceM = double.nan;

  /// Most recent tilt compensation factor (vz = cos(pitch) * cos(roll)).
  double lastVz = 1.0;

  /// Most recent calculated tilt angle in degrees.
  double lastTiltDeg = 0.0;

  /// Whether terrain elevation updates are currently frozen due to excessive tilt.
  bool tiltGated = false;

  /// Whether the ground elevation filter has been initialized with at least one valid sample.
  bool isInitialized = false;

  /// Calculates the vertical directional cosine projection factor:
  /// vz = cos(pitch) * cos(roll).
  static double computeVz(double rollRad, double pitchRad) {
    if (!rollRad.isFinite || !pitchRad.isFinite) {
      return 0.0;
    }
    final vz = math.cos(pitchRad) * math.cos(rollRad);
    return vz.clamp(-1.0, 1.0);
  }

  /// Calculates total attitude tilt angle in degrees from the vz factor.
  static double computeTiltDeg(double vz) {
    if (!vz.isFinite) return 90.0;
    final clamped = vz.clamp(-1.0, 1.0);
    final tiltRad = math.acos(clamped);
    return tiltRad * 180.0 / math.pi;
  }

  /// Calculates vertical ground clearance (AGL) from slant distance and tilt factor.
  double computeAgl(double rawDistanceM, double vz) {
    return rawDistanceM * vz + mountingOffsetZ;
  }

  /// Updates terrain elevation tracking based on aircraft attitude, altitude, and downward distance.
  void updateTerrain({
    required double currentAltMsl,
    required double rollRad,
    required double pitchRad,
    required double rawDistanceM,
    required bool isHealthy,
    double? dt,
  }) {
    if (!isHealthy ||
        !rawDistanceM.isFinite ||
        rawDistanceM <= 0 ||
        !currentAltMsl.isFinite ||
        !rollRad.isFinite ||
        !pitchRad.isFinite) {
      if (!rollRad.isFinite || !pitchRad.isFinite) {
        lastVz = 0.0;
        lastTiltDeg = 90.0;
        tiltGated = true;
      }
      return;
    }

    lastVz = computeVz(rollRad, pitchRad);
    lastTiltDeg = computeTiltDeg(lastVz);

    // Tilt gating: if tilt exceeds threshold, freeze terrain elevation update
    if (lastTiltDeg > maxTiltDeg) {
      tiltGated = true;
      lastGroundClearanceM = computeAgl(rawDistanceM, lastVz);
      return;
    }

    tiltGated = false;
    final hAgl = computeAgl(rawDistanceM, lastVz);
    lastGroundClearanceM = hAgl;
    final rawTerrainMsl = currentAltMsl - hAgl;
    lastRawTerrainMsl = rawTerrainMsl;

    if (!isInitialized) {
      terrainElevationMsl = rawTerrainMsl;
      isInitialized = true;
    } else {
      final alpha = dt != null ? (dt * 5.0).clamp(0.05, 0.40) : smoothingAlpha;
      terrainElevationMsl += alpha * (rawTerrainMsl - terrainElevationMsl);
    }
  }

  /// Calculates the adjusted target altitude MSL for terrain following.
  double adjustAltitude({
    required double currentAltMsl,
    required double rollRad,
    required double pitchRad,
    required double rawDistanceM,
    required bool isHealthy,
    double? dt,
    double? clearanceM,
  }) {
    final tgtClearance = clearanceM ?? targetClearanceM;
    updateTerrain(
      currentAltMsl: currentAltMsl,
      rollRad: rollRad,
      pitchRad: pitchRad,
      rawDistanceM: rawDistanceM,
      isHealthy: isHealthy,
      dt: dt,
    );

    if (!isInitialized) {
      return currentAltMsl;
    }

    return terrainElevationMsl + tgtClearance;
  }

  /// Resets terrain follower internal state.
  void reset() {
    terrainElevationMsl = double.nan;
    lastRawTerrainMsl = double.nan;
    lastGroundClearanceM = double.nan;
    lastVz = 1.0;
    lastTiltDeg = 0.0;
    tiltGated = false;
    isInitialized = false;
  }
}

/// Manages 10 concurrent radar sensor channels and downward terrain following.
final class RadarState {
  RadarState() {
    // Channel 0: Downward (orientation 25 / pitch 270°)
    channels[channelDownward].orientation = MavSensorOrientation.mavSensorRotationPitch270;
    channels[channelDownward].angleDeg = 0;

    // Channels 1..8: 360° horizontal ring at 45° azimuth intervals
    const horizontalOrientations = [
      MavSensorOrientation.mavSensorRotationNone, // 0° Front
      MavSensorOrientation.mavSensorRotationYaw45, // 45° Front-Right
      MavSensorOrientation.mavSensorRotationYaw90, // 90° Right
      MavSensorOrientation.mavSensorRotationYaw135, // 135° Rear-Right
      MavSensorOrientation.mavSensorRotationYaw180, // 180° Rear
      MavSensorOrientation.mavSensorRotationYaw225, // 225° Rear-Left
      MavSensorOrientation.mavSensorRotationYaw270, // 270° Left
      MavSensorOrientation.mavSensorRotationYaw315, // 315° Front-Left
    ];

    for (var i = 0; i < 8; i++) {
      final ch = i + 1;
      channels[ch].orientation = horizontalOrientations[i];
      channels[ch].angleDeg = i * 45;
    }

    // Channel 9: Top (orientation 24 / pitch 90°)
    channels[channelTop].orientation = MavSensorOrientation.mavSensorRotationPitch90;
    channels[channelTop].angleDeg = 0;
  }

  static const int channelDownward = 0;
  static const int channelFront = 1;
  static const int channelFrontRight = 2;
  static const int channelRight = 3;
  static const int channelRearRight = 4;
  static const int channelRear = 5;
  static const int channelRearLeft = 6;
  static const int channelLeft = 7;
  static const int channelFrontLeft = 8;
  static const int channelTop = 9;
  static const int channelCount = 10;

  /// Fixed array of 10 concurrent radar channels.
  final List<RadarSensorData> channels = List.generate(
    channelCount,
    (index) => RadarSensorData(channel: index),
  );

  /// Downward terrain following processor.
  final TerrainFollower terrainFollower = TerrainFollower();

  /// Channel 0: Downward facing radar sensor.
  RadarSensorData get downward => channels[channelDownward];

  /// Channel 1: Front facing radar sensor.
  RadarSensorData get forward => channels[channelFront];

  /// Channel 9: Top / overhead radar sensor.
  RadarSensorData get top => channels[channelTop];

  /// Current vertical ground clearance (AGL) in meters.
  double get downwardTerrainClearanceM => terrainFollower.lastGroundClearanceM;

  /// Current estimated ground terrain elevation MSL in meters.
  double get terrainElevationMsl => terrainFollower.terrainElevationMsl;

  /// Whether terrain follow updates are currently tilt gated.
  bool get tiltGated => terrainFollower.tiltGated;

  /// Whether downward radar terrain following has valid ground lock.
  bool get isTerrainActive => downward.healthy && downward.valid && terrainFollower.isInitialized;

  /// Total count of healthy and valid radar sensors across all 10 channels.
  int get activeSensorCount => channels.where((c) => c.healthy && c.valid).length;

  /// Updates a specific radar channel with new sensor measurements.
  void updateSensor(
    int channel, {
    required double distanceM,
    int? quality,
    bool? valid,
    bool? healthy,
    int? orientation,
    int? angleDeg,
    DateTime? timestamp,
  }) {
    if (channel < 0 || channel >= channelCount) return;
    channels[channel].update(
      distance: distanceM,
      quality: quality,
      isValid: valid,
      isHealthy: healthy,
      newOrientation: orientation,
      angle: angleDeg,
      timestamp: timestamp,
    );
  }

  /// Recalculates downward terrain following using current aircraft state.
  void updateDownwardTerrainFollow({
    required double currentAltMsl,
    required double rollRad,
    required double pitchRad,
    double? dt,
  }) {
    final down = channels[channelDownward];
    terrainFollower.updateTerrain(
      currentAltMsl: currentAltMsl,
      rollRad: rollRad,
      pitchRad: pitchRad,
      rawDistanceM: down.distanceM,
      isHealthy: down.healthy && down.valid,
      dt: dt,
    );
  }

  /// Ingests a MAVLink DistanceSensor message into the appropriate radar channel.
  void updateFromDistanceSensor(
    DistanceSensor m, {
    double? rollRad,
    double? pitchRad,
    double? altMsl,
    DateTime? now,
  }) {
    int targetChannel = m.instanceId;

    // Resolve channel assignment based on orientation or instanceId
    if (m.orientation == MavSensorOrientation.mavSensorRotationPitch270) {
      targetChannel = channelDownward;
    } else if (m.orientation == MavSensorOrientation.mavSensorRotationPitch90) {
      targetChannel = channelTop;
    } else if (targetChannel >= channelCount && m.orientation <= MavSensorOrientation.mavSensorRotationYaw315) {
      targetChannel = m.orientation + 1;
    }

    if (targetChannel >= 0 && targetChannel < channelCount) {
      final distM = m.currentDistance * 0.01;
      final minM = m.minDistance * 0.01;
      final maxM = m.maxDistance * 0.01;
      final isValid = m.currentDistance >= m.minDistance &&
          m.currentDistance <= m.maxDistance &&
          (m.signalQuality == 0 || m.signalQuality > 10);

      channels[targetChannel].update(
        distance: distM,
        quality: m.signalQuality,
        isValid: isValid,
        isHealthy: true,
        newOrientation: m.orientation,
        minM: minM,
        maxM: maxM,
        timestamp: now,
      );

      // If downward channel was updated and vehicle telemetry is available, update terrain
      if (targetChannel == channelDownward &&
          rollRad != null &&
          pitchRad != null &&
          altMsl != null &&
          altMsl.isFinite) {
        terrainFollower.updateTerrain(
          currentAltMsl: altMsl,
          rollRad: rollRad,
          pitchRad: pitchRad,
          rawDistanceM: distM,
          isHealthy: isValid,
        );
      }
    }
  }

  /// Resets all channels and terrain follower state.
  void reset() {
    for (final ch in channels) {
      ch.reset();
    }
    terrainFollower.reset();
  }
}
