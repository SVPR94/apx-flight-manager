// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/tokens.dart';
import 'quad_edit.dart';

enum _Grip { corner, side, rotate, move }

/// Handles for placing an image overlay on the map: corners (free
/// perspective), side midpoints (move a side parallel to itself), a rotate
/// grip above the top side and a move grip in the middle.
///
/// The handles take raw pointer events and call [onDragStart] at once, so the
/// owner can switch map dragging off before the map's pan gesture wins.
class OverlayEditLayer extends StatefulWidget {
  const OverlayEditLayer({
    super.key,
    required this.corners,
    required this.mapKey,
    required this.onChanged,
    this.onDragStart,
    this.onDragEnd,
  });

  /// Top‑left, top‑right, bottom‑right, bottom‑left.
  final List<LatLng> corners;

  /// The [FlutterMap]'s key, to turn pointer positions into map positions.
  final GlobalKey mapKey;
  final ValueChanged<List<LatLng>> onChanged;
  final VoidCallback? onDragStart, onDragEnd;

  /// Distance of the rotate grip beyond the top side, in pixels.
  static const rotateReach = 44.0;

  @override
  State<OverlayEditLayer> createState() => _OverlayEditLayerState();
}

class _OverlayEditLayerState extends State<OverlayEditLayer> {
  int? _pointer;
  _Grip? _grip;
  int _index = 0;
  Offset? _last;

  @override
  void dispose() {
    // Editing closed mid‑drag: give the map its gestures back.
    if (_pointer != null) widget.onDragEnd?.call();
    super.dispose();
  }

  Offset? _local(Offset global) {
    final box = widget.mapKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  void _down(PointerDownEvent e, _Grip grip, [int index = 0]) {
    if (e.buttons != kPrimaryButton && e.buttons != 0) return;
    if (_pointer != null) return;
    _pointer = e.pointer;
    _grip = grip;
    _index = index;
    _last = _local(e.position);
    widget.onDragStart?.call();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _last == null) return;
    final now = _local(e.position);
    if (now == null) return;
    final camera = MapCamera.of(context);
    final q = [for (final c in widget.corners) camera.latLngToScreenOffset(c)];
    final delta = now - _last!;
    final moved = switch (_grip!) {
      _Grip.corner => QuadEdit.moveCorner(q, _index, q[_index] + delta),
      _Grip.side => QuadEdit.moveSide(q, _index, delta),
      _Grip.move => QuadEdit.translate(q, delta),
      _Grip.rotate => QuadEdit.rotate(q, QuadEdit.centre(q), QuadEdit.turn(QuadEdit.centre(q), _last!, now)),
    };
    _last = now;
    widget.onChanged([for (final p in moved) camera.screenOffsetToLatLng(p)]);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _grip = null;
    _last = null;
    widget.onDragEnd?.call();
  }

  Widget _handle({
    required Key key,
    required _Grip grip,
    int index = 0,
    required MouseCursor cursor,
    required Widget child,
  }) => MouseRegion(
    key: key,
    cursor: cursor,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _down(e, grip, index),
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Center(child: child),
    ),
  );

  static const _ink = Color(0xFF0B7C87);
  static const _shadow = [BoxShadow(color: Color(0x40000000), blurRadius: 6)];

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final c = widget.corners;
    final q = [for (final p in c) camera.latLngToScreenOffset(p)];
    final topMid = QuadEdit.sideMid(q, 0);
    final grip = topMid + QuadEdit.outwardNormal(q, 0) * OverlayEditLayer.rotateReach;
    final gripAt = camera.screenOffsetToLatLng(grip);
    final topMidAt = camera.screenOffsetToLatLng(topMid);

    return Stack(
      children: [
        IgnorePointer(
          child: PolygonLayer(
            polygons: [
              Polygon(
                points: c,
                color: AlloyPalette.accent.withValues(alpha: 0.08),
                borderColor: AlloyPalette.accent,
                borderStrokeWidth: 2,
                pattern: StrokePattern.dashed(segments: const [8, 6]),
              ),
            ],
          ),
        ),
        IgnorePointer(
          child: PolylineLayer(
            polylines: [
              Polyline(points: [topMidAt, gripAt], color: AlloyPalette.accent, strokeWidth: 2),
            ],
          ),
        ),
        // Later markers sit on top, so corners win where handles overlap.
        MarkerLayer(
          markers: [
            Marker(
              point: camera.screenOffsetToLatLng(QuadEdit.centre(q)),
              width: 36,
              height: 36,
              child: _handle(
                key: const ValueKey('overlay_move'),
                grip: _Grip.move,
                cursor: SystemMouseCursors.move,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: AlloyPalette.accent, width: 2),
                    boxShadow: _shadow,
                  ),
                  child: const Icon(LucideIcons.move, size: 16, color: _ink),
                ),
              ),
            ),
            for (var s = 0; s < 4; s++)
              Marker(
                point: camera.screenOffsetToLatLng(QuadEdit.sideMid(q, s)),
                width: 28,
                height: 28,
                child: _handle(
                  key: ValueKey('overlay_side_$s'),
                  grip: _Grip.side,
                  index: s,
                  cursor: (q[(s + 1) % 4] - q[s]).dx.abs() >= (q[(s + 1) % 4] - q[s]).dy.abs()
                      ? SystemMouseCursors.resizeUpDown
                      : SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: AlloyPalette.accent, width: 2.5),
                      boxShadow: _shadow,
                    ),
                  ),
                ),
              ),
            Marker(
              point: gripAt,
              width: 34,
              height: 34,
              child: _handle(
                key: const ValueKey('overlay_rotate'),
                grip: _Grip.rotate,
                cursor: SystemMouseCursors.grab,
                child: Tooltip(
                  message: 'Drag to rotate',
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AlloyPalette.accent,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: _shadow,
                    ),
                    child: const Icon(LucideIcons.rotateCw, size: 15, color: Colors.white),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < 4; i++)
              Marker(
                point: c[i],
                width: 34,
                height: 34,
                child: _handle(
                  key: ValueKey('overlay_corner_$i'),
                  grip: _Grip.corner,
                  index: i,
                  cursor: SystemMouseCursors.precise,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: AlloyPalette.accent, width: 3),
                      boxShadow: _shadow,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      const ['TL', 'TR', 'BR', 'BL'][i],
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _ink),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
