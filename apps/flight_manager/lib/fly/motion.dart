// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:math' as math;

import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Telemetry made smooth for display.
///
/// APX sends attitude at 20 Hz and position at 10 Hz. Drawn as they arrive,
/// the horizon, compass and vehicle marker step; drawn on a fixed UI tick
/// they also beat against it. Here each value is predicted forward from its
/// last sample (attitude by its rates, position by its velocity, for at most
/// one sample interval) and eased towards that prediction on every screen
/// frame, so motion is continuous with very little lag.
///
/// Frames cost: each one redraws the glass panels. So the per-frame ticker
/// only runs while something is visibly catching up; a cheap 25 ms check
/// wakes it when a sample differs visibly from what is shown (0.1°, 5 cm,
/// 0.05 m or m/s on the readouts), and it stops once everything has
/// settled. Sensor noise on a vehicle at rest therefore draws nothing.
class FlightMotion extends ChangeNotifier {
  FlightMotion(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  Timer? _watch;
  VehicleSession? _session;

  // Smoothed outputs. Angles in degrees; heading 0–360.
  double roll = 0, pitch = 0, heading = 0;
  double lat = double.nan, lon = double.nan;
  double altRel = double.nan, groundSpeed = 0, climbRate = 0;
  double windFromDeg = double.nan, windSpeed = 0;

  bool get hasPosition => !lat.isNaN;

  /// Whether frames are being drawn for motion right now.
  bool get animating => _ticker.isActive;

  // Last samples and when they arrived (seconds on the motion clock).
  int _attBoot = -1;
  double _attAt = 0, _sRoll = 0, _sPitch = 0, _sYaw = 0, _rRoll = 0, _rPitch = 0, _rYaw = 0;
  double _posAt = 0, _sLat = double.nan, _sLon = double.nan, _vn = 0, _ve = 0;
  bool _fresh = true;

  // Motion clock: ticker time, continued across stops.
  double _clockBase = 0, _now = 0;
  Duration _last = Duration.zero;
  int _settledFrames = 0;

  // Thresholds below which a change can't be seen.
  static const _degEps = 0.1, _metreEps = 0.05, _valueEps = 0.05;
  static const _attitudeTau = 0.045, _positionTau = 0.08, _valueTau = 0.12;
  static const _maxPredict = 0.12; // s: a little over one sample interval

  /// Follows [session] (null stops everything and clears the state).
  void attach(VehicleSession? session) {
    if (identical(session, _session)) return;
    _session = session;
    _fresh = true;
    _attBoot = -1;
    lat = lon = _sLat = _sLon = altRel = windFromDeg = double.nan;
    windSpeed = 0;
    _watch?.cancel();
    _watch = null;
    if (_ticker.isActive) _ticker.stop();
    if (session != null) {
      _watch = Timer.periodic(const Duration(milliseconds: 25), (_) => _check());
      _start();
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _start() {
    if (_ticker.isActive || _session == null) return;
    _clockBase = _now;
    _last = Duration.zero;
    _settledFrames = 0;
    _ticker.start();
  }

  /// Between frames: wake the ticker if the newest samples would show.
  void _check() {
    final s = _session?.telemetry.snapshot;
    if (s == null || _ticker.isActive) return;
    const deg = 180 / math.pi;
    final turning = math.max(s.rollRate.abs(), math.max(s.pitchRate.abs(), s.yawRate.abs())) * deg;
    final wake =
        (s.timeBootMs != _attBoot &&
            ((s.roll * deg - roll).abs() >= _degEps ||
                (s.pitch * deg - pitch).abs() >= _degEps ||
                _turn(heading, s.yaw * deg).abs() >= _degEps ||
                turning * _maxPredict >= _degEps)) ||
        (s.hasPosition &&
            (s.lat != _sLat || s.lon != _sLon) &&
            (lat.isNaN ||
                _metres(s.lat - lat, s.lon - lon, s.lat) >= _metreEps ||
                math.sqrt(s.vn * s.vn + s.ve * s.ve) * _maxPredict >= _metreEps)) ||
        _differs(s.altRel, altRel, _valueEps) ||
        _differs(s.groundSpeed, groundSpeed, _valueEps) ||
        _differs(s.climbRate, climbRate, _valueEps) ||
        (!s.windSpeed.isNaN && _differs(s.windSpeed, windSpeed, 0.1)) ||
        (!s.windFromDeg.isNaN && (windFromDeg.isNaN || _turn(windFromDeg, s.windFromDeg).abs() >= 1.0));
    if (wake) _start();
  }

  void _tick(Duration elapsed) {
    final s = _session?.telemetry.snapshot;
    if (s == null) return;
    _now = _clockBase + elapsed.inMicroseconds / 1e6;
    final now = _now;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    double ease(double tau) => _fresh ? 1 : 1 - math.exp(-dt / tau);
    double step(double from, double to, double tau) => from.isNaN || to.isNaN ? to : from + (to - from) * ease(tau);
    final before = (roll, pitch, heading, lat, lon, altRel, groundSpeed, climbRate, windFromDeg, windSpeed);

    // Attitude: a new sample is recognised by its boot time.
    if (s.timeBootMs != _attBoot) {
      _attBoot = s.timeBootMs;
      _attAt = now;
      _sRoll = s.roll * 180 / math.pi;
      _sPitch = s.pitch * 180 / math.pi;
      _sYaw = s.yaw * 180 / math.pi;
      _rRoll = s.rollRate * 180 / math.pi;
      _rPitch = s.pitchRate * 180 / math.pi;
      _rYaw = s.yawRate * 180 / math.pi;
    }
    final ta = math.min(now - _attAt, _maxPredict);
    final tRoll = _sRoll + _rRoll * ta, tPitch = _sPitch + _rPitch * ta;
    final tHeading = (_sYaw + _rYaw * ta) % 360;
    roll = step(roll, tRoll, _attitudeTau);
    pitch = step(pitch, tPitch, _attitudeTau);
    // Heading eases the short way round.
    heading = (heading + _turn(heading, tHeading) * ease(_attitudeTau)) % 360;

    // Position: dead-reckoned from the last fix by its velocity.
    if (s.hasPosition && (s.lat != _sLat || s.lon != _sLon)) {
      _sLat = s.lat;
      _sLon = s.lon;
      _vn = s.vn;
      _ve = s.ve;
      _posAt = now;
    }
    var tLat = double.nan, tLon = double.nan;
    if (!_sLat.isNaN) {
      final tp = math.min(now - _posAt, _maxPredict);
      const mPerDeg = 111320.0;
      tLat = _sLat + _vn * tp / mPerDeg;
      tLon = _sLon + _ve * tp / (mPerDeg * math.cos(_sLat * math.pi / 180));
      // A jump of more than ~200 m (new vehicle, GPS reset) snaps.
      final far = lat.isNaN || (tLat - lat).abs() > 0.002 || (tLon - lon).abs() > 0.002;
      lat = far ? tLat : step(lat, tLat, _positionTau);
      lon = far ? tLon : step(lon, tLon, _positionTau);
    }

    altRel = step(altRel, s.altRel, _valueTau);
    groundSpeed = step(groundSpeed, s.groundSpeed, _valueTau);
    climbRate = step(climbRate, s.climbRate, _valueTau);

    // Wind direction eases the short way round continuously matching attitude/heading.
    if (!s.windFromDeg.isNaN) {
      if (windFromDeg.isNaN) {
        windFromDeg = s.windFromDeg % 360;
      } else {
        final diff = _turn(windFromDeg, s.windFromDeg);
        windFromDeg = (windFromDeg + diff * ease(_valueTau)) % 360;
        if (windFromDeg < 0) windFromDeg += 360;
      }
    } else {
      windFromDeg = double.nan;
    }
    windSpeed = s.windSpeed.isNaN ? 0.0 : step(windSpeed, s.windSpeed, _valueTau);

    if (_fresh && _attBoot >= 0) _fresh = false;

    if (before != (roll, pitch, heading, lat, lon, altRel, groundSpeed, climbRate, windFromDeg, windSpeed)) {
      notifyListeners();
    }

    // Settled: everything within half a visible step of where it's heading,
    // and nothing still being predicted forward. Stop drawing frames.
    final settled =
        (tRoll - roll).abs() < _degEps / 2 &&
        (tPitch - pitch).abs() < _degEps / 2 &&
        _turn(heading, tHeading).abs() < _degEps / 2 &&
        (tLat.isNaN || _metres(tLat - lat, tLon - lon, tLat) < _metreEps / 2) &&
        !_differs(s.altRel, altRel, _valueEps / 2) &&
        !_differs(s.groundSpeed, groundSpeed, _valueEps / 2) &&
        !_differs(s.climbRate, climbRate, _valueEps / 2) &&
        math.max(_rRoll.abs(), math.max(_rPitch.abs(), _rYaw.abs())) * _maxPredict < _degEps &&
        math.sqrt(_vn * _vn + _ve * _ve) * _maxPredict < _metreEps;
    _settledFrames = settled ? _settledFrames + 1 : 0;
    if (_settledFrames >= 3) _ticker.stop();
  }

  static double _turn(double from, double to) => ((to - from + 540) % 360) - 180;

  static bool _differs(double a, double b, double eps) => a.isNaN != b.isNaN || (!a.isNaN && (a - b).abs() >= eps);

  static double _metres(double dLat, double dLon, double atLat) {
    const mPerDeg = 111320.0;
    final x = dLon * mPerDeg * math.cos(atLat * math.pi / 180), y = dLat * mPerDeg;
    return math.sqrt(x * x + y * y);
  }
}
