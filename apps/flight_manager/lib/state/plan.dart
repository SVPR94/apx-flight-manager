// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';

import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mission/apx_mission.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection.dart';
import 'payloads.dart';
import 'storage.dart';
import 'vehicle_params.dart';

/// What a tap on the Plan map does.
enum PlanTool { select, waypoint, survey, corridor, orbit, land }

/// The plan being edited and everything around it.
final class PlanState {
  const PlanState({
    required this.plan,
    this.selected,
    this.tool = PlanTool.select,
    this.draft = const [],
    this.fileName,
    this.dirty = false,
    this.home,
    this.canUndo = false,
    this.canRedo = false,
  });

  final MissionPlan plan;

  /// Selected element id.
  final String? selected;
  final PlanTool tool;

  /// Points placed so far while drawing a survey/corridor.
  final List<GeoPoint> draft;
  final String? fileName;
  final bool dirty;

  /// Planning home when no vehicle reports one.
  final GeoPoint? home;
  final bool canUndo, canRedo;

  MissionElement? get selectedElement => plan.elements.where((e) => e.id == selected).firstOrNull;

  PlanState copyWith({
    MissionPlan? plan,
    String? selected,
    bool clearSelected = false,
    PlanTool? tool,
    List<GeoPoint>? draft,
    String? fileName,
    bool? dirty,
    GeoPoint? home,
    bool? canUndo,
    bool? canRedo,
  }) => PlanState(
    plan: plan ?? this.plan,
    selected: clearSelected ? null : (selected ?? this.selected),
    tool: tool ?? this.tool,
    draft: draft ?? this.draft,
    fileName: fileName ?? this.fileName,
    dirty: dirty ?? this.dirty,
    home: home ?? this.home,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
  );
}

/// Edits the plan. Every change goes through [_commit], which keeps undo
/// history and autosaves the working plan to `plans/current.apxplan`, so a
/// crash or restart in the field doesn't lose it.
final class PlanController extends Notifier<PlanState> {
  final _undo = <MissionPlan>[];
  final _redo = <MissionPlan>[];
  final ids = IdSource();
  Timer? _autosave;

  File get _autosaveFile =>
      File('${ref.read(dataDirProvider).path}${Platform.pathSeparator}plans${Platform.pathSeparator}current.apxplan');

  @override
  PlanState build() {
    ref.onDispose(() => _autosave?.cancel());
    final store = ref.read(settingsStoreProvider);
    final h = store.get<List>('planHome');
    final home = h == null ? null : GeoPoint((h[0] as num).toDouble(), (h[1] as num).toDouble());
    var plan = MissionPlan(payloads: ref.read(payloadsProvider));
    try {
      if (_autosaveFile.existsSync()) plan = PlanFiles.fromApxPlan(_autosaveFile.readAsStringSync());
    } catch (_) {
      // A damaged autosave is not worth failing start‑up over.
    }
    return PlanState(plan: plan, home: home, fileName: store.get<String>('planName'));
  }

  void _commit(MissionPlan plan, {String? select, bool clearSelect = false}) {
    _undo.add(state.plan);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    state = state.copyWith(
      plan: plan,
      dirty: true,
      selected: select,
      clearSelected: clearSelect,
      canUndo: true,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(seconds: 1), () {
      try {
        _autosaveFile.parent.createSync(recursive: true);
        _autosaveFile.writeAsStringSync(PlanFiles.toApxPlan(state.plan));
      } catch (_) {
        // Autosave is best effort; explicit Save reports errors.
      }
    });
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(state.plan);
    final p = _undo.removeLast();
    state = state.copyWith(plan: p, dirty: true, canUndo: _undo.isNotEmpty, canRedo: true);
    _scheduleAutosave();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(state.plan);
    final p = _redo.removeLast();
    state = state.copyWith(plan: p, dirty: true, canUndo: true, canRedo: _redo.isNotEmpty);
    _scheduleAutosave();
  }

  // ---- selection and tools ----------------------------------------------------

  void select(String? id) => state = state.copyWith(selected: id, clearSelected: id == null);

  void setTool(PlanTool t) => state = state.copyWith(tool: t, draft: const []);

  void setHome(GeoPoint p) {
    state = state.copyWith(home: p);
    ref.read(settingsStoreProvider).set('planHome', [p.lat, p.lon]);
  }

  double get _alt => state.plan.settings.altitude;

