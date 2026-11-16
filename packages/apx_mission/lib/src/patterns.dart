// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_geo/apx_geo.dart';

/// One straight pass of a survey or corridor. The payload works between
/// [start] and [end]; [entry]/[exit] add the run‑in/run‑out (equal to
/// start/end when there is no overshoot).
final class Pass {
  const Pass(this.entry, this.start, this.end, this.exit);
  final GeoPoint entry, start, end, exit;

  bool get hasRunIn => entry != start;
  bool get hasRunOut => exit != end;
}

typedef _V = (double, double);

double _cross(_V a, _V b) => a.$1 * b.$2 - a.$2 * b.$1;
_V _sub(_V a, _V b) => (a.$1 - b.$1, a.$2 - b.$2);
_V _add(_V a, _V b) => (a.$1 + b.$1, a.$2 + b.$2);
_V _mul(_V a, double k) => (a.$1 * k, a.$2 * k);
double _len(_V a) => math.sqrt(a.$1 * a.$1 + a.$2 * a.$2);
_V _unit(_V a) {
  final l = _len(a);
  return l == 0 ? (0, 0) : (a.$1 / l, a.$2 / l);
}

GeoPoint centroid(List<GeoPoint> pts) {
  var la = 0.0, lo = 0.0;
  for (final p in pts) {
    la += p.lat;
    lo += p.lon;
  }
  return GeoPoint(la / pts.length, lo / pts.length);
}

/// Polygon area in m².
double polygonArea(List<GeoPoint> polygon) {
  if (polygon.length < 3) return 0;
  final f = LocalFrame(centroid(polygon));
  final v = [for (final p in polygon) f.toLocal(p)];
  var a = 0.0;
  for (var i = 0; i < v.length; i++) {
    a += _cross(v[i], v[(i + 1) % v.length]);
  }
  return a.abs() / 2;
}

/// True if any two non‑adjacent edges cross.
bool selfIntersects(List<GeoPoint> polygon) {
  final n = polygon.length;
  if (n < 4) return false;
  final f = LocalFrame(centroid(polygon));
  final v = [for (final p in polygon) f.toLocal(p)];
  bool crosses(_V a, _V b, _V c, _V d) {
    final d1 = _cross(_sub(b, a), _sub(c, a)), d2 = _cross(_sub(b, a), _sub(d, a));
    final d3 = _cross(_sub(d, c), _sub(a, c)), d4 = _cross(_sub(d, c), _sub(b, c));
    return d1 * d2 < 0 && d3 * d4 < 0;
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if ((j == i + 1) || (i == 0 && j == n - 1)) continue;
      if (crosses(v[i], v[(i + 1) % n], v[j], v[(j + 1) % n])) return true;
    }
  }
  return false;
}

