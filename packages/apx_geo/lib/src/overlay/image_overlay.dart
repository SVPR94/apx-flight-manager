// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../geo/crs.dart';
import '../geo/geo_point.dart';
import '../geo/homography.dart';
import '../geo/mercator.dart';
import '../raster/geo_raster.dart';
import '../raster/raster.dart';

/// How a plain image (PNG/JPG) is placed on the map.
sealed class ImagePlacement {
  const ImagePlacement();

  /// The four image corners on the ground, in order top‑left, top‑right,
  /// bottom‑right, bottom‑left. Every placement reduces to this.
  List<GeoPoint> corners(int width, int height);

  Map<String, Object?> toJson();

  static ImagePlacement fromJson(Map<String, Object?> j) => switch (j['kind']) {
    'corners' => CornerPlacement([
      for (final c in (j['corners'] as List).cast<List>()) GeoPoint((c[0] as num).toDouble(), (c[1] as num).toDouble()),
    ]),
    'centre' => CentrePlacement(
      center: GeoPoint((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
      widthMetres: (j['width'] as num).toDouble(),
      heightMetres: (j['height'] as num).toDouble(),
      rotationDeg: (j['rotation'] as num?)?.toDouble() ?? 0,
    ),
    'worldfile' => WorldFilePlacement([
      for (final v in (j['params'] as List)) (v as num).toDouble(),
    ], crsDefinition: j['crs'] as String?),
    _ => throw FormatException('Unknown image placement ${j['kind']}'),
  };
}

/// Four ground corners → full perspective (homography) fit.
final class CornerPlacement extends ImagePlacement {
  CornerPlacement(this.points) {
    if (points.length != 4) throw ArgumentError('Corner placement needs four corners');
  }

  /// Top‑left, top‑right, bottom‑right, bottom‑left.
  final List<GeoPoint> points;

  @override
  List<GeoPoint> corners(int width, int height) => points;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'corners',
    'corners': [
      for (final p in points) [p.lat, p.lon],
    ],
  };
}

/// Centre, ground size and clockwise rotation from north.
final class CentrePlacement extends ImagePlacement {
  const CentrePlacement({
    required this.center,
    required this.widthMetres,
    required this.heightMetres,
    this.rotationDeg = 0,
  });

  final GeoPoint center;
  final double widthMetres, heightMetres, rotationDeg;

  @override
  List<GeoPoint> corners(int width, int height) {
    final hw = widthMetres / 2, hh = heightMetres / 2;
    final dist = math.sqrt(hw * hw + hh * hh);
    final a = math.atan2(hw, hh) * 180 / math.pi; // angle of the top‑right corner from "up"
    return [
      destination(center, rotationDeg - a, dist),
      destination(center, rotationDeg + a, dist),
      destination(center, rotationDeg + 180 - a, dist),
      destination(center, rotationDeg + 180 + a, dist),
    ];
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'centre',
    'lat': center.lat,
    'lon': center.lon,
    'width': widthMetres,
    'height': heightMetres,
    'rotation': rotationDeg,
  };
}

/// An ESRI world file (.pgw/.jgw/.wld): six lines A, D, B, E, C, F mapping
/// pixel centres to map coordinates, x = A·col + B·row + C, y = D·col + E·row + F.
/// Coordinates are in [crsDefinition] (a `.prj` WKT) or, without one,
/// geographic WGS‑84 when the numbers look like degrees.
final class WorldFilePlacement extends ImagePlacement {
  WorldFilePlacement(this.params, {this.crsDefinition}) {
    if (params.length != 6) throw const FormatException('A world file has six numbers');
  }

  factory WorldFilePlacement.parse(String text, {String? prj}) {
    final nums = [for (final l in text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) double.parse(l)];
    if (nums.length < 6) throw const FormatException('A world file has six numbers');
    return WorldFilePlacement(nums.sublist(0, 6), crsDefinition: prj);
  }

