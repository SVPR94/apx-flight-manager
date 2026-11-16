// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'geo_point.dart';

/// Map datums a tile provider can draw in. Chinese map services are legally
/// required to offset their maps: GCJ‑02 (Gaode/AMap, Tencent, Google China)
/// and BD‑09 (Baidu, a further shift on top of GCJ‑02).
enum MapDatum { wgs84, gcj02, bd09 }

/// Converts WGS‑84 to the provider's datum. Outside mainland China every
/// datum equals WGS‑84.
GeoPoint wgs84To(MapDatum datum, GeoPoint p) => switch (datum) {
  MapDatum.wgs84 => p,
  MapDatum.gcj02 => wgs84ToGcj02(p),
  MapDatum.bd09 => gcj02ToBd09(wgs84ToGcj02(p)),
};

GeoPoint toWgs84From(MapDatum datum, GeoPoint p) => switch (datum) {
  MapDatum.wgs84 => p,
  MapDatum.gcj02 => gcj02ToWgs84(p),
  MapDatum.bd09 => gcj02ToWgs84(bd09ToGcj02(p)),
};

/// The coarse box the GCJ‑02 offset applies in (the published convention).
bool outOfChina(GeoPoint p) => p.lon < 72.004 || p.lon > 137.8347 || p.lat < 0.8293 || p.lat > 55.8271;

const _a = 6378245.0;
const _ee = 0.00669342162296594323;

GeoPoint wgs84ToGcj02(GeoPoint p) {
  if (outOfChina(p)) return p;
  final (dLat, dLon) = _delta(p.lat, p.lon);
  return GeoPoint(p.lat + dLat, p.lon + dLon);
}

/// Inverse of [wgs84ToGcj02] by fixed‑point iteration (the forward offset is
/// smooth, so this converges to well under a centimetre in a few steps).
GeoPoint gcj02ToWgs84(GeoPoint g) {
  if (outOfChina(g)) return g;
  var w = g;
  for (var i = 0; i < 6; i++) {
    final f = wgs84ToGcj02(w);
    final dLat = f.lat - g.lat, dLon = f.lon - g.lon;
    w = GeoPoint(w.lat - dLat, w.lon - dLon);
    if (dLat.abs() < 1e-10 && dLon.abs() < 1e-10) break;
  }
  return w;
}

(double, double) _delta(double lat, double lon) {
  final x = lon - 105.0, y = lat - 35.0;
  var dLat = _transformLat(x, y), dLon = _transformLon(x, y);
  final radLat = lat / 180 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - _ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
  dLon = (dLon * 180) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
  return (dLat, dLon);
}

