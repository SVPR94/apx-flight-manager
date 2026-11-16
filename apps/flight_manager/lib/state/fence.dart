// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'connection.dart';
import 'storage.dart';

/// State of the safety geofence in FlyView.
final class FenceState {
  const FenceState({
    this.points = const [],
    this.enabled = false,
    this.isDrawing = false,
    this.altMax = 50.0,
    this.action = 1, // 0=Report only, 1=RTL, 2=Land, 4=Brake
    this.margin = 2.0,
    this.isUploading = false,
    this.isMoving = false,
  });

  /// Polygon vertices in order around the perimeter.
  final List<LatLng> points;

  /// Whether the safety geofence is armed/enabled.
  final bool enabled;

  /// Whether the pilot is actively placing/editing vertices on the map.
  final bool isDrawing;

  /// Whether the pilot is moving/dragging the entire fence.
  final bool isMoving;

  /// Maximum ceiling altitude above takeoff in meters (0 = no height restriction).
  final double altMax;

  /// Action upon breach: 0=Report, 1=RTL, 2=Land, 4=Brake.
  final int action;

  /// Safety margin before boundary in meters.
  final double margin;

  /// Whether an upload transaction is active.
  final bool isUploading;

  bool get hasValidPolygon => points.length >= 3;

  /// Geometric center (centroid) of the fence polygon.
  LatLng? get center {
    if (points.isEmpty) return null;
    double lat = 0;
    double lon = 0;
    for (final p in points) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / points.length, lon / points.length);
  }

  String get actionName => switch (action) {
    0 => 'Report Only',
    2 => 'Land',
    4 => 'Brake / Hold',
    _ => 'Return to Launch (RTL)',
  };

  FenceState copyWith({
    List<LatLng>? points,
    bool? enabled,
    bool? isDrawing,
    bool? isMoving,
    double? altMax,
    int? action,
    double? margin,
    bool? isUploading,
  }) => FenceState(
    points: points ?? this.points,
    enabled: enabled ?? this.enabled,
    isDrawing: isDrawing ?? this.isDrawing,
    isMoving: isMoving ?? this.isMoving,
    altMax: altMax ?? this.altMax,
    action: action ?? this.action,
    margin: margin ?? this.margin,
    isUploading: isUploading ?? this.isUploading,
  );
}

final class FenceController extends Notifier<FenceState> {
  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  FenceState build() {
    final rawPts = _store.get<List>('fencePoints');
    final points = <LatLng>[];
    if (rawPts != null) {
      for (final p in rawPts) {
        if (p is Map) {
          final lat = (p['lat'] as num?)?.toDouble();
          final lon = (p['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) {
            points.add(LatLng(lat, lon));
          }
        }
      }
    }

    final altMax = (_store.get<num>('fenceAltMax'))?.toDouble() ?? 50.0;
    final action = _store.get<num>('fenceAction')?.toInt() ?? 1;
    final enabled = _store.get<bool>('fenceEnabled') ?? false;

    // Follow the vehicle's FENCE_* parameters. The session only has
    // parameters once it has bound to a vehicle, which happens after
    // connectionProvider changes, so wait for that before subscribing.
    ref.listen(connectionProvider, (_, next) => _follow(next?.session));
    ref.onDispose(_unfollow);
    final initial = ref.read(connectionProvider)?.session;
    if (initial != null) Future.microtask(() => _follow(initial));

    return FenceState(points: points, enabled: enabled, altMax: altMax, action: action);
  }

  final _subs = <StreamSubscription<Object?>>[];
  VehicleSession? _followed;

  void _unfollow() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _followed = null;
  }

  void _follow(VehicleSession? session) {
    if (identical(session, _followed)) return;
    _unfollow();
    if (session == null) return;
    _followed = session;
    var bound = false;
    void bind() {
      if (bound || !session.isBound) return;
      bound = true;
      _subs.add(session.parameters.changes.where((p) => p.name.startsWith('FENCE_')).listen((_) => _pull(session)));
      _pull(session);
    }

    _subs.add(session.state.changes.listen((_) => bind()));
    bind();
  }

  /// Takes the vehicle's FENCE_* values; the vehicle is the authority.
  void _pull(VehicleSession session) {
    final p = session.parameters;
    final vEnable = p['FENCE_ENABLE']?.value;
    final vAlt = p['FENCE_ALT_MAX']?.value;
    final vAct = p['FENCE_ACTION']?.value;
    final vMargin = p['FENCE_MARGIN']?.value;
    if (vEnable == null && vAlt == null && vAct == null && vMargin == null) return;
    state = state.copyWith(
      enabled: vEnable != null ? vEnable >= 0.5 : null,
      altMax: vAlt,
      action: vAct?.round(),
      margin: vMargin,
    );
  }

  void _persist() {
    _store.set('fencePoints', [
      for (final p in state.points) {'lat': p.latitude, 'lon': p.longitude},
    ]);
    _store.set('fenceAltMax', state.altMax);
    _store.set('fenceAction', state.action);
    _store.set('fenceEnabled', state.enabled);
  }

  void toggleDrawing() {
    state = state.copyWith(isDrawing: !state.isDrawing, isMoving: false);
  }