/// How many survey lines [surveyPasses] would generate, without generating
/// them (cheap; used to refuse absurd patterns before they freeze the UI).
int surveyLineCount(List<GeoPoint> polygon, {required double spacing, double angleDeg = 0}) {
  if (polygon.length < 3 || spacing <= 0) return 0;
  final f = LocalFrame(centroid(polygon));
  final a = angleDeg * math.pi / 180;
  var lo = double.infinity, hi = -double.infinity;
  for (final p in polygon) {
    final (x, y) = f.toLocal(p);
    final v = x * math.cos(a) - y * math.sin(a);
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  return math.max(1, ((hi - lo) / spacing - 1e-6).ceil());
}

/// Most passes one survey may have.
const maxSurveyLines = 2000;

/// Lawn‑mower passes over [polygon]: lines along bearing [angleDeg],
/// [spacing] apart, the first and last half a spacing inside the boundary
/// (so the swath edge meets the boundary). Concave shapes give several
/// pieces per line; each piece is its own pass, so the payload is off over
/// the gaps. Passes alternate direction.
///
/// [startNear]: choose whichever of the four corners is closest to this
/// point as the start. Otherwise [reverse] picks the other end.
List<Pass> surveyPasses(
  List<GeoPoint> polygon, {
  required double spacing,
  double angleDeg = 0,
  double overshoot = 0,
  bool reverse = false,
  GeoPoint? startNear,
}) {
  if (polygon.length < 3 || spacing <= 0) return const [];
  final f = LocalFrame(centroid(polygon));
  final a = angleDeg * math.pi / 180;
  final d = (math.sin(a), math.cos(a)); // along the passes (east, north)
  final n = (math.cos(a), -math.sin(a)); // across
  double along(_V p) => p.$1 * d.$1 + p.$2 * d.$2;
  double across(_V p) => p.$1 * n.$1 + p.$2 * n.$2;
  _V back(double u, double v) => _add(_mul(d, u), _mul(n, v));

  final pts = [for (final p in polygon) f.toLocal(p)];
  final uv = [for (final p in pts) (along(p), across(p))];
  final vMin = uv.map((p) => p.$2).reduce(math.min), vMax = uv.map((p) => p.$2).reduce(math.max);
  final width = vMax - vMin;
  final lineVs = <double>[];
  if (width <= spacing) {
    lineVs.add((vMin + vMax) / 2);
  } else {
    // Tolerance: a 60.0000001 m width at 20 m spacing is still 3 passes.
    final count = (width / spacing - 1e-6).ceil();
    // Centre the set so the leftover is split between both sides.
    final first = vMin + (width - (count - 1) * spacing) / 2;
    for (var k = 0; k < count; k++) {
      lineVs.add(first + k * spacing);
    }
  }

  // Each line → sorted pieces [u0,u1] inside the polygon.
  final lines = <List<(double, double)>>[];
  for (final v in lineVs) {
    final xs = <double>[];
    for (var i = 0; i < uv.length; i++) {
      final p = uv[i], q = uv[(i + 1) % uv.length];
      if ((p.$2 <= v && q.$2 > v) || (q.$2 <= v && p.$2 > v)) {
        xs.add(p.$1 + (v - p.$2) * (q.$1 - p.$1) / (q.$2 - p.$2));
      }
    }
    xs.sort();
    final pieces = <(double, double)>[];
    for (var i = 0; i + 1 < xs.length; i += 2) {
      if (xs[i + 1] - xs[i] > 0.1) pieces.add((xs[i], xs[i + 1]));
    }
    lines.add(pieces);
  }

  List<Pass> build(bool reverseOrder, bool firstBackward) {
    final order = reverseOrder ? lines.reversed.toList() : lines;
    final orderV = reverseOrder ? lineVs.reversed.toList() : lineVs;
    final out = <Pass>[];
    var backward = firstBackward;
    for (var k = 0; k < order.length; k++) {
      if (order[k].isEmpty) continue;
      final pieces = backward ? order[k].reversed : order[k];
      for (final (u0, u1) in pieces) {
        final (s, e) = backward ? (u1, u0) : (u0, u1);
        final dir = backward ? -1.0 : 1.0;
        final v = orderV[k];
        GeoPoint g(double u) {
          final p = back(u, v);
          return f.toGeo(p.$1, p.$2);
        }

        out.add(
          Pass(
            overshoot > 0 ? g(s - dir * overshoot) : g(s),
            g(s),
            g(e),
            overshoot > 0 ? g(e + dir * overshoot) : g(e),
          ),
        );
      }
      backward = !backward;
    }
    return out;
  }

  if (startNear != null) {
    List<Pass>? best;
    var bestD = double.infinity;
    for (final r in [false, true]) {
      for (final b in [false, true]) {
        final p = build(r, b);
        if (p.isEmpty) continue;
        final dist = haversineMetres(startNear, p.first.entry);
        if (dist < bestD) {
          bestD = dist;
          best = p;
        }
      }
    }
    return best ?? const [];
  }
  return build(reverse, reverse);
}

/// One corridor lane: the payload works along [points]; [entry]/[exit] add
/// the run‑in/run‑out (equal to the first/last point without overshoot).
final class Lane {
  const Lane(this.entry, this.points, this.exit);
  final GeoPoint entry, exit;
  final List<GeoPoint> points;
}

/// Corridor lanes: the [path] offset sideways to fill [width], one lane per
/// [spacing], flown back and forth.
List<Lane> corridorLanes(List<GeoPoint> path, {required double width, required double spacing, double overshoot = 0}) {
  if (path.length < 2) return const [];
  final f = LocalFrame(centroid(path));
  final pts = [for (final p in path) f.toLocal(p)];
  final lanes = spacing <= 0 ? 1 : (width / spacing - 1e-6).ceil().clamp(1, 100);
  GeoPoint g(_V v) => f.toGeo(v.$1, v.$2);
  return [
    for (var k = 0; k < lanes; k++)
      () {
        var lane = _offsetPolyline(pts, (k - (lanes - 1) / 2) * spacing);
        if (lane.length < 2) return null;
        if (k.isOdd) lane = lane.reversed.toList();
        final entry = overshoot > 0 ? _sub(lane.first, _mul(_unit(_sub(lane[1], lane.first)), overshoot)) : lane.first;
        final exit = overshoot > 0
            ? _add(lane.last, _mul(_unit(_sub(lane.last, lane[lane.length - 2])), overshoot))
            : lane.last;
        return Lane(g(entry), [for (final v in lane) g(v)], g(exit));
      }(),
  ].nonNulls.toList();
}

/// The path shifted sideways by [offset] m (positive = right of travel).
///
/// Gentle bends get a mitred corner. On the outside of a sharp bend the lane
/// follows an arc round the corner (a mitre would spike far out). On the
/// inside, the lane is trimmed to the parts that keep their offset from the
/// path, so it never loops back across the centre line; where a hairpin is
/// narrower than the lane's offset, that stretch of lane is dropped.
List<_V> _offsetPolyline(List<_V> path, double offset) {
  // Repeated points have no direction.
  final pts = <_V>[];
  for (final v in path) {
    if (pts.isEmpty || _len(_sub(v, pts.last)) > 0.01) pts.add(v);
  }
  if (offset == 0 || pts.length < 2) return pts;
  _V normal(_V t) => (t.$2, -t.$1); // right of travel
  final out = <_V>[];
  final src = <int>[]; // path vertex each output point came from
  final arc = <bool>[]; // point k → k+1 is a chord of a corner arc
  void put(_V v, int i, {bool arcNext = false}) {
    out.add(v);
    src.add(i);
    arc.add(arcNext);
  }

  for (var i = 0; i < pts.length; i++) {
    if (i == 0 || i == pts.length - 1) {
      final t = i == 0 ? _sub(pts[1], pts[0]) : _sub(pts[i], pts[i - 1]);
      put(_add(pts[i], _mul(normal(_unit(t)), offset)), i);
      continue;
    }
    final t1 = _unit(_sub(pts[i], pts[i - 1])), t2 = _unit(_sub(pts[i + 1], pts[i]));
    final n1 = normal(t1), n2 = normal(t2);
    final cosTurn = t1.$1 * t2.$1 + t1.$2 * t2.$2;
    // Left turns are positive; a full reversal counts as a left turn.
    final turn = _cross(t1, t2).abs() < 1e-9 ? (cosTurn < 0 ? 1.0 : 0.0) : _cross(t1, t2);
    if (cosTurn > 0.5) {
      // Up to 60°: a mitre, at most 1.15 × the offset out.
      final m = _unit(_add(n1, n2));
      final cosHalf = m.$1 * n1.$1 + m.$2 * n1.$2;
      put(_add(pts[i], _mul(m, offset / cosHalf)), i);
    } else if (turn * offset > 0) {
      // Outside of a sharp bend: arc round the corner in ≤30° steps.
      final r = offset.abs(), dir = turn > 0 ? 1.0 : -1.0;
      final v1 = _mul(n1, offset), v2 = _mul(n2, offset);
      final a1 = math.atan2(v1.$2, v1.$1);
      var sweep = math.atan2(v2.$2, v2.$1) - a1;
      while (sweep * dir < 0) {
        sweep += 2 * math.pi * dir;
      }
      final steps = (sweep.abs() / (math.pi / 6)).ceil().clamp(1, 12);
      for (var k = 0; k <= steps; k++) {
        final a = a1 + sweep * k / steps;
        put(_add(pts[i], (r * math.cos(a), r * math.sin(a))), i, arcNext: k < steps);
      }
    } else {
      // Inside of a sharp bend: both shifted ends; the crossing is cut below.
      put(_add(pts[i], _mul(n1, offset)), i);
      put(_add(pts[i], _mul(n2, offset)), i);
    }
  }
  return _trimToOffset(out, src, arc, pts, offset.abs());
}

/// Keeps the parts of [lane] at least [offset] from the [path] segments
/// next to where each part came from ([src] = path vertex per lane point).
/// Only nearby segments count, so a corridor that crosses itself further
/// along keeps both passes. The kept parts are joined in order. Chords of
/// the ≤30° corner arcs ([arc]) dip up to 1 − cos 15° (3.4 %) inside the
/// offset by construction, so they get that much leeway.
List<_V> _trimToOffset(List<_V> lane, List<int> src, List<bool> arc, List<_V> path, double offset) {
  double distNear(_V p, int from, int to) {
    var best = double.infinity;
    for (var i = math.max(0, from - 2); i <= math.min(path.length - 2, to + 1); i++) {
      final a = path[i], d = _sub(path[i + 1], a);
      final t = ((_sub(p, a).$1 * d.$1 + _sub(p, a).$2 * d.$2) / (d.$1 * d.$1 + d.$2 * d.$2)).clamp(0.0, 1.0);
      best = math.min(best, _len(_sub(p, _add(a, _mul(d, t)))));
    }
    return best;
  }

  final runs = <List<_V>>[];
  List<_V>? run;
  final step = math.max(0.25, offset / 8);
  for (var i = 0; i + 1 < lane.length; i++) {
    final a = lane[i], ab = _sub(lane[i + 1], a);
    final lo = math.min(src[i], src[i + 1]), hi = math.max(src[i], src[i + 1]);
    _V pt(double t) => _add(a, _mul(ab, t));
    final need = (arc[i] ? offset * math.cos(math.pi / 12) : offset) - 0.01;
    bool ok(double t) => distNear(pt(t), lo, hi) >= need;
    var prevOk = ok(0);
    if (run != null && !prevOk) {
      runs.add(run);
      run = null;
    } else if (run == null && prevOk) {
      run = [a];
    }
    final steps = math.max(1, (_len(ab) / step).ceil());
    var prevT = 0.0;
    for (var k = 1; k <= steps; k++) {
      final t = k / steps, cur = ok(t);
      if (cur != prevOk) {
        // The edge of the valid part, found by bisection.
        var good = prevT, bad = t;
        for (var it = 0; it < 30; it++) {
          final m = (good + bad) / 2;
          if (ok(m) == prevOk) {
            good = m;
          } else {
            bad = m;
          }
        }
        final x = pt((good + bad) / 2);
        if (prevOk) {
          runs.add(run!..add(x));
          run = null;
        } else {
          run = [x];
        }
      }
      prevT = t;
      prevOk = cur;
    }
    if (prevOk) run!.add(lane[i + 1]);
  }
  if (run != null) runs.add(run);
  double length(List<_V> r) {
    var l = 0.0;
    for (var i = 0; i + 1 < r.length; i++) {
      l += _len(_sub(r[i + 1], r[i]));
    }
    return l;
  }

  final out = <_V>[];
  for (final r in runs.where((r) => length(r) >= 0.5)) {
    for (final v in r) {
      // Parts meeting at an inner corner share their end point.
      if (out.isEmpty || _len(_sub(v, out.last)) > 0.05) out.add(v);
    }
  }
  return out;
}

/// Orbit vertices: [legs]+1 points around [center] at [radius], from
/// [startBearing], clockwise or not, covering [sweepDeg] in equal legs no
/// larger than [resolutionDeg].
List<GeoPoint> orbitPoints(
  GeoPoint center, {
  required double radius,
  double startBearing = 0,
  double sweepDeg = 360,
  bool clockwise = true,
  double resolutionDeg = 15,
}) {
  final legs = (sweepDeg / resolutionDeg.clamp(1, 90)).ceil().clamp(1, 1000);
  final step = sweepDeg / legs * (clockwise ? 1 : -1);
  return [for (var k = 0; k <= legs; k++) destination(center, startBearing + k * step, radius)];
}
