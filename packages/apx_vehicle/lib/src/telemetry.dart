// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:math' as math;

import 'package:apx_mavlink/apx_mavlink.dart';

import 'radar.dart';

final class GpsState {
  int fixType = GpsFixType.noGps;
  int satellites = 0;
  double hdop = double.nan; // from eph/100
  double vdop = double.nan;
  double lat = double.nan;
  double lon = double.nan;
  double altMsl = double.nan;
  double groundSpeed = double.nan;
  DateTime? updated;

  bool get has3dFix => fixType >= GpsFixType.v3dFix;
}

/// One redundant sensor lane from HIGHRES_IMU (id = lane).
final class ImuLane {
  ImuLane(this.lane);
  final int lane;
  double accX = 0, accY = 0, accZ = 0;
  double gyroX = 0, gyroY = 0, gyroZ = 0;
  double magX = 0, magY = 0, magZ = 0;
  double pressureHpa = 0, pressureAlt = 0, temperature = 0;
  DateTime? updated;
}

final class StatusMessage {
  StatusMessage(this.severity, this.text, this.time);
  final int severity; // MAV_SEVERITY
  final String text;
  final DateTime time;
}

/// Latest known vehicle state. Mutated by [TelemetryStore]; consumers read it.
final class VehicleSnapshot {
  // Identity / state
  int vehicleType = 0;
  int autopilot = 0;
  int baseMode = 0;
  int customMode = 0;
  int systemStatus = 0;
  bool get armed => (baseMode & MavModeFlag.safetyArmed) != 0;

  // Attitude (radians, rad/s)
  double roll = 0, pitch = 0, yaw = 0;
  double rollRate = 0, pitchRate = 0, yawRate = 0;
  int timeBootMs = 0;

  // Position
  double lat = double.nan, lon = double.nan;
  double altMsl = double.nan, altRel = double.nan;
  double vn = 0, ve = 0, vd = 0;
  double headingDeg = double.nan;
  bool hasPosition = false;

  // VFR_HUD
  double groundSpeed = 0, airSpeed = 0, climbRate = 0;

  // Power
  double batteryVoltage = double.nan;
  double batteryCurrent = double.nan;
  int batteryRemaining = -1;

  // Environment
  double windFromDeg = double.nan, windSpeed = double.nan, windVertical = double.nan;

  // Sensors
  final gps = [GpsState(), GpsState()];
  final imu = [for (var i = 0; i < 4; i++) ImuLane(i)];
  final radar = RadarState();
  int sensorsPresent = 0, sensorsEnabled = 0, sensorsHealthy = 0;

  // Outputs and RC (RC on APX echoes GCS overrides)
  List<int> servo = List.filled(16, 0);
  List<int> rc = List.filled(18, 0);
  int rcRssi = 255;

  // Mission progress (AUTO only)
  int missionCurrent = -1;
  int missionTotal = 0;
  int lastReached = -1;

  // Geofence (FENCE_STATUS). Null until the vehicle has reported one.
  bool? fenceBreached;
  int fenceBreachCount = 0;

  /// FENCE_BREACH: 0 none, 1 min alt, 2 max alt, 3 boundary. APX sends its
  /// own codes here (1 altitude, 4 polygon); see [fenceBreachLabel].
  int fenceBreachType = 0;

  /// What the vehicle reported for a breach, or null when not breached.
  String? get fenceBreachLabel => fenceBreached != true
      ? null
      : switch (fenceBreachType) {
          1 || 2 => 'altitude limit',
          3 || 4 => 'boundary',
          _ => 'fence',
        };

  // Home (estimated on APX 0.1).
  double homeLat = double.nan, homeLon = double.nan, homeAltMsl = double.nan;

  DateTime? lastHeartbeat;

  /// Increments on every applied message; UI polls this at frame rate.
  int revision = 0;
}

/// Folds incoming messages into a [VehicleSnapshot].
final class TelemetryStore {
  final VehicleSnapshot snapshot = VehicleSnapshot();
  final _status = StreamController<StatusMessage>.broadcast();
  final _reboot = StreamController<void>.broadcast();
  final _armChanges = StreamController<bool>.broadcast();

  /// STATUSTEXT from the vehicle.
  Stream<StatusMessage> get statusMessages => _status.stream;

