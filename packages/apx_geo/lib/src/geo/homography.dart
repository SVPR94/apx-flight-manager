// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
final class Homography {
  const Homography._(this.m);

  /// Row‑major 3×3 matrix.
  final List<double> m;

  /// The transform taking each of four [from] points to the matching [to]
  /// point. Throws if three of the points are collinear.
  factory Homography.fromPoints(List<(double, double)> from, List<(double, double)> to) {
    if (from.length != 4 || to.length != 4) throw ArgumentError('A homography needs exactly four point pairs');
    // Solve A·h = b for h = [h11 h12 h13 h21 h22 h23 h31 h32].
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final (x, y) = from[i];
      final (u, v) = to[i];
      a[2 * i]
        ..setAll(0, [x, y, 1, 0, 0, 0, -u * x, -u * y])
        ..[8] = u;
      a[2 * i + 1]
        ..setAll(0, [0, 0, 0, x, y, 1, -v * x, -v * y])
        ..[8] = v;
    }
    final h = _solve(a);
    return Homography._([...h, 1]);
  }

  (double, double) apply(double x, double y) {
    final w = m[6] * x + m[7] * y + m[8];
    return ((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w);
  }

  Homography inverse() {
    final [a, b, c, d, e, f, g, h, i] = m;
    final co = [
      e * i - f * h,
      c * h - b * i,
      b * f - c * e,
      f * g - d * i,
      a * i - c * g,
      c * d - a * f,
      d * h - e * g,
      b * g - a * h,
      a * e - b * d,
    ];
    final det = a * co[0] + b * co[3] + c * co[6];
    if (det.abs() < 1e-300) throw StateError('Homography is singular');
    final s = co[8] / det;
    return Homography._([for (final v in co) v / det / s]);
  }

  /// Gaussian elimination with partial pivoting on an n×(n+1) system.
  static List<double> _solve(List<List<double>> a) {
    final n = a.length;
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) throw ArgumentError('Corner points are degenerate (three in a line?)');
      final t = a[col];
      a[col] = a[pivot];
      a[pivot] = t;
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final k = a[r][col] / a[col][col];
        if (k == 0) continue;
        for (var c = col; c <= n; c++) {
          a[r][c] -= k * a[col][c];
        }
      }
    }
    return [for (var r = 0; r < n; r++) a[r][n] / a[r][r]];
  }
}