  /// A GDAL/QGIS sidecar (`image.png.aux.xml`, written by "Save as" PNG/JPEG
  /// exports): its GeoTransform and SRS WKT.
  factory WorldFilePlacement.fromAuxXml(String xml) {
    final gt = RegExp(r'<GeoTransform>([^<]+)</GeoTransform>').firstMatch(xml)?.group(1);
    if (gt == null) throw const FormatException('The .aux.xml has no GeoTransform (the image is not georeferenced).');
    final v = gt.split(',').map((s) => double.parse(s.trim())).toList();
    if (v.length != 6) throw const FormatException('The .aux.xml GeoTransform needs six numbers');
    final srs = RegExp(r'<SRS[^>]*>([^<]+)</SRS>').firstMatch(xml)?.group(1);
    String unescape(String s) => s
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    // GDAL's origin is the outer corner of the first pixel; a world file's
    // is that pixel's centre.
    final [x0, a, b, y0, d, e] = v;
    return WorldFilePlacement([
      a,
      d,
      b,
      e,
      x0 + a / 2 + b / 2,
      y0 + d / 2 + e / 2,
    ], crsDefinition: srs == null ? null : unescape(srs));
  }

  final List<double> params;
  final String? crsDefinition;

  Crs get crs {
    if (crsDefinition != null && crsDefinition!.trim().isNotEmpty) return Crs.parse(crsDefinition!);
    final [_, _, _, _, c, f] = params;
    if (c.abs() <= 180 && f.abs() <= 90) return Crs.wgs84;
    throw const FormatException(
      'This world file is in projected coordinates. Add the matching .prj file next to the image (same name).',
    );
  }

  @override
  List<GeoPoint> corners(int width, int height) {
    final [a, d, b, e, c, f] = params;
    final crs = this.crs;
    // Pixel centre (0,0) is at (C, F); corners sit half a pixel outside.
    GeoPoint at(double col, double row) =>
        crs.toWgs84(a * (col - 0.5) + b * (row - 0.5) + c, d * (col - 0.5) + e * (row - 0.5) + f);
    return [at(0, 0), at(width.toDouble(), 0), at(width.toDouble(), height.toDouble()), at(0, height.toDouble())];
  }

  @override
  Map<String, Object?> toJson() => {'kind': 'worldfile', 'params': params, 'crs': crsDefinition};
}

/// Plain images placed on the map.
abstract final class ImageOverlay {
  /// World‑file extensions to look for next to an image, most specific first.
  static List<String> worldFileExtensions(String imageExtension) {
    final e = imageExtension.toLowerCase().replaceFirst('.', '');
    final short = e.length >= 3 ? '${e[0]}${e[e.length - 1]}w' : '${e}w'; // png → pgw, jpg → jgw, jpeg → jgw
    return {'.$short', '.${e}w', '.wld'}.toList();
  }

  static RgbaRaster decode(Uint8List bytes) {
    final im = img.decodeImage(bytes);
    if (im == null) throw const FormatException('Not a PNG or JPEG image');
    final rgba = im.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
    return RgbaRaster(rgba.width, rgba.height, Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba)));
  }

  /// Places [image] by [placement]. The fit is a homography between image
  /// pixels and Web‑Mercator metres, so straight lines stay straight on the
  /// map and four‑corner placement keeps true perspective.
  static GeoRaster place(RgbaRaster image, ImagePlacement placement) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final corners = placement.corners(image.width, image.height);
    // Solve relative to the first corner: raw Mercator metres (~10⁷) would
    // make the 8×8 system badly conditioned.
    final (ox, oy) = WebMercator.toMetres(corners[0].lat, corners[0].lon);
    final ground = [
      for (final c in corners) (WebMercator.toMetres(c.lat, c.lon).$1 - ox, WebMercator.toMetres(c.lat, c.lon).$2 - oy),
    ];
    final toPixel = Homography.fromPoints(ground, [(0, 0), (w, 0), (w, h), (0, h)]);
    final toGround = toPixel.inverse();

    final (cx, cy) = toGround.apply(w / 2, h / 2);
    final (rx, ry) = toGround.apply(w / 2 + 1, h / 2);
    final centre = WebMercator.fromMetres(cx + ox, cy + oy);
    final mpp = haversineMetres(centre, WebMercator.fromMetres(rx + ox, ry + oy));
    final m = toPixel.m;
    final inside = (m[6] * cx + m[7] * cy + m[8]).sign;

    return GeoRaster(
      image: image,
      bounds: GeoBounds.around(corners),
      metresPerPixel: mpp,
      locate: (p) {
        final (x, y) = WebMercator.toMetres(p.lat, p.lon);
        final gx = x - ox, gy = y - oy;
        // Beyond the image's horizon the projective weight changes sign.
        if ((m[6] * gx + m[7] * gy + m[8]) * inside <= 0) return null;
        return toPixel.apply(gx, gy);
      },
    );
  }
}