  /// The vehicle restarted (boot time went backwards).
  Stream<void> get reboots => _reboot.stream;

  Stream<bool> get armChanges => _armChanges.stream;

  bool _wasArmed = false;
  bool _hasReportedHome = false;

  void apply(MavMessage m, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final s = snapshot;
    switch (m) {
      case Heartbeat():
        s.vehicleType = m.type;
        s.autopilot = m.autopilot;
        s.baseMode = m.baseMode;
        s.customMode = m.customMode;
        s.systemStatus = m.systemStatus;
        s.lastHeartbeat = t;
        if (s.armed != _wasArmed) {
          _wasArmed = s.armed;
          // Capture home on arming (takeoff spot) and on landing if vehicle doesn't stream HomePosition
          if (!_hasReportedHome) {
            _captureHome();
          }
          _armChanges.add(s.armed);
        }
      case Attitude():
        if (m.timeBootMs + 5000 < s.timeBootMs) _reboot.add(null);
        s.timeBootMs = m.timeBootMs;
        s.roll = m.roll;
        s.pitch = m.pitch;
        s.yaw = m.yaw;
        s.rollRate = m.rollspeed;
        s.pitchRate = m.pitchspeed;
        s.yawRate = m.yawspeed;
        s.radar.updateDownwardTerrainFollow(
          currentAltMsl: s.altMsl,
          rollRad: s.roll,
          pitchRad: s.pitch,
        );
      case GlobalPositionInt():
        s.lat = m.lat / 1e7;
        s.lon = m.lon / 1e7;
        s.altMsl = m.alt / 1000;
        s.altRel = m.relativeAlt / 1000;
        s.vn = m.vx / 100;
        s.ve = m.vy / 100;
        s.vd = m.vz / 100;
        s.headingDeg = m.hdg == 0xFFFF ? double.nan : m.hdg / 100;
        s.hasPosition = true;
        s.radar.updateDownwardTerrainFollow(
          currentAltMsl: s.altMsl,
          rollRad: s.roll,
          pitchRad: s.pitch,
        );
        _estimateHome();
      case VfrHud():
        s.groundSpeed = m.groundspeed;
        s.airSpeed = m.airspeed;
        s.climbRate = m.climb;
      case SysStatus():
        s.sensorsPresent = m.onboardControlSensorsPresent;
        s.sensorsEnabled = m.onboardControlSensorsEnabled;
        s.sensorsHealthy = m.onboardControlSensorsHealth;
        _battery(m.voltageBattery, m.currentBattery, m.batteryRemaining);
      case BatteryStatus():
        final v = m.voltages.isNotEmpty ? m.voltages.first : 0xFFFF;
        _battery(v, m.currentBattery, m.batteryRemaining);
      case GpsRawInt():
        _gps(s.gps[0], m.fixType, m.satellitesVisible, m.eph, m.epv, m.lat, m.lon, m.alt, m.vel, t);
      case Gps2Raw():
        _gps(s.gps[1], m.fixType, m.satellitesVisible, m.eph, m.epv, m.lat, m.lon, m.alt, m.vel, t);
      case HighresImu():
        if (m.instanceId < s.imu.length) {
          s.imu[m.instanceId]
            ..accX = m.xacc
            ..accY = m.yacc
            ..accZ = m.zacc
            ..gyroX = m.xgyro
            ..gyroY = m.ygyro
            ..gyroZ = m.zgyro
            ..magX = m.xmag
            ..magY = m.ymag
            ..magZ = m.zmag
            ..pressureHpa = m.absPressure
            ..pressureAlt = m.pressureAlt
            ..temperature = m.temperature
            ..updated = t;
        }
      case Wind():
        s.windFromDeg = m.direction;
        s.windSpeed = m.speed;
        s.windVertical = m.speedZ;
      case ServoOutputRaw():
        s.servo = [
          m.servo1Raw,
          m.servo2Raw,
          m.servo3Raw,
          m.servo4Raw,
          m.servo5Raw,
          m.servo6Raw,
          m.servo7Raw,
          m.servo8Raw,
          m.servo9Raw,
          m.servo10Raw,
          m.servo11Raw,
          m.servo12Raw,
          m.servo13Raw,
          m.servo14Raw,
          m.servo15Raw,
          m.servo16Raw,
        ];
      case RcChannels():
        s.rc = [
          m.chan1Raw,
          m.chan2Raw,
          m.chan3Raw,
          m.chan4Raw,
          m.chan5Raw,
          m.chan6Raw,
          m.chan7Raw,
          m.chan8Raw,
          m.chan9Raw,
          m.chan10Raw,
          m.chan11Raw,
          m.chan12Raw,
          m.chan13Raw,
          m.chan14Raw,
          m.chan15Raw,
          m.chan16Raw,
          m.chan17Raw,
          m.chan18Raw,
        ];
        s.rcRssi = m.rssi;
      case MissionCurrent():
        s.missionCurrent = m.seq;
        s.missionTotal = m.total;
      case MissionItemReached():
        s.lastReached = m.seq;
      case FenceStatus():
        s.fenceBreached = m.breachStatus != 0;
        s.fenceBreachCount = m.breachCount;
        s.fenceBreachType = m.breachType;
      case HomePosition():
        s.homeLat = m.latitude / 1e7;
        s.homeLon = m.longitude / 1e7;
        s.homeAltMsl = m.altitude / 1000.0;
        _hasReportedHome = true;
      case DistanceSensor():
        s.radar.updateFromDistanceSensor(
          m,
          rollRad: s.roll,
          pitchRad: s.pitch,
          altMsl: s.altMsl,
          now: t,
        );
      case Statustext():
        _status.add(StatusMessage(m.severity, m.text, t));
      default:
        return;
    }
    s.revision++;
  }

