// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:typed_data';

import '../geo/mercator.dart';
import '../raster/geo_raster.dart';
import '../raster/raster.dart';
import '../tiles/compose.dart';
import '../tiles/tile_cache.dart';

/// Writes a raster overlay's tile pyramid into the tile cache (pinned, as
/// PNG for transparency), in batches so a cache shared with the running
/// tile server is only briefly locked.
///
/// CPU heavy: run on a background isolate with its own [TileCache.open] on
/// the same file.
int renderOverlayToCache(GeoRaster raster, TileCache cache, String sourceId, {PyramidProgress? progress}) {
  cache.clear(source: sourceId);
  final sink = _BatchSink(cache, sourceId);
  final n = buildPyramid(raster, sink, progress: progress);
  sink.flush();
  return n;
}

final class _BatchSink implements TileSink {
  _BatchSink(this.cache, this.source);
  final TileCache cache;
  final String source;
  final _batch = <(TileId, Uint8List, String)>[];

  @override
  void put(TileId tile, RgbaRaster pixels) {
    _batch.add((tile, encodeTile(pixels), 'image/png'));
    if (_batch.length >= 64) flush();
  }

  void flush() {
    if (_batch.isEmpty) return;
    cache.putAll(source, _batch);
    _batch.clear();
  }
}