  void startDrawing() {
    state = state.copyWith(isDrawing: true, isMoving: false);
  }

  void finishDrawing() {
    state = state.copyWith(isDrawing: false);
    _persist();
  }

  void toggleMoving() {
    state = state.copyWith(isMoving: !state.isMoving, isDrawing: false);
  }

  void startMoving() {
    state = state.copyWith(isMoving: true, isDrawing: false);
  }

  void finishMoving() {
    state = state.copyWith(isMoving: false);
    _persist();
  }

  void translate(double deltaLat, double deltaLon) {
    if (state.points.isEmpty) return;
    final updated = [
      for (final p in state.points) LatLng(p.latitude + deltaLat, p.longitude + deltaLon),
    ];
    state = state.copyWith(points: updated);
    _persist();
  }

  void moveTo(LatLng target) {
    final c = state.center;
    if (c == null) return;
    final dLat = target.latitude - c.latitude;
    final dLon = target.longitude - c.longitude;
    translate(dLat, dLon);
  }

  void addPoint(LatLng pt) {
    state = state.copyWith(points: [...state.points, pt]);
    _persist();
  }

  void updatePoint(int index, LatLng pt) {
    if (index < 0 || index >= state.points.length) return;
    final updated = List<LatLng>.from(state.points);
    updated[index] = pt;
    state = state.copyWith(points: updated);
    _persist();
  }

  void removePoint(int index) {
    if (index < 0 || index >= state.points.length) return;
    final updated = List<LatLng>.from(state.points)..removeAt(index);
    state = state.copyWith(points: updated);
    _persist();
  }

  void undoPoint() {
    if (state.points.isEmpty) return;
    final updated = List<LatLng>.from(state.points)..removeLast();
    state = state.copyWith(points: updated);
    _persist();
  }

  void clearPoints() {
    state = state.copyWith(points: const [], isDrawing: false);
    _persist();
  }

  Future<void> toggleEnabled(VehicleSession? session, bool enable) async {
    state = state.copyWith(enabled: enable);
    _persist();
    if (session != null && session.isBound) {
      try {
        await session.parameters.set('FENCE_ENABLE', enable ? 1.0 : 0.0);
      } catch (_) {}
    }
  }

  Future<void> setAltMax(VehicleSession? session, double alt) async {
    state = state.copyWith(altMax: alt);
    _persist();
    if (session != null && session.isBound) {
      try {
        await session.parameters.set('FENCE_ALT_MAX', alt);
      } catch (_) {}
    }
  }

  Future<void> setAction(VehicleSession? session, int action) async {
    state = state.copyWith(action: action);
    _persist();
    if (session != null && session.isBound) {
      try {
        await session.parameters.set('FENCE_ACTION', action.toDouble());
      } catch (_) {}
    }
  }

  /// Writes the FENCE_* parameters and the polygon to the vehicle. An
  /// incomplete polygon (< 3 vertices) clears the vehicle's polygon.
  /// Returns null on success, otherwise what went wrong.
  Future<String?> uploadToVehicle(VehicleSession session) async {
    // TODO(APX-FW-1): APX builds without a fence ignore mission_type and
    // would store the vertices as the mission. FENCE_ENABLE marks firmware
    // that handles fence uploads.
    if (session.parameters['FENCE_ENABLE'] == null) return 'This firmware has no geofence support';
    // What to send: each echoed FENCE_* value updates [state] (see _pull)
    // while the upload is still running.
    final want = state;
    state = state.copyWith(isUploading: true);
    try {
      Future<void> put(String name, double value) async {
        final r = await session.parameters.set(name, value);
        if (r.outcome == ParamSetOutcome.noReply) throw TransferException('$name: no reply from the vehicle');
      }

      // Polygon first, so the fence is never enabled around a stale one.
      final items = <WireMissionItem>[
        if (want.hasValidPolygon)
          for (final (i, p) in want.points.indexed)
            WireMissionItem(
              seq: i,
              command: MavCmd.navFencePolygonVertexInclusion,
              x: (p.latitude * 1e7).round(),
              y: (p.longitude * 1e7).round(),
              param1: want.points.length.toDouble(),
            ),
      ];
      await session.missions.upload(items, missionType: MavMissionType.fence);

      await put('FENCE_TYPE', 5.0); // 1 (Alt) + 4 (Polygon)
      await put('FENCE_ALT_MAX', want.altMax);
      await put('FENCE_ACTION', want.action.toDouble());
      await put('FENCE_MARGIN', want.margin);
      await put('FENCE_ENABLE', want.enabled ? 1.0 : 0.0);
      _persist();
      return null;
    } catch (e) {
      return e is TransferException ? e.message : '$e';
    } finally {
      state = state.copyWith(isUploading: false);
    }
  }
}

final fenceProvider = NotifierProvider<FenceController, FenceState>(FenceController.new);

/// The active breach the vehicle reports (FENCE_STATUS), e.g. 'boundary',
/// or null. Compared by value, so watchers rebuild only when it changes.
final fenceBreachProvider = Provider<String?>((ref) {
  final session = ref.watch(connectionProvider)?.session;
  if (session == null) return null;
  ref.watch(frameTickProvider);
  return session.telemetry.snapshot.fenceBreachLabel;
});
