// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../geo/crs.dart';
import '../geo/geo_point.dart';
import '../raster/geo_raster.dart';
import '../raster/raster.dart';

/// Georeferencing read from a GeoTIFF's tags.
final class GeoTiffInfo {
  GeoTiffInfo({required this.width, required this.height, required this.crs, required this.affine, this.noData});

  final int width, height;
  final Crs crs;

  /// Pixel‑corner (col, row) → model (x, y): [a, b, c, d, e, f] with
  /// x = a·col + b·row + c, y = d·col + e·row + f.
  final List<double> affine;
  final double? noData;

  (double, double) toModel(double col, double row) {
    final [a, b, c, d, e, f] = affine;
    return (a * col + b * row + c, d * col + e * row + f);
  }

  (double, double)? toPixel(double x, double y) {
    final [a, b, c, d, e, f] = affine;
    final det = a * e - b * d;
    if (det == 0) return null;
    final dx = x - c, dy = y - f;
    return ((e * dx - b * dy) / det, (a * dy - d * dx) / det);
  }

  GeoPoint pixelToWgs84(double col, double row) {
    final (x, y) = toModel(col, row);
    return crs.toWgs84(x, y);
  }
}

/// Reads GeoTIFF files (classic TIFF, any compression the `image` package
/// decodes: none, LZW, Deflate, PackBits, JPEG).
///
/// Not supported, with a clear error: BigTIFF (files over 4 GB), geocentric
/// models, and user‑defined projections that aren't recognisable from their
/// citation. Very large images are decoded whole, so memory is the limit
/// (an 8000 × 8000 RGBA image needs about 256 MB).
abstract final class GeoTiff {
  static const _modelPixelScale = 33550;
  static const _modelTiepoint = 33922;
  static const _modelTransformation = 34264;
  static const _geoKeyDirectory = 34735;
  static const _geoAsciiParams = 34737;
  static const _gdalNoData = 42113;

  /// Reads only the georeference (cheap: no pixel decoding).
  static GeoTiffInfo readInfo(Uint8List bytes) {
    final t = _TiffTags.parse(bytes);
    final width = t.ints(256)?.first, height = t.ints(257)?.first;
    if (width == null || height == null) throw const FormatException('TIFF has no image dimensions');

    final keys = _geoKeys(t);
    final modelType = keys[1024];
    final rasterType = keys[1025] ?? 1;
    final crs = _crs(keys, modelType, t.ascii(_geoAsciiParams) ?? '');

    List<double> affine;
    final transform = t.doubles(_modelTransformation);
    final tie = t.doubles(_modelTiepoint), scale = t.doubles(_modelPixelScale);
    if (transform != null && transform.length >= 16) {
      affine = [transform[0], transform[1], transform[3], transform[4], transform[5], transform[7]];
    } else if (tie != null && tie.length >= 6 && scale != null && scale.length >= 2) {
      final (i, j, x, y, sx, sy) = (tie[0], tie[1], tie[3], tie[4], scale[0], scale[1]);
      affine = [sx, 0, x - i * sx, 0, -sy, y + j * sy];
    } else {
      throw const FormatException('TIFF has no georeference (no ModelTransformation or tiepoint + pixel scale)');
    }
    if (rasterType == 2) {
      // PixelIsPoint: the reference marks pixel centres; shift to corners.
      final [a, b, c, d, e, f] = affine;
      affine = [a, b, c - 0.5 * (a + b), d, e, f - 0.5 * (d + e)];
    }
    final nd = t.ascii(_gdalNoData);
    return GeoTiffInfo(
      width: width,
      height: height,
      crs: crs,
      affine: affine,
      noData: nd == null ? null : double.tryParse(nd.trim()),
    );
  }

