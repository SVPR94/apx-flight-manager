// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;
import 'dart:ui';

/// Edits on an image overlay's four corners (top‑left, top‑right,
/// bottom‑right, bottom‑left), done in screen pixels. Web Mercator is
/// conformal, so rotating or moving sides on screen keeps the image's shape
/// on the ground.
abstract final class QuadEdit {
  /// Centre of the four corners.
  static Offset centre(List<Offset> q) => (q[0] + q[1] + q[2] + q[3]) / 4;

  /// Midpoint of side [side]: 0 top, 1 right, 2 bottom, 3 left (between
  /// corner `side` and the next one).
  static Offset sideMid(List<Offset> q, int side) => (q[side] + q[(side + 1) % 4]) / 2;

  /// Unit normal of [side], pointing away from the centre.
  static Offset outwardNormal(List<Offset> q, int side) {
    final a = q[side], b = q[(side + 1) % 4];
    final e = b - a;
    final len = e.distance;
    if (len == 0) return Offset.zero;
    var n = Offset(-e.dy, e.dx) / len;
    if ((sideMid(q, side) - centre(q)).dx * n.dx + (sideMid(q, side) - centre(q)).dy * n.dy < 0) n = -n;
    return n;
  }

  /// Moves one corner to [to].
  static List<Offset> moveCorner(List<Offset> q, int corner, Offset to) => [
    for (final (i, p) in q.indexed) i == corner ? to : p,
  ];

  /// Moves [side] parallel to itself by the part of [delta] along its normal,
  /// so the side keeps its direction and the image stretches or shrinks.
  static List<Offset> moveSide(List<Offset> q, int side, Offset delta) {
    final n = outwardNormal(q, side);
    final d = n * (delta.dx * n.dx + delta.dy * n.dy);
    return [for (final (i, p) in q.indexed) i == side || i == (side + 1) % 4 ? p + d : p];
  }

  /// Moves all four corners by [delta].
  static List<Offset> translate(List<Offset> q, Offset delta) => [for (final p in q) p + delta];

  /// Rotates all four corners about [about] by [radians] (clockwise on screen).
  static List<Offset> rotate(List<Offset> q, Offset about, double radians) {
    final c = math.cos(radians), s = math.sin(radians);
    return [
      for (final p in q)
        about + Offset((p.dx - about.dx) * c - (p.dy - about.dy) * s, (p.dx - about.dx) * s + (p.dy - about.dy) * c),
    ];
  }

  /// Angle turned at [about] going from [from] to [to], in (−π, π].
  static double turn(Offset about, Offset from, Offset to) {
    var a = (to - about).direction - (from - about).direction;
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a <= -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }
}
