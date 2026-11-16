// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import '../geo/geo_point.dart';
import '../geo/mercator.dart';
import 'raster.dart';

/// A decoded image with a georeference: everything the pyramid builder needs
/// to draw it on the map.
final class GeoRaster {
  GeoRaster({required this.image, required this.locate, required this.bounds, required this.metresPerPixel});

  final RgbaRaster image;

  /// WGS‑84 → source pixel.
  final PixelLocator locate;

  /// WGS‑84 extent of the image.
  final GeoBounds bounds;

  /// Approximate ground size of one source pixel.
  final double metresPerPixel;

  /// The zoom whose map pixels are about as fine as the source's, so the
  /// deepest tiles neither waste space nor throw detail away.
  int get nativeZoom {
    final lat = bounds.center.lat;
    final z = (math.log(WebMercator.metresPerPixel(lat, 0) / metresPerPixel) / math.ln2).ceil();
    return z.clamp(1, 23);
  }

  /// The coarsest zoom worth drawing: where the whole image is a few pixels.
  int get minZoom => math.max(0, nativeZoom - 12);
}

/// Something the pyramid writes finished tiles to (the tile cache).
abstract interface class TileSink {
  void put(TileId tile, RgbaRaster pixels);
}

/// Progress of [buildPyramid]: tiles done out of the estimated total.
typedef PyramidProgress = void Function(int done, int total);

/// Renders [raster] into Web‑Mercator tiles from [GeoRaster.nativeZoom] down to
/// [GeoRaster.minZoom]. The deepest level is reprojected per pixel from the
/// source; each coarser level is box‑filtered from its four children, which
/// keeps low zooms free of aliasing. Depth‑first, so memory stays at a few
/// tiles per level whatever the image size. Empty tiles are not stored.
///
/// Returns the number of tiles written.
int buildPyramid(GeoRaster raster, TileSink sink, {int? maxZoom, PyramidProgress? progress}) {
  final top = maxZoom ?? raster.nativeZoom;
  final bottom = math.min(raster.minZoom, top);
  var total = 0;
  for (var z = bottom; z <= top; z++) {
    total += WebMercator.countTiles(raster.bounds, z, z);
  }
  var done = 0, written = 0;

  RgbaRaster? render(TileId t) {
    if (!t.bounds.intersects(raster.bounds)) return null;
    RgbaRaster? out;
    if (t.z == top) {
      final warp = TileWarp(t, raster.locate);
      if (warp.sourceBounds != null) out = warp.render(raster.image);
    } else {
      final kids = [for (final c in t.children) render(c)];
      if (kids.any((k) => k != null)) out = RgbaRaster.downsample2x2(kids, tileSize);
    }
    done++;
    progress?.call(math.min(done, total), total);
    if (out == null || out.isEmpty) return null;
    sink.put(t, out);
    written++;
    return out;
  }

  for (final t in WebMercator.tilesCovering(raster.bounds, bottom)) {
    render(t);
  }
  return written;
}
