// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import '../geo/china.dart';
import '../geo/mercator.dart';

/// How a provider numbers its tiles.
enum TileGrid {
  /// Standard XYZ slippy map (Web Mercator, y down).
  webMercator,

  /// Baidu's own Mercator grid, y up from MC (0,0); see `BaiduMercator`.
  baidu,
}

/// A service that issues API keys. Several providers share one key (all the
/// Google map types use the same key), so keys are stored per service.
final class KeyService {
  const KeyService(this.id, this.name, {required this.consoleUrl, this.note});

  final String id, name;

  /// Where the user gets a key.
  final String consoleUrl;
  final String? note;

  static const google = KeyService(
    'google',
    'Google Map Tiles API',
    consoleUrl: 'https://console.cloud.google.com/google/maps-apis',
    note: 'Enable "Map Tiles API" for the key.',
  );
  static const azure = KeyService('azure', 'Azure Maps', consoleUrl: 'https://portal.azure.com/#create/Microsoft.Maps');
  static const mapbox = KeyService('mapbox', 'Mapbox', consoleUrl: 'https://account.mapbox.com/access-tokens/');
  static const maptiler = KeyService('maptiler', 'MapTiler', consoleUrl: 'https://cloud.maptiler.com/account/keys/');
  static const tianditu = KeyService(
    'tianditu',
    'Tianditu (天地图)',
    consoleUrl: 'https://console.tianditu.gov.cn/',
    note: 'Use a "server" (服务端) key.',
  );

  static const all = [google, azure, mapbox, maptiler, tianditu];

  static KeyService? byId(String id) => all.where((k) => k.id == id).firstOrNull;
}

/// Google's Map Tiles API needs a session token created with the key.
final class GoogleSessionSpec {
  const GoogleSessionSpec(this.mapType, {this.layerTypes = const []});
  final String mapType;
  final List<String> layerTypes;

  Map<String, Object> get body => {
    'mapType': mapType,
    'language': 'en-US',
    'region': 'US',
    if (layerTypes.isNotEmpty) 'layerTypes': layerTypes,
  };
}

/// Credentials the tile server adds when it builds an upstream URL. Keys never
/// appear in the URLs the map widget sees.
final class TileAuth {
  const TileAuth({this.key, this.session});
  final String? key;
  final String? session;
}

typedef TileUrl = String Function(int z, int x, int y, TileAuth auth);

/// An online base‑map source.
final class MapProvider {
  const MapProvider({
    required this.id,
    required this.name,
    required this.group,
    required this.attribution,
    required this.url,
    this.labels,
    this.minZoom = 0,
    this.maxZoom = 19,
    this.datum = MapDatum.wgs84,
    this.grid = TileGrid.webMercator,
    this.key,
    this.googleSession,
    this.imagery = false,
    this.allowsBulkDownload = false,
    this.custom = false,
  });

  final String id, name, group, attribution;
  final TileUrl url;

  /// A transparent label layer drawn over [url] (imagery + names).
  final TileUrl? labels;
  final int minZoom, maxZoom;

  /// The datum the provider's imagery is drawn in. Non‑WGS‑84 tiles are
  /// reprojected by the tile server so everything on the map stays WGS‑84.
  final MapDatum datum;
  final TileGrid grid;
  final KeyService? key;
  final GoogleSessionSpec? googleSession;

  /// Photographic: served as JPEG after reprojection, shown with a darker
  /// vehicle trail.
  final bool imagery;

  /// Whether the provider's terms allow downloading areas for offline use.
  final bool allowsBulkDownload;

  /// User‑defined (Settings → Maps → Custom sources).
  final bool custom;

  /// Tiles pass straight through (no reprojection or label compositing).
  bool get passthrough => datum == MapDatum.wgs84 && grid == TileGrid.webMercator && labels == null;
}

String _pick(List<String> s, int x, int y) => s[(x + y).abs() % s.length];

/// Built‑in providers. Every URL here was checked against the live service
/// (keyed services reject a bad key with 401/403, not 404).
abstract final class MapProviders {
  static const defaultId = 'osm';

