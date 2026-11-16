// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'connection.dart';

/// Persistent flight snail-trail that records vehicle coordinates continuously,
/// even when the Fly tab is not active, when the window loses focus, or when
/// the app is in the background.
final class FlightTrailState {
  const FlightTrailState({required this.points, required this.revision});

  final List<LatLng> points;
  final int revision;

  FlightTrailState copyWith({List<LatLng>? points, int? revision}) =>
      FlightTrailState(points: points ?? this.points, revision: revision ?? this.revision);
}

final class FlightTrailController extends Notifier<FlightTrailState> {
  Timer? _sampleTimer;
  static const int _maxPoints = 5000;
  static const _distanceCalc = Distance();
  bool _wasArmed = false;
  bool _wasAirborne = false;

  @override
  FlightTrailState build() {
    // When connection changes, listen and reset or continue.
    ref.listen<Connection?>(connectionProvider, (prev, next) {
      if (next == null) {
        _sampleTimer?.cancel();
        _sampleTimer = null;
        _wasArmed = false;
        _wasAirborne = false;
      } else {
        _startSampling(next.session);
      }
    });

    final current = ref.read(connectionProvider);
    if (current != null) {
      _startSampling(current.session);
    }

    ref.onDispose(() {
      _sampleTimer?.cancel();
    });

    return const FlightTrailState(points: [], revision: 0);
  }

  void _startSampling(VehicleSession session) {
    _sampleTimer?.cancel();
    _wasArmed = session.telemetry.snapshot.armed;
    _wasAirborne = (session.telemetry.snapshot.altRel > 1.0);

    // Sample position at 10 Hz (matching APX GLOBAL_POSITION_INT stream rate)
    _sampleTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final snap = session.telemetry.snapshot;
      final armed = snap.armed;
      final airborne = armed && (!snap.altRel.isNaN && snap.altRel >= 0.8);

      // Detect new takeoff:
      // 1) Transition from disarmed to armed (pre-takeoff arm)
      // 2) Transition from ground to airborne (liftoff)
      if (armed && !_wasArmed) {
        clear();
      } else if (airborne && !_wasAirborne && state.points.length > 5) {
        // If there was pre-takeoff ground roll/jitter, fresh takeoff resets trail
        clear();
      }

      _wasArmed = armed;
      _wasAirborne = airborne;

      if (!snap.hasPosition || snap.lat.isNaN || snap.lon.isNaN) return;

      // Only record the snail trail while armed / airborne (retains existing points after landing)
      if (!armed && !airborne) return;

      final here = LatLng(snap.lat, snap.lon);
      final pts = state.points;

      if (pts.isEmpty || _distanceCalc.as(LengthUnit.Meter, pts.last, here) >= 1.0) {
        final nextPts = List<LatLng>.from(pts)..add(here);
        if (nextPts.length > _maxPoints) {
          nextPts.removeRange(0, nextPts.length - _maxPoints);
        }
        state = FlightTrailState(points: nextPts, revision: state.revision + 1);
      }
    });
  }

  void clear() {
    state = const FlightTrailState(points: [], revision: 0);
  }

  /// Explicitly sets points for testing or external track replay.
  @visibleForTesting
  void setPoints(List<LatLng> points) {
    state = FlightTrailState(points: List.unmodifiable(points), revision: state.revision + 1);
  }
}

final flightTrailProvider = NotifierProvider<FlightTrailController, FlightTrailState>(FlightTrailController.new);