  /// Decodes pixels and georeference.
  static GeoRaster read(Uint8List bytes) {
    final info = readInfo(bytes);
    final decoded = img.TiffDecoder().decode(bytes);
    if (decoded == null) throw const FormatException('Could not decode the TIFF pixels');
    final rgba = _toRgba(decoded, info.noData);

    final corners = [
      for (final (c, r) in [
        (0.0, 0.0),
        (info.width / 2, 0.0),
        (info.width.toDouble(), 0.0),
        (0.0, info.height / 2),
        (info.width.toDouble(), info.height / 2),
        (0.0, info.height.toDouble()),
        (info.width / 2, info.height.toDouble()),
        (info.width.toDouble(), info.height.toDouble()),
      ])
        info.pixelToWgs84(c, r),
    ];
    final mid = info.pixelToWgs84(info.width / 2, info.height / 2);
    final mpp =
        (haversineMetres(mid, info.pixelToWgs84(info.width / 2 + 1, info.height / 2)) +
            haversineMetres(mid, info.pixelToWgs84(info.width / 2, info.height / 2 + 1))) /
        2;

    return GeoRaster(
      image: rgba,
      bounds: GeoBounds.around(corners),
      metresPerPixel: mpp,
      locate: (p) {
        final (x, y) = info.crs.fromWgs84(p);
        return info.toPixel(x, y);
      },
    );
  }

  static Map<int, int> _geoKeys(_TiffTags t) {
    final dir = t.ints(_geoKeyDirectory);
    if (dir == null || dir.length < 4) return const {};
    final keys = <int, int>{};
    for (var k = 0; k < dir[3] && 4 + k * 4 + 3 < dir.length; k++) {
      final id = dir[4 + k * 4], loc = dir[4 + k * 4 + 1], value = dir[4 + k * 4 + 3];
      if (loc == 0) keys[id] = value;
    }
    return keys;
  }

  static Crs _crs(Map<int, int> keys, int? modelType, String citations) {
    final code = modelType == 2 ? keys[2048] : keys[3072];
    if (modelType == 3) throw const FormatException('Geocentric GeoTIFFs are not supported');
    if (code != null && code != 32767) {
      final known = Crs.fromEpsg(code);
      if (known != null) return known;
      throw FormatException(
        'GeoTIFF uses EPSG:$code, which isn\'t built in. Re‑export it as EPSG:4326, 3857 or WGS 84 / UTM.',
      );
    }
    if (modelType == 2) return Crs.wgs84; // geographic, datum not given as EPSG → WGS‑84
    // User‑defined: GDAL still writes a citation such as "WGS 84 / UTM zone 43N".
    for (final c in citations.split('|')) {
      try {
        if (c.trim().isNotEmpty) return Crs.parse(c.trim());
      } on FormatException {
        // try the next citation
      } catch (_) {}
    }
    throw const FormatException(
      'GeoTIFF has a user‑defined projection. Re‑export it as EPSG:4326, 3857 or WGS 84 / UTM.',
    );
  }

  /// Converts any decoded image to RGBA8. 8‑bit data is used as is; deeper or
  /// floating‑point data (elevation models, 16‑bit imagery) is stretched
  /// between its 2nd and 98th percentiles. [noData] pixels become transparent.
  static RgbaRaster _toRgba(img.Image src, double? noData) {
    final w = src.width, h = src.height;
    final out = RgbaRaster(w, h);
    final px = out.pixels;
    final nc = src.numChannels;
    final deep = src.format != img.Format.uint8;

    if (!deep) {
      final rgba = src.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
      px.setAll(0, rgba.getBytes(order: img.ChannelOrder.rgba));
      if (noData != null) {
        final nd = noData.round();
        var i = 0;
        for (final p in src) {
          final isNd = nc >= 3 ? (p.r == nd && p.g == nd && p.b == nd) : p.r == nd;
          if (isNd) px[i + 3] = 0;
          i += 4;
        }
      }
      return out;
    }

    final channels = nc >= 3 ? 3 : 1;
    final lo = List<double>.filled(channels, 0), hi = List<double>.filled(channels, 1);
    for (var c = 0; c < channels; c++) {
      final samples = <double>[];
      final stride = ((w * h) / 200000).ceil().clamp(1, 1 << 30);
      var k = 0;
      for (final p in src) {
        if (k++ % stride != 0) continue;
        final v = p[c].toDouble();
        if (v.isNaN || (noData != null && v == noData)) continue;
        samples.add(v);
      }
      if (samples.isEmpty) continue;
      samples.sort();
      lo[c] = samples[(samples.length * 0.02).floor()];
      hi[c] = samples[(samples.length * 0.98).floor().clamp(0, samples.length - 1)];
      if (hi[c] <= lo[c]) hi[c] = lo[c] + 1;
    }
    var i = 0;
    for (final p in src) {
      final v0 = p[0].toDouble();
      if (v0.isNaN || (noData != null && v0 == noData)) {
        i += 4;
        continue;
      }
      for (var c = 0; c < 3; c++) {
        final ch = channels == 1 ? 0 : c;
        final v = channels == 1 ? v0 : p[c].toDouble();
        px[i + c] = ((v - lo[ch]) / (hi[ch] - lo[ch]) * 255).round().clamp(0, 255);
      }
      px[i + 3] = nc == 4 || nc == 2 ? (p.aNormalized * 255).round().clamp(0, 255) : 255;
      i += 4;
    }
    return out;
  }
}

