// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_mission/apx_mission.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../fly/instruments.dart';
import '../map/layers_panel.dart';
import '../map/map_dialogs.dart';
import '../map/map_layers.dart';
import '../map/path_arrows.dart';
import '../state/connection.dart';
import '../state/payloads.dart';
import '../state/plan.dart';
import '../state/storage.dart';
import '../state/view_items.dart';
import 'plan_panel.dart';

/// Colour for legs flown with a payload working.
const _payloadColour = Color(0xFF5E9E2E);

/// Mission planning: draw and edit on the map, details in the side panel.
class PlanView extends ConsumerStatefulWidget {
  const PlanView({super.key});

  @override
  ConsumerState<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends ConsumerState<PlanView> {
  final _map = MapController();
  final _mapKey = GlobalKey();
  bool _layersOpen = false;

  /// An element being dragged: shown live, committed on release (one undo step).
  MissionElement? _preview;

  /// A handle has the pointer: map panning is off until it is released, so a
  /// drag that starts on a handle always moves the handle, never the map.
  bool _dragging = false;
  Offset? _downAt;
  LatLng? _dragStart;
  bool _moved = false;

  /// Centred on the vehicle once after it connected, for an empty plan.
  bool _centredOnVehicle = false;

  GeoPoint? _vehiclePosition() {
    final s = ref.read(connectionProvider)?.session.telemetry.snapshot;
    return s != null && s.hasPosition ? GeoPoint(s.lat, s.lon) : null;
  }

  void _centreOnVehicle() {
    final v = _vehiclePosition();
    if (v != null) _map.move(toLatLng(v), _map.camera.zoom < 16 ? 17 : _map.camera.zoom);
  }

  PlanController get _ctl => ref.read(planProvider.notifier);

  @override
  void initState() {
    super.initState();
    // An autosaved or opened plan may carry older payload definitions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctl.syncPayloads(ref.read(payloadsProvider));
    });
  }

  late final (LatLng, double) _view = () {
    final v = ref.read(settingsStoreProvider).get<Map>('mapView');
    if (v == null) return (const LatLng(20, 0), 3.0);
    return (LatLng((v['lat'] as num).toDouble(), (v['lon'] as num).toDouble()), (v['zoom'] as num).toDouble());
  }();

  LatLng _toMap(Offset global) {
    final box = _mapKey.currentContext!.findRenderObject()! as RenderBox;
    return _map.camera.screenOffsetToLatLng(box.globalToLocal(global));
  }

  void _zoomTo(MissionElement? e) {
    final home = ref.read(planHomeProvider);
    final pts = e == null ? [?home, ...ref.read(planProvider).plan.elements.expand((x) => x.anchors)] : e.anchors;
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(toLatLng(pts.first), _map.camera.zoom < 16 ? 17 : _map.camera.zoom);
      return;
    }
    final b = GeoBounds.around(pts);
    _map.fitCamera(
      CameraFit.bounds(bounds: toLatLngBounds(b), padding: const EdgeInsets.fromLTRB(440, 80, 100, 80), maxZoom: 19),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the plan's payload list in step with Vehicle → Payloads.
    ref.listen(payloadsProvider, (_, v) => _ctl.syncPayloads(v));
    // Start planning where the drone is: centre on it once when it first
    // reports a position, unless a plan is already open.
    ref.listen(planHomeProvider, (_, home) {
      if (home == null || _centredOnVehicle || _vehiclePosition() == null) return;
      _centredOnVehicle = true;
      if (ref.read(planProvider).plan.elements.isEmpty) _centreOnVehicle();
    });
    if (ref.watch(connectionProvider.select((c) => c == null))) _centredOnVehicle = false;
    final st = ref.watch(planProvider);
    final drawing = st.tool == PlanTool.survey || st.tool == PlanTool.corridor;
    return Stack(
      children: [
        Positioned.fill(child: _mapLayer(st)),
        Positioned(top: 16, left: 16, bottom: 16, child: PlanPanel(onZoomTo: _zoomTo)),
        Positioned(top: 16, right: 16, child: _tools(st)),
        if (_layersOpen)
          Positioned(
            top: 16,
            right: 72,
            bottom: 16,
            child: Align(
              alignment: Alignment.topRight,
              child: LayersPanel(
                camera: () => _map.camera,
                onClose: () => setState(() => _layersOpen = false),
                onZoomTo: (b) =>
                    _map.fitCamera(CameraFit.bounds(bounds: toLatLngBounds(b), padding: const EdgeInsets.all(60))),
                onEditCorners: (_) => notify(context, 'Adjust overlay corners from the Fly view.'),
              ),
            ),
          ),
        if (st.tool != PlanTool.select)
          Positioned(left: 432, right: 80, bottom: 16, child: Center(child: _toolBar(st, drawing))),
      ],
    );
  }

  Widget _tools(PlanState st) {
    Widget tool(PlanTool t, IconData icon, String tip) => GlassIconButton(
      icon: icon,
      tooltip: tip,
      active: st.tool == t,
      onPressed: () => _ctl.setTool(st.tool == t ? PlanTool.select : t),
    );
    return Column(
      spacing: 10,
      children: [
        Glass(
          padding: EdgeInsets.zero,
          radius: 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tool(PlanTool.waypoint, LucideIcons.mapPin, 'Add waypoints'),
              tool(PlanTool.survey, LucideIcons.grid3x3, 'Survey an area'),
              tool(PlanTool.corridor, LucideIcons.route, 'Corridor along a path'),
              tool(PlanTool.orbit, LucideIcons.rotateCw, 'Orbit a point'),
              tool(PlanTool.land, LucideIcons.planeLanding, 'Land at a point'),
            ],
          ),
        ),
        Glass(
          padding: EdgeInsets.zero,
          radius: 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassIconButton(
                icon: LucideIcons.plus,
                tooltip: 'Zoom in',
                onPressed: () => _map.move(_map.camera.center, _map.camera.zoom + 1),
              ),
              GlassIconButton(
                icon: LucideIcons.minus,
                tooltip: 'Zoom out',
                onPressed: () => _map.move(_map.camera.center, _map.camera.zoom - 1),
              ),
              GlassIconButton(
                icon: LucideIcons.scan,
                tooltip: 'Show the whole mission',
                onPressed: () => _zoomTo(null),
              ),
              GlassIconButton(
                icon: LucideIcons.locateFixed,
                tooltip: 'Centre on the vehicle',
                onPressed: ref.watch(connectionProvider.select((c) => c == null)) ? null : _centreOnVehicle,
              ),
              GlassIconButton(
                icon: LucideIcons.layers,
                tooltip: 'Map layers',
                active: _layersOpen,
                onPressed: () => setState(() => _layersOpen = !_layersOpen),
              ),
              GlassIconButton(
                icon: LucideIcons.house,
                tooltip: 'Set planning home to the map centre',
                onPressed: () => _ctl.setHome(toGeo(_map.camera.center)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolBar(PlanState st, bool drawing) {
    final text = switch (st.tool) {
      PlanTool.waypoint => 'Tap the map to add waypoints.',
      PlanTool.survey => 'Tap the corners of the area in order (${st.draft.length} placed).',
      PlanTool.corridor => 'Tap points along the path (${st.draft.length} placed).',
      PlanTool.orbit => 'Tap the point to orbit.',
      PlanTool.land => 'Tap where to land.',
      PlanTool.select => '',
    };
    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      radius: Alloy.radiusCapsule,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Flexible(child: Text(text)),
          if (drawing && st.draft.isNotEmpty) AlloyButton(label: 'Undo point', onPressed: _ctl.undoDraftPoint),
          AlloyButton(label: drawing ? 'Cancel' : 'Done', onPressed: () => _ctl.setTool(PlanTool.select)),
          if (drawing)
            AlloyButton(
              label: 'Finish',
              primary: true,
              onPressed: () {
                final err = _ctl.finishDraft();
                if (err != null) notify(context, err);
              },
            ),
        ],
      ),
    );
  }

  Widget _mapLayer(PlanState st) {
    final p = context.alloy;
    final (compiled, _) = ref.watch(compiledPlanProvider);
    final home = ref.watch(planHomeProvider);
    final viewSettings = ref.watch(viewItemSettingsProvider);
    final pathSize = viewSettings.pathSize;
    final plan = st.plan;
    final els = [for (final e in plan.elements) e.id == _preview?.id ? _preview! : e];

    // Path legs, split where the payload state changes.
    final legs = <Polyline>[];
    final pathRuns = <(List<LatLng>, Color)>[];
    LatLng? at = home == null ? null : toLatLng(home);
    var run = <LatLng>[?at];
    var runOn = false;
    void flush() {
      if (run.length > 1) {
        pathRuns.add((List.of(run), runOn ? _payloadColour : AlloyPalette.accent));
        // High-contrast casing underneath for clear visibility on bright map tiles and satellite imagery
        legs.add(
          Polyline(
            points: run,
            strokeWidth: runOn ? (pathSize + 2.3) : (pathSize + 2.0),
            color: Colors.black.withValues(alpha: 0.4),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
        legs.add(
          Polyline(
            points: run,
            strokeWidth: runOn ? (pathSize * 1.05) : pathSize,
            color: runOn ? _payloadColour : AlloyPalette.accent,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
      }
    }

    for (final it in compiled.items) {
      LatLng? to;
      if (it.position != null && it.isNav) to = toLatLng(it.position!);
      if (it.command == MavCmd.navReturnToLaunch && home != null) to = toLatLng(home);
      if (to == null) continue;
      if (it.payloadOn != runOn) {
        flush();
        run = [?at];
        runOn = it.payloadOn;
      }
      run.add(to);
      at = to;
    }
    flush();

    final selected = st.selected;
    return FlutterMap(
      key: _mapKey,
      mapController: _map,
      options: MapOptions(
        initialCenter: _view.$1,
        initialZoom: _view.$2,
        maxZoom: 22,
        backgroundColor: p.canvas,
        // Double-tap zoom stays on while a handle is dragged: flutter_map
        // re-subscribes a single-use stream when that flag changes, after
        // which map taps stop arriving.
        interactionOptions: InteractionOptions(flags: _dragging ? InteractiveFlag.doubleTapZoom : InteractiveFlag.all),
        onTap: (_, ll) => _ctl.tapMap(toGeo(ll)),
      ),
      children: [
        ...mapBaseLayers(ref),
        // Pattern shapes.
        PolygonLayer(
          polygons: [
            for (final e in els.whereType<SurveyElement>())
              Polygon(
                points: [for (final v in e.polygon) toLatLng(v)],
                color: AlloyPalette.accent.withValues(alpha: e.id == selected ? 0.14 : 0.07),
                borderColor: AlloyPalette.accent.withValues(alpha: e.id == selected ? 1 : 0.7),
                borderStrokeWidth: e.id == selected ? 3.5 : 2.5,
              ),
            if (st.tool == PlanTool.survey && st.draft.length > 2)
              Polygon(
                points: [for (final v in st.draft) toLatLng(v)],
                color: AlloyPalette.accent.withValues(alpha: 0.1),
                borderColor: AlloyPalette.accent,
                borderStrokeWidth: 3.0,
                pattern: StrokePattern.dashed(segments: const [8, 6]),
              ),
          ],
        ),
        CircleLayer(
          circles: [
            for (final e in els.whereType<OrbitElement>())
              CircleMarker(
                point: toLatLng(e.center),
                radius: e.radius,
                useRadiusInMeter: true,
                color: AlloyPalette.accent.withValues(alpha: e.id == selected ? 0.10 : 0.05),
                borderColor: AlloyPalette.accent.withValues(alpha: e.id == selected ? 0.9 : 0.6),
                borderStrokeWidth: e.id == selected ? 3.5 : 2.5,
              ),
          ],
        ),
        PolylineLayer(
          polylines: [
            for (final e in els.whereType<CorridorElement>()) ...[
              Polyline(
                points: [for (final v in e.path) toLatLng(v)],
                strokeWidth: 5.5,
                color: Colors.black.withValues(alpha: 0.35),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
              Polyline(
                points: [for (final v in e.path) toLatLng(v)],
                strokeWidth: 3.2,
                color: e.id == selected ? AlloyPalette.accent : p.ink.withValues(alpha: 0.75),
                pattern: StrokePattern.dashed(segments: const [8, 6]),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
            // A line needs two points: flutter_map asserts on fewer.
            if ((st.tool == PlanTool.corridor || st.tool == PlanTool.survey) && st.draft.length == 2 ||
                st.tool == PlanTool.corridor && st.draft.length > 2) ...[
              Polyline(
                points: [for (final v in st.draft) toLatLng(v)],
                strokeWidth: 6.0,
                color: Colors.black.withValues(alpha: 0.35),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
              Polyline(
                points: [for (final v in st.draft) toLatLng(v)],
                strokeWidth: 3.5,
                color: AlloyPalette.accent,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
            ...legs,
          ],
        ),
        FlightPathArrowsLayer(runs: pathRuns),
        MarkerLayer(
          markers: [
            if (home != null)
              Marker(
                point: toLatLng(home),
                width: 30,
                height: 30,
                child: _pin(const Icon(LucideIcons.house, size: 15, color: Color(0xFF0B7C87))),
              ),
            // Numbered waypoints (number = vehicle item).
            for (final e in els)
              if (e is WaypointElement)
                _handle(
                  e.position,
                  size: 28,
                  onTap: () => _ctl.select(e.id),
                  onDrag: (ll, _) => setState(() => _preview = e.copyWith(position: toGeo(ll))),
                  onDragEnd: _commitPreview,
                  child: _pin(
                    Text(
                      '${compiled.items.indexWhere((i) => i.elementId == e.id && i.isNav) + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: e.id == selected ? Colors.white : const Color(0xFF0B7C87),
                      ),
                    ),
                    filled: e.id == selected,
                  ),
                )
              else if (e is LandElement && e.position != null)
                _handle(
                  e.position!,
                  size: 30,
                  onTap: () => _ctl.select(e.id),
                  onDrag: (ll, _) => setState(() => _preview = LandElement(id: e.id, position: toGeo(ll))),
                  onDragEnd: _commitPreview,
                  child: _pin(
                    const Icon(LucideIcons.planeLanding, size: 15, color: Color(0xFF0B7C87)),
                    filled: e.id == selected,
                  ),
                )
              else if (e.anchors.isNotEmpty && e.id != selected)
                _handle(
                  _badgePoint(e),
                  size: 30,
                  onTap: () => _ctl.select(e.id),
                  onDrag: (ll, start) => _moveWhole(e.id, ll, start),
                  onDragEnd: _commitPreview,
                  child: _pin(Icon(_icon(e), size: 15, color: const Color(0xFF0B7C87))),
                ),
            ..._editHandles(els.where((e) => e.id == selected).firstOrNull),
            for (final v in st.draft)
              Marker(
                point: toLatLng(v),
                width: 14,
                height: 14,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: AlloyPalette.accent, width: 3),
                  ),
                ),
              ),
          ],
        ),
        // On top so the home pin can't hide it; it ignores the pointer.
        const _VehicleLayer(),
        mapAttribution(ref),
      ],
    );
  }

  /// Shows [id] shifted by the pointer's travel since the drag began.
  void _moveWhole(String id, LatLng now, LatLng start) {
    final orig = ref.read(planProvider).plan.elements.where((x) => x.id == id).firstOrNull;
    if (orig == null) return;
    setState(() => _preview = orig.translated(now.latitude - start.latitude, now.longitude - start.longitude));
  }

  void _commitPreview() {
    final e = _preview;
    setState(() => _preview = null);
    if (e != null) _ctl.replace(e);
  }

  static IconData _icon(MissionElement e) => switch (e) {
    SurveyElement() => LucideIcons.grid3x3,
    CorridorElement() => LucideIcons.route,
    OrbitElement(:final clockwise) => clockwise ? LucideIcons.rotateCw : LucideIcons.rotateCcw,
    _ => LucideIcons.mapPin,
  };

  GeoPoint _badgePoint(MissionElement e) => switch (e) {
    SurveyElement(:final polygon) => centroid(polygon),
    CorridorElement(:final path) => _halfway(path),
    OrbitElement(:final center) => center,
    _ => e.anchors.first,
  };

  /// Corner / path / centre / radius handles of the selected element.
  List<Marker> _editHandles(MissionElement? e) {
    if (e == null) return const [];
    Marker vertex(GeoPoint v, void Function(LatLng) drag, {VoidCallback? remove, required String keep}) => _handle(
      v,
      size: 22,
      onDrag: (ll, _) => drag(ll),
      onDragEnd: _commitPreview,
      onRemove: remove,
      cannotRemove: keep,
      tooltip: 'Drag to move · double‑click or right‑click to delete',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: AlloyPalette.accent, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
        ),
      ),
    );
    Marker insert(GeoPoint a, GeoPoint b, VoidCallback onTap) => Marker(
      point: LatLng((a.lat + b.lat) / 2, (a.lon + b.lon) / 2),
      width: 20,
      height: 20,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: AlloyPalette.accent.withValues(alpha: 0.85)),
          child: const Icon(LucideIcons.plus, size: 13, color: Colors.white),
        ),
      ),
    );
    // The whole pattern moves with this one (corners and path points stay
    // individually draggable).
    Marker mover() => _handle(
      _badgePoint(e),
      lift: e is CorridorElement ? 34 : 0,
      size: 30,
      cursor: SystemMouseCursors.move,
      onDrag: (ll, start) => _moveWhole(e.id, ll, start),
      onDragEnd: _commitPreview,
      tooltip: 'Drag to move the whole pattern',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AlloyPalette.accent,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
        ),
        child: const Icon(LucideIcons.move, size: 15, color: Colors.white),
      ),
    );
    switch (e) {
      case SurveyElement(:final polygon):
        return [
          mover(),
          for (var i = 0; i < polygon.length; i++)
            insert(polygon[i], polygon[(i + 1) % polygon.length], () {
              _ctl.replace(
                e.copyWith(polygon: [...polygon]..insert(i + 1, _mid(polygon[i], polygon[(i + 1) % polygon.length]))),
              );
            }),
          for (var i = 0; i < polygon.length; i++)
            vertex(
              polygon[i],
              (ll) => setState(() => _preview = e.copyWith(polygon: [...polygon]..[i] = toGeo(ll))),
              remove: polygon.length > 3 ? () => _ctl.replace(e.copyWith(polygon: [...polygon]..removeAt(i))) : null,
              keep: 'A survey area needs at least 3 corners.',
            ),
        ];
      case CorridorElement(:final path):
        return [
          mover(),
          for (var i = 0; i + 1 < path.length; i++)
            insert(
              path[i],
              path[i + 1],
              () => _ctl.replace(e.copyWith(path: [...path]..insert(i + 1, _mid(path[i], path[i + 1])))),
            ),
          for (var i = 0; i < path.length; i++)
            vertex(
              path[i],
              (ll) => setState(() => _preview = e.copyWith(path: [...path]..[i] = toGeo(ll))),
              remove: path.length > 2 ? () => _ctl.replace(e.copyWith(path: [...path]..removeAt(i))) : null,
              keep: 'A corridor needs at least 2 points.',
            ),
        ];
      case OrbitElement(:final center, :final radius, :final startBearing):
        return [
          mover(),
          _handle(
            destination(center, startBearing, radius),
            size: 26,
            onDrag: (ll, _) {
              final g = toGeo(ll);
              setState(
                () => _preview = e.copyWith(
                  radius: haversineMetres(center, g).clamp(2.0, 2000.0).roundToDouble(),
                  startBearing: bearingDeg(center, g).roundToDouble(),
                ),
              );
            },
            onDragEnd: _commitPreview,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AlloyPalette.accent,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(LucideIcons.moveHorizontal, size: 13, color: Colors.white),
            ),
          ),
        ];
      default:
        return const [];
    }
  }

  /// The point half way along [path] by length (a path point or "+" handle
  /// would otherwise sit on the same spot as the move handle).
  static GeoPoint _halfway(List<GeoPoint> path) {
    final legs = [for (var i = 0; i + 1 < path.length; i++) haversineMetres(path[i], path[i + 1])];
    var left = legs.fold(0.0, (a, b) => a + b) / 2;
    for (var i = 0; i < legs.length; i++) {
      if (left <= legs[i] && legs[i] > 0) {
        final t = left / legs[i];
        return GeoPoint(
          path[i].lat + (path[i + 1].lat - path[i].lat) * t,
          path[i].lon + (path[i + 1].lon - path[i].lon) * t,
        );
      }
      left -= legs[i];
    }
    return path.first;
  }

  static GeoPoint _mid(GeoPoint a, GeoPoint b) => GeoPoint((a.lat + b.lat) / 2, (a.lon + b.lon) / 2);

  Marker _handle(
    GeoPoint at, {
    required double size,
    required Widget child,
    required void Function(LatLng now, LatLng start) onDrag,
    required VoidCallback onDragEnd,
    VoidCallback? onTap,
    VoidCallback? onRemove,
    String? cannotRemove,
    MouseCursor cursor = SystemMouseCursors.grab,
    String? tooltip,
    double lift = 0,
  }) {
    void end() {
      final moved = _moved;
      setState(() {
        _dragging = false;
        _downAt = _dragStart = null;
        _moved = false;
      });
      if (moved) onDragEnd();
    }

    Widget w = Listener(
      // Raw pointer events: the map's own pan recogniser would otherwise win
      // the gesture race with a mouse (its slop is smaller than a drag's).
      onPointerDown: (e) {
        if (e.buttons != kPrimaryButton) return;
        setState(() => _dragging = true);
        _downAt = e.position;
        _dragStart = _toMap(e.position);
        _moved = false;
      },
      onPointerMove: (e) {
        if (!_dragging || _downAt == null) return;
        if (!_moved && (e.position - _downAt!).distance < 3) return;
        _moved = true;
        onDrag(_toMap(e.position), _dragStart!);
      },
      onPointerUp: (_) => end(),
      onPointerCancel: (_) => end(),
      child: GestureDetector(
        onTap: onTap,
        // Points that can be deleted: double‑click, or right‑click / touch
        // long‑press for a menu.
        onDoubleTap: cannotRemove == null ? null : () => _deletePoint(onRemove, cannotRemove),
        onSecondaryTapUp: cannotRemove == null ? null : (d) => _pointMenu(d.globalPosition, onRemove, cannotRemove),
        child: GestureDetector(
          // Touch only: with a mouse a pause before dragging would open it.
          supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
          onLongPressStart: cannotRemove == null
              ? null
              : (d) {
                  setState(() {
                    _dragging = false;
                    _downAt = null;
                    _moved = false;
                    _preview = null;
                  });
                  _pointMenu(d.globalPosition, onRemove, cannotRemove);
                },
          child: child,
        ),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip, waitDuration: const Duration(milliseconds: 700), child: w);
    final handle = MouseRegion(cursor: _dragging ? SystemMouseCursors.grabbing : cursor, child: w);
    return Marker(
      point: toLatLng(at),
      width: size,
      // Lifted handles sit [lift] px above their point; the empty lower part
      // of the marker lets clicks through.
      height: size + 2 * lift,
      child: lift == 0
          ? handle
          : Align(
              alignment: Alignment.topCenter,
              child: SizedBox.square(dimension: size, child: handle),
            ),
    );
  }

  void _deletePoint(VoidCallback? remove, String cannot) {
    if (remove == null) {
      notify(context, cannot);
    } else {
      remove();
    }
  }

  Future<void> _pointMenu(Offset at, VoidCallback? remove, String cannot) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final pick = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          value: true,
          enabled: remove != null,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.trash2, size: 16, color: AlloyPalette.warning),
            title: const Text('Delete point'),
            subtitle: remove == null ? Text(cannot) : null,
          ),
        ),
      ],
    );
    if (pick == true) remove?.call();
  }

  Widget _pin(Widget child, {bool filled = false}) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? AlloyPalette.accent : Colors.white,
      border: Border.all(color: AlloyPalette.accent, width: 2.5),
    ),
    child: child,
  );
}

/// The connected vehicle on the planning map, so a plan can be drawn
/// relative to where the drone is. Rebuilds with telemetry on its own.
class _VehicleLayer extends ConsumerWidget {
  const _VehicleLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    if (conn == null) return const SizedBox.shrink();
    ref.watch(frameTickProvider);
    final s = conn.session.telemetry.snapshot;
    if (!s.hasPosition) return const SizedBox.shrink();
    final viewSettings = ref.watch(viewItemSettingsProvider);
    final iconSize = viewSettings.droneIconSize;
    return MarkerLayer(
      markers: [
        Marker(
          point: LatLng(s.lat, s.lon),
          width: iconSize,
          height: iconSize,
          child: IgnorePointer(
            child: VehicleGlyph(
              arms: VehicleGlyph.armsOf(s.vehicleType),
              headingDeg: s.headingDeg.isNaN ? 0 : s.headingDeg,
              size: iconSize,
              vehicleType: s.vehicleType,
              customIconPath: viewSettings.customVehicleIcons[s.vehicleType],
            ),
          ),
        ),
      ],
    );
  }
}