  /// A tap on the map with the current tool.
  void tapMap(GeoPoint p) {
    switch (state.tool) {
      case PlanTool.select:
        select(null);
      case PlanTool.waypoint:
        final e = WaypointElement(id: ids.next(), position: p, altitude: _lastAltitude());
        _commit(state.plan.copyWith(elements: [...state.plan.elements, e]), select: e.id);
      case PlanTool.survey:
      case PlanTool.corridor:
        state = state.copyWith(draft: [...state.draft, p]);
      case PlanTool.orbit:
        final e = OrbitElement(id: ids.next(), center: p, radius: 20, altitude: _lastAltitude());
        _commit(state.plan.copyWith(elements: [...state.plan.elements, e]), select: e.id);
        state = state.copyWith(tool: PlanTool.select);
      case PlanTool.land:
        final e = LandElement(id: ids.next(), position: p);
        _commit(state.plan.copyWith(elements: [...state.plan.elements, e]), select: e.id);
        state = state.copyWith(tool: PlanTool.select);
    }
  }

  double _lastAltitude() {
    for (final e in state.plan.elements.reversed) {
      switch (e) {
        case WaypointElement(:final altitude) ||
            SurveyElement(:final altitude) ||
            CorridorElement(:final altitude) ||
            OrbitElement(:final altitude):
          return altitude;
        default:
      }
    }
    return _alt;
  }

  void undoDraftPoint() {
    if (state.draft.isNotEmpty) state = state.copyWith(draft: state.draft.sublist(0, state.draft.length - 1));
  }

  /// Turns the drawn points into a survey or corridor.
  String? finishDraft() {
    final pts = state.draft;
    if (state.tool == PlanTool.survey) {
      if (pts.length < 3) return 'Place at least 3 corners.';
      if (selfIntersects(pts)) return 'The edges cross; place the corners in order around the area.';
      final e = SurveyElement(
        id: ids.next(),
        polygon: pts,
        altitude: _lastAltitude(),
        angleDeg: _longestEdgeBearing(pts),
        payload: PatternPayload(payloadId: _defaultPayload()),
      );
      _commit(state.plan.copyWith(elements: [...state.plan.elements, e]), select: e.id);
    } else if (state.tool == PlanTool.corridor) {
      if (pts.length < 2) return 'Place at least 2 path points.';
      final e = CorridorElement(
        id: ids.next(),
        path: pts,
        altitude: _lastAltitude(),
        payload: PatternPayload(payloadId: _defaultPayload()),
      );
      _commit(state.plan.copyWith(elements: [...state.plan.elements, e]), select: e.id);
    }
    state = state.copyWith(tool: PlanTool.select, draft: const []);
    return null;
  }

  String? _defaultPayload() => state.plan.payloads.firstOrNull?.id;

  /// Passes along the longest edge: fewest turns for most fields.
  static double _longestEdgeBearing(List<GeoPoint> pts) {
    var best = 0.0, bearing = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final d = haversineMetres(a, b);
      if (d > best) {
        best = d;
        bearing = bearingDeg(a, b) % 180;
      }
    }
    return bearing.roundToDouble();
  }

  static double longestEdgeBearing(List<GeoPoint> pts) => _longestEdgeBearing(pts);

  // ---- element edits ----------------------------------------------------------

  void replace(MissionElement e) {
    final els = [for (final x in state.plan.elements) x.id == e.id ? e : x];
    _commit(state.plan.copyWith(elements: els), select: state.selected);
  }

  void add(MissionElement e, {int? at}) {
    final els = [...state.plan.elements];
    els.insert(at ?? els.length, e);
    _commit(state.plan.copyWith(elements: els), select: e.id);
  }

  void remove(String id) => _commit(
    state.plan.copyWith(elements: state.plan.elements.where((e) => e.id != id).toList()),
    clearSelect: state.selected == id,
    select: state.selected == id ? null : state.selected,
  );

  /// Deletes every matching element in one undo step (e.g. all waypoints).
  void removeWhere(bool Function(MissionElement) test) {
    final els = state.plan.elements.where((e) => !test(e)).toList();
    if (els.length == state.plan.elements.length) return;
    final keep = els.any((e) => e.id == state.selected);
    _commit(
      state.plan.copyWith(elements: els),
      select: keep ? state.selected : null,
      clearSelect: !keep,
    );
  }

  void reorder(int from, int to) {
    final els = [...state.plan.elements];
    final e = els.removeAt(from);
    els.insert(to.clamp(0, els.length), e);
    _commit(state.plan.copyWith(elements: els), select: state.selected);
  }

  /// Replaces a pattern with its individual waypoints and commands.
  void explode(String id, CompiledMission compiled) {
    final els = <MissionElement>[];
    for (final e in state.plan.elements) {
      els.addAll(e.id == id ? explodeElement(e, compiled, ids) : [e]);
    }
    _commit(state.plan.copyWith(elements: els), clearSelect: true);
  }

  void setSettings(MissionSettings s) => _commit(state.plan.copyWith(settings: s), select: state.selected);

  /// Keeps the plan's payload list in step with the vehicle's (Vehicle →
  /// Payloads), keeping definitions only the plan has (from an opened file).
  void syncPayloads(List<Payload> vehicle) {
    final ids = {for (final p in vehicle) p.id};
    final merged = [...vehicle, ...state.plan.payloads.where((p) => !ids.contains(p.id))];
    if (merged.map((p) => p.toJson().toString()).join() ==
        state.plan.payloads.map((p) => p.toJson().toString()).join()) {
      return;
    }
    state = state.copyWith(plan: state.plan.copyWith(payloads: merged));
  }

  // ---- files ------------------------------------------------------------------

  void newPlan() {
    _commit(MissionPlan(payloads: ref.read(payloadsProvider)), clearSelect: true);
    state = state.copyWith(fileName: '', dirty: false);
    ref.read(settingsStoreProvider).set('planName', null);
  }

  void load(MissionPlan plan, {required String name, GeoPoint? home}) {
    _commit(plan, clearSelect: true);
    state = state.copyWith(fileName: name, dirty: false, home: home);
    syncPayloads(ref.read(payloadsProvider));
    ref.read(settingsStoreProvider).set('planName', name);
  }

  void markSaved(String name) {
    state = state.copyWith(fileName: name, dirty: false);
    ref.read(settingsStoreProvider).set('planName', name);
  }
}

