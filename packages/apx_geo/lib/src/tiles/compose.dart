// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../geo/china.dart';
import '../geo/mercator.dart';
import '../raster/raster.dart';
import 'provider.dart';

/// Which provider tiles cover one output tile, and how they are laid out.
final class SourceFootprint {
  const SourceFootprint(this.level, this.col0, this.row0, this.cols, this.rows);

  /// Provider zoom level.
  final int level;

  /// Top‑left source tile, in a y‑down grid (for Baidu, the provider's own
  /// y is `-row - 1`).
  final int col0, row0, cols, rows;

  Iterable<(int, int)> get cells sync* {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        yield (col0 + c, row0 + r);
      }
    }
  }
}

/// Maps WGS‑84 to continuous y‑down pixel coordinates in the provider's own
/// grid at [level].
PixelLocator providerLocator(MapDatum datum, TileGrid grid, int level) {
  switch (grid) {
    case TileGrid.webMercator:
      return (p) => WebMercator.toPixel(wgs84To(datum, p), level);
    case TileGrid.baidu:
      final res = BaiduMercator.unitsPerPixel(level);
      return (p) {
        final (mx, my) = BaiduMercator.fromBd09(wgs84To(datum, p));
        return (mx / res, -my / res);
      };
  }
}

/// Provider zoom level used to draw output zoom [z]: Baidu level L has
/// 2^(18−L) m/px against Web Mercator's ~156543/2^z, so L = z + 1 is the
/// first level at least as sharp.
int providerLevel(TileGrid grid, int z, int maxZoom) => switch (grid) {
  TileGrid.webMercator => math.min(z, maxZoom),
  TileGrid.baidu => (z + 1).clamp(3, maxZoom),
};

/// The source tiles needed to draw [t], or null if it falls outside the
/// provider's world.
SourceFootprint? footprint(TileId t, MapDatum datum, TileGrid grid, int maxZoom) {
  final level = providerLevel(grid, t.z, maxZoom);
  final warp = TileWarp(t, providerLocator(datum, grid, level));
  final b = warp.sourceBounds;
  if (b == null) return null;
  final (x0, y0, x1, y1) = b;
  final c0 = (x0 / tileSize).floor(), c1 = ((x1 - 1e-9) / tileSize).floor();
  final r0 = (y0 / tileSize).floor(), r1 = ((y1 - 1e-9) / tileSize).floor();
  final cols = c1 - c0 + 1, rows = r1 - r0 + 1;
  if (cols > 4 || rows > 4) return null; // only at world‑scale zooms, where offsets are meaningless
  return SourceFootprint(level, c0, r0, cols, rows);
}

/// Everything [composeTile] needs, in a form that crosses isolates.
final class ComposeJob {
  const ComposeJob({
    required this.z,
    required this.x,
    required this.y,
    required this.datum,
    required this.grid,
    required this.footprint,
    required this.base,
    this.labels,
    required this.jpeg,
    this.warp = true,
  });

  final int z, x, y;
  final MapDatum datum;
  final TileGrid grid;
  final SourceFootprint footprint;

  /// Encoded source tiles in [SourceFootprint.cells] order; null = missing.
  final List<Uint8List?> base;
  final List<Uint8List?>? labels;
  final bool jpeg;

  /// False when only labels are composited (grid already matches).
  final bool warp;
}

/// Decodes the source tiles, composites labels, reprojects to the output Web
/// Mercator tile and encodes it. Pure CPU work: run it on a background isolate.
Uint8List? composeTile(ComposeJob job) {
  final f = job.footprint;
  final mosaic = RgbaRaster(f.cols * tileSize, f.rows * tileSize);
  var any = false;
  for (var i = 0; i < job.base.length; i++) {
    final c = i % f.cols, r = i ~/ f.cols;
    final b = _decode(job.base[i]);
    if (b != null) {
      mosaic.blit(b, c * tileSize, r * tileSize);
      any = true;
    }
    final l = job.labels == null ? null : _decode(job.labels![i]);
    if (l != null) _over(mosaic, l, c * tileSize, r * tileSize);
  }
  if (!any) return null;

  final RgbaRaster out;
  if (job.warp) {
    final warp = TileWarp(TileId(job.z, job.x, job.y), providerLocator(job.datum, job.grid, f.level));
    out = warp.render(mosaic, offsetX: f.col0 * tileSize.toDouble(), offsetY: f.row0 * tileSize.toDouble());
  } else {
    out = mosaic;
  }
  return encodeTile(out, jpeg: job.jpeg);
}

Uint8List encodeTile(RgbaRaster r, {bool jpeg = false}) {
  final im = img.Image.fromBytes(
    width: r.width,
    height: r.height,
    bytes: r.pixels.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return jpeg ? img.encodeJpg(im, quality: 88) : img.encodePng(im, level: 4);
}

RgbaRaster? _decode(Uint8List? bytes) {
  if (bytes == null) return null;
  final im = img.decodeImage(bytes);
  if (im == null) return null;
  final c = im.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
  if (c.width != tileSize || c.height != tileSize) {
    final s = img.copyResize(c, width: tileSize, height: tileSize, interpolation: img.Interpolation.average);
    return RgbaRaster(tileSize, tileSize, Uint8List.fromList(s.getBytes(order: img.ChannelOrder.rgba)));
  }
  return RgbaRaster(tileSize, tileSize, Uint8List.fromList(c.getBytes(order: img.ChannelOrder.rgba)));
}

/// Source‑over alpha compositing of [top] onto [dst] at ([dx], [dy]).
void _over(RgbaRaster dst, RgbaRaster top, int dx, int dy) {
  for (var y = 0; y < top.height; y++) {
    for (var x = 0; x < top.width; x++) {
      final s = (y * top.width + x) * 4;
      final a = top.pixels[s + 3];
      if (a == 0) continue;
      final d = ((y + dy) * dst.width + x + dx) * 4;
      final da = dst.pixels[d + 3];
      final oa = a + da * (255 - a) ~/ 255;
      for (var k = 0; k < 3; k++) {
        dst.pixels[d + k] = oa == 0 ? 0 : (top.pixels[s + k] * a + dst.pixels[d + k] * da * (255 - a) ~/ 255) ~/ oa;
      }
      dst.pixels[d + 3] = oa;
    }
  }
}