/// Minimal reader for the first IFD of a classic TIFF: just enough to fetch
/// the georeferencing tags. Pixels are left to the `image` package.
final class _TiffTags {
  _TiffTags._(this._d, this._endian, this._entries);

  final ByteData _d;
  final Endian _endian;
  final Map<int, (int type, int count, int offset)> _entries;

  factory _TiffTags.parse(Uint8List bytes) {
    if (bytes.length < 8) throw const FormatException('Not a TIFF file');
    final d = ByteData.sublistView(bytes);
    final Endian e;
    if (bytes[0] == 0x49 && bytes[1] == 0x49) {
      e = Endian.little;
    } else if (bytes[0] == 0x4D && bytes[1] == 0x4D) {
      e = Endian.big;
    } else {
      throw const FormatException('Not a TIFF file');
    }
    final magic = d.getUint16(2, e);
    if (magic == 43)
      throw const FormatException(
        'BigTIFF (files over 4 GB) is not supported yet. Save as a classic TIFF or tile it smaller.',
      );
    if (magic != 42) throw const FormatException('Not a TIFF file');
    final ifd = d.getUint32(4, e);
    if (ifd + 2 > bytes.length) throw const FormatException('TIFF directory is outside the file');
    final n = d.getUint16(ifd, e);
    final entries = <int, (int, int, int)>{};
    for (var i = 0; i < n; i++) {
      final o = ifd + 2 + i * 12;
      if (o + 12 > bytes.length) break;
      final tag = d.getUint16(o, e), type = d.getUint16(o + 2, e), count = d.getUint32(o + 4, e);
      final size = (_typeSize[type] ?? 1) * count;
      entries[tag] = (type, count, size <= 4 ? o + 8 : d.getUint32(o + 8, e));
    }
    return _TiffTags._(d, e, entries);
  }

  static const _typeSize = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8};

  List<int>? ints(int tag) {
    final en = _entries[tag];
    if (en == null) return null;
    final (type, count, off) = en;
    if (off + count * (_typeSize[type] ?? 1) > _d.lengthInBytes) return null;
    return [
      for (var i = 0; i < count; i++)
        switch (type) {
          1 || 7 => _d.getUint8(off + i),
          3 => _d.getUint16(off + i * 2, _endian),
          4 => _d.getUint32(off + i * 4, _endian),
          8 => _d.getInt16(off + i * 2, _endian),
          9 => _d.getInt32(off + i * 4, _endian),
          _ => 0,
        },
    ];
  }

  List<double>? doubles(int tag) {
    final en = _entries[tag];
    if (en == null) return null;
    final (type, count, off) = en;
    if (off + count * (_typeSize[type] ?? 1) > _d.lengthInBytes) return null;
    return [
      for (var i = 0; i < count; i++)
        switch (type) {
          12 => _d.getFloat64(off + i * 8, _endian),
          11 => _d.getFloat32(off + i * 4, _endian),
          5 => _d.getUint32(off + i * 8, _endian) / _d.getUint32(off + i * 8 + 4, _endian),
          _ => (ints(tag)?[i] ?? 0).toDouble(),
        },
    ];
  }

  String? ascii(int tag) {
    final en = _entries[tag];
    if (en == null || en.$1 != 2) return null;
    final (_, count, off) = en;
    if (off + count > _d.lengthInBytes) return null;
    final chars = _d.buffer.asUint8List(_d.offsetInBytes + off, count);
    final end = chars.indexOf(0);
    return String.fromCharCodes(end < 0 ? chars : chars.sublist(0, end));
  }
}