  static final List<MapProvider> builtIn = [
    MapProvider(
      id: 'osm',
      name: 'OpenStreetMap',
      group: 'OpenStreetMap',
      attribution: '© OpenStreetMap contributors',
      url: (z, x, y, _) => 'https://tile.openstreetmap.org/$z/$x/$y.png',
    ),
    MapProvider(
      id: 'opentopomap',
      name: 'OpenTopoMap',
      group: 'OpenStreetMap',
      attribution: '© OpenStreetMap contributors, SRTM · style © OpenTopoMap (CC‑BY‑SA)',
      maxZoom: 17,
      url: (z, x, y, _) => 'https://${_pick(const ['a', 'b', 'c'], x, y)}.tile.opentopomap.org/$z/$x/$y.png',
    ),
    MapProvider(
      id: 'esri-imagery',
      name: 'Esri World Imagery',
      group: 'Esri',
      attribution: 'Esri, Maxar, Earthstar Geographics, and the GIS User Community',
      imagery: true,
      url: (z, x, y, _) => 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x',
    ),
    MapProvider(
      id: 'esri-topo',
      name: 'Esri World Topographic',
      group: 'Esri',
      attribution: 'Esri, HERE, Garmin, FAO, NOAA, USGS, © OpenStreetMap contributors',
      url: (z, x, y, _) =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/$z/$y/$x',
    ),
    for (final (type, label, layers, imagery) in const [
      ('roadmap', 'Roadmap', <String>[], false),
      ('satellite', 'Satellite', <String>[], true),
      ('satellite', 'Hybrid', ['layerRoadmap'], true),
      ('terrain', 'Terrain', ['layerRoadmap'], false),
    ])
      MapProvider(
        id: 'google-${label.toLowerCase()}',
        name: 'Google $label',
        group: 'Google',
        attribution: 'Map data ©${DateTime.now().year} Google',
        maxZoom: 22,
        key: KeyService.google,
        imagery: imagery,
        googleSession: GoogleSessionSpec(type, layerTypes: layers),
        url: (z, x, y, a) => 'https://tile.googleapis.com/v1/2dtiles/$z/$x/$y?session=${a.session}&key=${a.key}',
      ),
    for (final (tileset, label, imagery, maxZoom) in const [
      ('microsoft.imagery', 'Imagery', true, 19),
      ('microsoft.base.road', 'Road', false, 22),
    ])
      MapProvider(
        id: 'azure-${label.toLowerCase()}',
        name: 'Azure Maps $label',
        group: 'Microsoft',
        attribution: '© Microsoft, © TomTom, © Vexcel, Earthstar Geographics',
        maxZoom: maxZoom,
        key: KeyService.azure,
        imagery: imagery,
        url: (z, x, y, a) =>
            'https://atlas.microsoft.com/map/tile?api-version=2024-04-01&tilesetId=$tileset&zoom=$z&x=$x&y=$y&tileSize=256&subscription-key=${a.key}',
      ),
    MapProvider(
      id: 'mapbox-satellite',
      name: 'Mapbox Satellite',
      group: 'Mapbox',
      attribution: '© Mapbox © Maxar',
      maxZoom: 22,
      key: KeyService.mapbox,
      imagery: true,
      url: (z, x, y, a) => 'https://api.mapbox.com/v4/mapbox.satellite/$z/$x/$y.jpg?access_token=${a.key}',
    ),
    MapProvider(
      id: 'maptiler-satellite',
      name: 'MapTiler Satellite',
      group: 'MapTiler',
      attribution: '© MapTiler © OpenStreetMap contributors',
      maxZoom: 20,
      key: KeyService.maptiler,
      imagery: true,
      url: (z, x, y, a) => 'https://api.maptiler.com/tiles/satellite-v2/$z/$x/$y.jpg?key=${a.key}',
    ),
    for (final (layer, label, labelLayer, imagery) in const [
      ('img', 'Imagery', 'cia', true),
      ('vec', 'Vector', 'cva', false),
    ])
      MapProvider(
        id: 'tianditu-$layer',
        name: 'Tianditu $label',
        group: 'China',
        attribution: '© 天地图 Tianditu',
        maxZoom: 18,
        key: KeyService.tianditu,
        imagery: imagery,
        url: (z, x, y, a) => _tianditu(layer, z, x, y, a),
        labels: (z, x, y, a) => _tianditu(labelLayer, z, x, y, a),
      ),
    MapProvider(
      id: 'gaode-road',
      name: 'Gaode (AMap) Road',
      group: 'China',
      attribution: '© 高德地图 AutoNavi',
      maxZoom: 18,
      datum: MapDatum.gcj02,
      url: (z, x, y, _) =>
          'https://webrd0${_pick(const ['1', '2', '3', '4'], x, y)}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x=$x&y=$y&z=$z',
    ),
    MapProvider(
      id: 'gaode-satellite',
      name: 'Gaode (AMap) Satellite',
      group: 'China',
      attribution: '© 高德地图 AutoNavi',
      maxZoom: 18,
      datum: MapDatum.gcj02,
      imagery: true,
      url: (z, x, y, _) =>
          'https://webst0${_pick(const ['1', '2', '3', '4'], x, y)}.is.autonavi.com/appmaptile?style=6&x=$x&y=$y&z=$z',
      labels: (z, x, y, _) =>
          'https://webst0${_pick(const ['1', '2', '3', '4'], x, y)}.is.autonavi.com/appmaptile?style=8&x=$x&y=$y&z=$z',
    ),
    MapProvider(
      id: 'baidu-road',
      name: 'Baidu Road',
      group: 'China',
      attribution: '© 百度地图 Baidu',
      maxZoom: 19,
      datum: MapDatum.bd09,
      grid: TileGrid.baidu,
      url: (z, x, y, _) =>
          'https://maponline${_pick(const ['0', '1', '2', '3'], x, y)}.bdimg.com/tile/?qt=vtile&x=$x&y=$y&z=$z&styles=pl&scaler=1&udt=20240101&from=jsapi3_0',
    ),
    MapProvider(
      id: 'baidu-satellite',
      name: 'Baidu Satellite',
      group: 'China',
      attribution: '© 百度地图 Baidu',
      maxZoom: 19,
      datum: MapDatum.bd09,
      grid: TileGrid.baidu,
      imagery: true,
      url: (z, x, y, _) =>
          'https://maponline${_pick(const ['0', '1', '2', '3'], x, y)}.bdimg.com/starpic/?qt=satepc&u=x=$x;y=$y;z=$z;v=009;type=sate&fm=46&udt=20240101',
    ),
  ];