final planProvider = NotifierProvider<PlanController, PlanState>(PlanController.new);

/// Vehicle facts for compiling: from the connected vehicle's parameters, or
/// APX defaults when offline.
final vehicleFactsProvider = Provider<VehicleFacts>((ref) {
  ref.watch(paramRevisionProvider);
  final params = ref.watch(paramServiceProvider)?.all;
  if (params == null || params.isEmpty) return const VehicleFacts();
  return VehicleFacts.fromParameters({for (final p in params.values) p.name: p.value});
});

/// Where the mission starts: the vehicle's home when known, else the
/// planning home, else the first element.
final planHomeProvider = Provider<GeoPoint?>((ref) {
  final conn = ref.watch(connectionProvider);
  if (conn != null) ref.watch(frameTickProvider); // telemetry is polled, not pushed
  final s = conn?.session.telemetry.snapshot;
  if (s != null && !s.homeLat.isNaN) return GeoPoint(s.homeLat, s.homeLon);
  // Not armed yet, so no home: it will be where the vehicle is now. Rounded
  // to ~1 m so GPS jitter doesn't recompile the plan every frame.
  if (s != null && s.hasPosition) {
    double r(double v) => (v * 1e5).roundToDouble() / 1e5;
    return GeoPoint(r(s.lat), r(s.lon));
  }
  return ref.watch(planProvider.select((p) => p.home));
});

/// The compiled plan and its issues, recomputed when the plan changes.
final compiledPlanProvider = Provider<(CompiledMission, List<Issue>)>((ref) {
  final plan = ref.watch(planProvider.select((s) => s.plan));
  final facts = ref.watch(vehicleFactsProvider);
  final home = ref.watch(planHomeProvider);
  final compiled = MissionCompiler(facts: facts).compile(plan, home: home);
  return (compiled, validatePlan(plan, compiled, facts));
});

/// Mission upload/download with the vehicle.
final class MissionLink {
  MissionLink(this.session);
  final VehicleSession session;

  /// Uploads and reads back to confirm the vehicle holds exactly this.
  Future<void> upload(CompiledMission m) async {
    final items = m.toWire();
    await session.missions.upload(items);
    final back = await session.missions.download();
    session.vehicleMission = back;
    if (back.length != items.length) {
      throw TransferException('The vehicle holds ${back.length} items, expected ${items.length}.');
    }
    for (var i = 1; i < items.length; i++) {
      final a = items[i], b = back[i];
      if (a.command != b.command || a.x != b.x || a.y != b.y || (a.z - b.z).abs() > 0.01) {
        throw TransferException('Item $i reads back differently from what was sent.');
      }
    }
  }

  Future<ImportResult> download() async {
    final items = await session.missions.download();
    session.vehicleMission = items;
    return PlanFiles.fromWire(items);
  }
}
