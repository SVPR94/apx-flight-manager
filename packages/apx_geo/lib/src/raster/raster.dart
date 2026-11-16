// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;
import 'dart:typed_data';

import '../geo/geo_point.dart';
import '../geo/mercator.dart';

/// An 8‑bit RGBA image held in memory, row‑major, no padding.
final class RgbaRaster {
  RgbaRaster(this.width, this.height, [Uint8List? pixels]) : pixels = pixels ?? Uint8List(width * height * 4) {
    if (this.pixels.length != width * height * 4) throw ArgumentError('RGBA buffer size does not match $width×$height');
  }

  final int width, height;
  final Uint8List pixels;

  bool get isEmpty {
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] != 0) return false;
    }
    return true;
  }

  /// Copies [src] into this raster with its top‑left at ([dx], [dy]).
  void blit(RgbaRaster src, int dx, int dy) {
    for (var y = 0; y < src.height; y++) {
      final ty = y + dy;
      if (ty < 0 || ty >= height) continue;
      for (var x = 0; x < src.width; x++) {
        final tx = x + dx;
        if (tx < 0 || tx >= width) continue;
        final s = (y * src.width + x) * 4, d = (ty * width + tx) * 4;
        pixels.setRange(d, d + 4, src.pixels, s);
      }
    }
  }

  /// Bilinear sample at continuous coordinates where pixel (i, j) covers
  /// [i, i+1) × [j, j+1). Outside the raster is transparent. Colour is
  /// weighted by alpha so transparent neighbours don't darken edges.
  void sampleInto(double x, double y, Uint8List out, int o) {
    final fx = x - 0.5, fy = y - 0.5;
    if (fx < -0.5 || fy < -0.5 || fx > width - 0.5 || fy > height - 0.5) {
      out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0;
      return;
    }
    final x0 = fx.floor(), y0 = fy.floor();
    final ax = fx - x0, ay = fy - y0;
    var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
    for (var k = 0; k < 4; k++) {
      final xi = x0 + (k & 1), yi = y0 + (k >> 1);
      final w = ((k & 1) == 1 ? ax : 1 - ax) * ((k >> 1) == 1 ? ay : 1 - ay);
      if (w == 0) continue;
      final cx = xi.clamp(0, width - 1), cy = yi.clamp(0, height - 1);
      final i = (cy * width + cx) * 4;
      final wa = w * pixels[i + 3];
      r += pixels[i] * wa;
      g += pixels[i + 1] * wa;
      b += pixels[i + 2] * wa;
      a += wa;
    }
    if (a <= 0) {
      out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0;
      return;
    }
    out[o] = (r / a).round();
    out[o + 1] = (g / a).round();
    out[o + 2] = (b / a).round();
    out[o + 3] = a.round().clamp(0, 255);
  }

  /// Halves a 2×2 block of equal‑size tiles into one (box filter, alpha
  /// weighted). Null quadrants count as transparent.
  static RgbaRaster downsample2x2(List<RgbaRaster?> quads, int size) {
    final out = RgbaRaster(size, size);
    final half = size ~/ 2;
    for (var q = 0; q < 4; q++) {
      final src = quads[q];
      if (src == null) continue;
      final ox = (q & 1) * half, oy = (q >> 1) * half;
      for (var y = 0; y < half; y++) {
        for (var x = 0; x < half; x++) {
          var r = 0, g = 0, b = 0, a = 0;
          for (var k = 0; k < 4; k++) {
            final i = ((2 * y + (k >> 1)) * size + 2 * x + (k & 1)) * 4;
            final pa = src.pixels[i + 3];
            r += src.pixels[i] * pa;
            g += src.pixels[i + 1] * pa;
            b += src.pixels[i + 2] * pa;
            a += pa;
          }
          final o = ((oy + y) * size + ox + x) * 4;
          if (a == 0) continue;
          out.pixels[o] = r ~/ a;
          out.pixels[o + 1] = g ~/ a;
          out.pixels[o + 2] = b ~/ a;
          out.pixels[o + 3] = (a + 2) ~/ 4;
        }
      }
    }
    return out;
  }
}

/// Maps a WGS‑84 position to continuous source‑pixel coordinates (same
/// convention as [RgbaRaster.sampleInto]); null where the source has no
/// answer (e.g. behind a perspective horizon).
typedef PixelLocator = (double, double)? Function(GeoPoint p);

/// Where every pixel of one output Web‑Mercator tile comes from in a source
/// image. The exact mapping is evaluated on a grid every [step] pixels and
/// bilinearly interpolated between: all the mappings used here (UTM,
/// homographies, China datums) are smooth, so the interpolation error at
/// step 16 is far below a pixel.
final class TileWarp {
  TileWarp(this.tile, PixelLocator locate, {this.step = 16}) : _grid = _sample(tile, locate, step);

  final TileId tile;
  final int step;
  final List<(double, double)?> _grid;

  int get _n => tileSize ~/ step + 1;

  static List<(double, double)?> _sample(TileId tile, PixelLocator locate, int step) {
    final n = tileSize ~/ step + 1;
    final ox = tile.x * tileSize.toDouble(), oy = tile.y * tileSize.toDouble();
    return [
      for (var j = 0; j < n; j++)
        for (var i = 0; i < n; i++) locate(WebMercator.fromPixel(ox + i * step, oy + j * step, tile.z)),
    ];
  }

  /// Bounding box of the source coordinates this tile reads, or null if the
  /// tile maps entirely outside the source.
  (double, double, double, double)? get sourceBounds {
    var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (final p in _grid) {
      if (p == null) continue;
      x0 = math.min(x0, p.$1);
      y0 = math.min(y0, p.$2);
      x1 = math.max(x1, p.$1);
      y1 = math.max(y1, p.$2);
    }
    return x0 > x1 ? null : (x0, y0, x1, y1);
  }

  /// Renders the tile from [src], whose pixel (0,0) sits at source
  /// coordinate ([offsetX], [offsetY]).
  RgbaRaster render(RgbaRaster src, {double offsetX = 0, double offsetY = 0}) {
    final out = RgbaRaster(tileSize, tileSize);
    final n = _n;
    for (var py = 0; py < tileSize; py++) {
      // Sample at pixel centres.
      final gy = (py + 0.5) / step;
      final j = gy.floor().clamp(0, n - 2);
      final ty = gy - j;
      for (var px = 0; px < tileSize; px++) {
        final gx = (px + 0.5) / step;
        final i = gx.floor().clamp(0, n - 2);
        final tx = gx - i;
        final a = _grid[j * n + i],
            b = _grid[j * n + i + 1],
            c = _grid[(j + 1) * n + i],
            d = _grid[(j + 1) * n + i + 1];
        final o = (py * tileSize + px) * 4;
        if (a == null || b == null || c == null || d == null) continue;
        final sx = (a.$1 * (1 - tx) + b.$1 * tx) * (1 - ty) + (c.$1 * (1 - tx) + d.$1 * tx) * ty;
        final sy = (a.$2 * (1 - tx) + b.$2 * tx) * (1 - ty) + (c.$2 * (1 - tx) + d.$2 * tx) * ty;
        src.sampleInto(sx - offsetX, sy - offsetY, out.pixels, o);
      }
    }
    return out;
  }
}