  void _battery(int mv, int ca, int remaining) {
    final s = snapshot;
    s.batteryVoltage = mv == 0xFFFF ? double.nan : mv / 1000;
    s.batteryCurrent = ca < 0 ? double.nan : ca / 100;
    s.batteryRemaining = remaining;
  }

  void _gps(GpsState g, int fix, int sats, int eph, int epv, int lat, int lon, int alt, int vel, DateTime t) {
    g
      ..fixType = fix
      ..satellites = sats == 255 ? 0 : sats
      ..hdop = eph == 0xFFFF ? double.nan : eph / 100
      ..vdop = epv == 0xFFFF ? double.nan : epv / 100
      ..lat = lat / 1e7
      ..lon = lon / 1e7
      ..altMsl = alt / 1000
      ..groundSpeed = vel == 0xFFFF ? double.nan : vel / 100
      ..updated = t;
    if (fix >= 3) {
      final s = snapshot;
      if (s.lat.isNaN || !s.hasPosition) {
        s.lat = g.lat;
        s.lon = g.lon;
        if (s.altMsl.isNaN) s.altMsl = g.altMsl;
        s.hasPosition = true;
      }
      _estimateHome();
    }
  }

  // Home altitude is exact (AMSL − relative). Horizontal home is automatically
  // set to the vehicle's position when it arms, or when on the ground / landed.
  void _estimateHome() {
    final s = snapshot;
    if (!s.altMsl.isNaN && !s.altRel.isNaN) s.homeAltMsl = s.altMsl - s.altRel;
    // Only capture home from GPS if vehicle does not stream HomePosition and home is not yet initialized
    if (!_hasReportedHome && s.homeLat.isNaN) {
      _captureHome();
    }
  }

  void _captureHome() {
    final s = snapshot;
    if (!s.hasPosition) return;
    s.homeLat = s.lat;
    s.homeLon = s.lon;
    if (!s.altMsl.isNaN) {
      s.homeAltMsl = !s.altRel.isNaN ? (s.altMsl - s.altRel) : s.altMsl;
    }
  }

  /// Manually updates or overrides the home position in telemetry state (e.g. from GCS in-flight command).
  void setManualHome({required double lat, required double lon, double? altMsl}) {
    final s = snapshot;
    s.homeLat = lat;
    s.homeLon = lon;
    if (altMsl != null && !altMsl.isNaN) {
      s.homeAltMsl = altMsl;
    }
    _hasReportedHome = true;
  }

  Future<void> dispose() async {
    await _status.close();
    await _reboot.close();
    await _armChanges.close();
  }
}

/// Distance in metres between two WGS‑84 points (haversine, mean radius).
double distanceMetres(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371008.8;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = p2 - p1, dl = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