double _transformLat(double x, double y) {
  var r = -100.0 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
  r += (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) * 2 / 3;
  r += (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3;
  r += (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) * 2 / 3;
  return r;
}

double _transformLon(double x, double y) {
  var r = 300.0 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
  r += (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) * 2 / 3;
  r += (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3;
  r += (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) * 2 / 3;
  return r;
}

const _xPi = math.pi * 3000.0 / 180.0;

GeoPoint gcj02ToBd09(GeoPoint g) {
  final x = g.lon, y = g.lat;
  final z = math.sqrt(x * x + y * y) + 0.00002 * math.sin(y * _xPi);
  final t = math.atan2(y, x) + 0.000003 * math.cos(x * _xPi);
  return GeoPoint(z * math.sin(t) + 0.006, z * math.cos(t) + 0.0065);
}

/// Inverse of [gcj02ToBd09]: the usual closed form, refined by iteration
/// (the closed form alone is off by up to ~10 cm).
GeoPoint bd09ToGcj02(GeoPoint b) {
  final x = b.lon - 0.0065, y = b.lat - 0.006;
  final z = math.sqrt(x * x + y * y) - 0.00002 * math.sin(y * _xPi);
  final t = math.atan2(y, x) - 0.000003 * math.cos(x * _xPi);
  var g = GeoPoint(z * math.sin(t), z * math.cos(t));
  for (var i = 0; i < 4; i++) {
    final f = gcj02ToBd09(g);
    g = GeoPoint(g.lat - (f.lat - b.lat), g.lon - (f.lon - b.lon));
  }
  return g;
}

/// Baidu's own Mercator ("MC") and tile grid. Baidu tiles are not Web
/// Mercator: they are indexed from MC (0,0) with y growing north, and level L
/// has 2^(18-L) MC units per pixel. The band polynomials below are copied
/// verbatim from Baidu's JavaScript API (api.map.baidu.com getscript v3.0,
/// functions `Ta` and `Wb`), which is what draws their tiles.
abstract final class BaiduMercator {
  static double unitsPerPixel(int level) => math.pow(2, 18 - level).toDouble();

  /// BD‑09 lat/lon → MC metres (x east, y north).
  static (double, double) fromBd09(GeoPoint p) {
    final lon = _wrap(p.lon, -180, 180), lat = p.lat.clamp(-85.0, 85.0);
    List<double>? c;
    for (var i = 0; i < _llBand.length; i++) {
      if (lat >= _llBand[i]) {
        c = _ll2mc[i];
        break;
      }
    }
    if (c == null) {
      for (var i = 0; i < _llBand.length; i++) {
        if (lat <= -_llBand[i]) {
          c = _ll2mc[i];
          break;
        }
      }
    }
    return _poly(lon, lat, c!);
  }

  /// MC metres → BD‑09 lat/lon.
  static GeoPoint toBd09(double x, double y) {
    late List<double> c;
    for (var i = 0; i < _mcBand.length; i++) {
      if (y.abs() >= _mcBand[i]) {
        c = _mc2ll[i];
        break;
      }
    }
    final (lon, lat) = _poly(x, y, c);
    return GeoPoint(lat, lon);
  }

  static (double, double) _poly(double x, double y, List<double> c) {
    final u = c[0] + c[1] * x.abs();
    final s = y.abs() / c[9];
    final v =
        c[2] +
        c[3] * s +
        c[4] * s * s +
        c[5] * s * s * s +
        c[6] * s * s * s * s +
        c[7] * s * s * s * s * s +
        c[8] * s * s * s * s * s * s;
    return (x < 0 ? -u : u, y < 0 ? -v : v);
  }

  static double _wrap(double v, double lo, double hi) {
    while (v > hi) {
      v -= hi - lo;
    }
    while (v < lo) {
      v += hi - lo;
    }
    return v;
  }

  static const _mcBand = [12890594.86, 8362377.87, 5591021.0, 3481989.83, 1678043.12, 0.0];
  static const _llBand = [86.0, 60.0, 45.0, 30.0, 15.0, 0.0];

  static const List<List<double>> _mc2ll = [
    [
      1.410526172116255e-8,
      8.98305509648872e-6,
      -1.9939833816331,
      200.9824383106796,
      -187.2403703815547,
      91.6087516669843,
      -23.38765649603339,
      2.57121317296198,
      -0.03801003308653,
      1.73379812e7,
    ],
    [
      -7.435856389565537e-9,
      8.983055097726239e-6,
      -0.78625201886289,
      96.32687599759846,
      -1.85204757529826,
      -59.36935905485877,
      47.40033549296737,
      -16.50741931063887,
      2.28786674699375,
      1.026014486e7,
    ],
    [
      -3.030883460898826e-8,
      8.98305509983578e-6,
      0.30071316287616,
      59.74293618442277,
      7.357984074871,
      -25.38371002664745,
      13.45380521110908,
      -3.29883767235584,
      0.32710905363475,
      6856817.37,
    ],
    [
      -1.981981304930552e-8,
      8.983055099779535e-6,
      0.03278182852591,
      40.31678527705744,
      0.65659298677277,
      -4.44255534477492,
      0.85341911805263,
      0.12923347998204,
      -0.04625736007561,
      4482777.06,
    ],
    [
      3.09191371068437e-9,
      8.983055096812155e-6,
      6.995724062e-5,
      23.10934304144901,
      -2.3663490511e-4,
      -0.6321817810242,
      -0.00663494467273,
      0.03430082397953,
      -0.00466043876332,
      2555164.4,
    ],
    [
      2.890871144776878e-9,
      8.983055095805407e-6,
      -3.068298e-8,
      7.47137025468032,
      -3.53937994e-6,
      -0.02145144861037,
      -1.234426596e-5,
      1.0322952773e-4,
      -3.23890364e-6,
      826088.5,
    ],
  ];

  static const List<List<double>> _ll2mc = [
    [
      -0.0015702102444,
      111320.7020616939,
      1704480524535203,
      -10338987376042340,
      26112667856603880,
      -35149669176653700,
      26595700718403920,
      -10725012454188240,
      1800819912950474,
      82.5,
    ],
    [
      8.277824516172526e-4,
      111320.7020463578,
      6.477955746671607e8,
      -4.082003173641316e9,
      1.077490566351142e10,
      -1.517187553151559e10,
      1.205306533862167e10,
      -5.124939663577472e9,
      9.133119359512032e8,
      67.5,
    ],
    [
      0.00337398766765,
      111320.7020202162,
      4481351.045890365,
      -2.339375119931662e7,
      7.968221547186455e7,
      -1.159649932797253e8,
      9.723671115602145e7,
      -4.366194633752821e7,
      8477230.501135234,
      52.5,
    ],
    [
      0.00220636496208,
      111320.7020209128,
      51751.86112841131,
      3796837.749470245,
      992013.7397791013,
      -1221952.21711287,
      1340652.697009075,
      -620943.6990984312,
      144416.9293806241,
      37.5,
    ],
    [
      -3.441963504368392e-4,
      111320.7020576856,
      278.2353980772752,
      2485758.690035394,
      6070.750963243378,
      54821.18345352118,
      9540.606633304236,
      -2710.55326746645,
      1405.483844121726,
      22.5,
    ],
    [
      -3.218135878613132e-4,
      111320.7020701615,
      0.00369383431289,
      823725.6402795718,
      0.46104986909093,
      2351.343141331292,
      1.58060784298199,
      8.77738589078284,
      0.37238884252424,
      7.45,
    ],
  ];
}