  static String _tianditu(String layer, int z, int x, int y, TileAuth a) =>
      'https://t${(x + y) % 8}.tianditu.gov.cn/${layer}_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=$layer'
      '&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX=$z&TILEROW=$y&TILECOL=$x&tk=${a.key}';
}

/// A user‑defined online source: an XYZ template or a WMS endpoint.
final class CustomSource {
  const CustomSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.template,
    this.maxZoom = 19,
    this.layers = '',
    this.attribution = '',
  });

  final String id, name;

  /// `xyz` or `wms`.
  final String kind;

  /// XYZ: a URL with {z} {x} {y}, optional {-y} (TMS), {s} (a/b/c), {q}
  /// (quadkey). WMS: the service base URL.
  final String template;
  final int maxZoom;
  final String layers;
  final String attribution;

  MapProvider toProvider() => MapProvider(
    id: id,
    name: name,
    group: 'Custom',
    attribution: attribution.isEmpty ? name : attribution,
    maxZoom: maxZoom,
    custom: true,
    url: kind == 'wms' ? _wms : _xyz,
  );

  String _xyz(int z, int x, int y, TileAuth _) => template
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{-y}', '${(1 << z) - 1 - y}')
      .replaceAll('{y}', '$y')
      .replaceAll('{s}', _pick(const ['a', 'b', 'c'], x, y))
      .replaceAll('{q}', TileId(z, x, y).quadKey);

  String _wms(int z, int x, int y, TileAuth _) {
    final b = TileId(z, x, y).bounds;
    final (x0, y0) = WebMercator.toMetres(b.south, b.west);
    final (x1, y1) = WebMercator.toMetres(b.north, b.east);
    final sep = template.contains('?') ? '&' : '?';
    return '$template${sep}SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0&LAYERS=${Uri.encodeQueryComponent(layers)}&STYLES='
        '&CRS=EPSG:3857&BBOX=$x0,$y0,$x1,$y1&WIDTH=256&HEIGHT=256&FORMAT=image/png&TRANSPARENT=true';
  }

  /// Checks the template before saving it.
  String? validate() {
    if (name.trim().isEmpty) return 'Give the source a name.';
    final u = Uri.tryParse(template.replaceAll(RegExp(r'\{[^}]*\}'), '0'));
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https'))
      return 'The URL must start with http:// or https://.';
    if (kind == 'xyz' &&
        !(template.contains('{z}') &&
            template.contains('{x}') &&
            (template.contains('{y}') || template.contains('{-y}'))) &&
        !template.contains('{q}')) {
      return 'An XYZ template needs {z}, {x} and {y} (or {q}).';
    }
    if (kind == 'wms' && layers.trim().isEmpty) return 'Enter the WMS layer name(s).';
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'template': template,
    'maxZoom': maxZoom,
    'layers': layers,
    'attribution': attribution,
  };

  factory CustomSource.fromJson(Map<String, Object?> j) => CustomSource(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: j['kind'] as String,
    template: j['template'] as String,
    maxZoom: (j['maxZoom'] as num?)?.toInt() ?? 19,
    layers: j['layers'] as String? ?? '',
    attribution: j['attribution'] as String? ?? '',
  );
}
