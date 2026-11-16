// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:apx_geo/apx_geo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage.dart';

/// User map settings, persisted in settings.json under "maps".
final class MapSettings {
  const MapSettings({
    this.baseMap = MapProviders.defaultId,
    this.keys = const {},
    this.offline = false,
    this.shareOnLan = false,
    this.cacheLimitMb = 2048,
    this.custom = const [],
    this.local = const [],
  });

  final String baseMap;

  /// API keys by [KeyService.id].
  final Map<String, String> keys;
  final bool offline;
  final bool shareOnLan;
  final int cacheLimitMb;
  final List<CustomSource> custom;

  /// MBTiles files and tile folders, as [LocalTileSource.toJson].
  final List<Map<String, Object?>> local;

  MapSettings copyWith({
    String? baseMap,
    Map<String, String>? keys,
    bool? offline,
    bool? shareOnLan,
    int? cacheLimitMb,
    List<CustomSource>? custom,
    List<Map<String, Object?>>? local,
  }) => MapSettings(
    baseMap: baseMap ?? this.baseMap,
    keys: keys ?? this.keys,
    offline: offline ?? this.offline,
    shareOnLan: shareOnLan ?? this.shareOnLan,
    cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
    custom: custom ?? this.custom,
    local: local ?? this.local,
  );

  Map<String, Object?> toJson() => {
    'baseMap': baseMap,
    'keys': keys,
    'offline': offline,
    'shareOnLan': shareOnLan,
    'cacheLimitMb': cacheLimitMb,
    'custom': [for (final c in custom) c.toJson()],
    'local': local,
  };

  factory MapSettings.fromJson(Map<String, Object?> j) => MapSettings(
    baseMap: j['baseMap'] as String? ?? MapProviders.defaultId,
    keys: (j['keys'] as Map?)?.cast<String, String>() ?? const {},
    offline: j['offline'] == true,
    shareOnLan: j['shareOnLan'] == true,
    cacheLimitMb: (j['cacheLimitMb'] as num?)?.toInt() ?? 2048,
    custom: [for (final c in (j['custom'] as List? ?? const [])) CustomSource.fromJson((c as Map).cast())],
    local: [for (final l in (j['local'] as List? ?? const [])) (l as Map).cast<String, Object?>()],
  );
}

/// A base map the user can pick: an online provider or a local source.
final class BaseMapChoice {
  const BaseMapChoice({
    required this.id,
    required this.name,
    required this.group,
    required this.attribution,
    required this.maxZoom,
    this.provider,
    this.needsKey,
    this.imagery = false,
  });

  final String id, name, group, attribution;
  final int maxZoom;
  final MapProvider? provider;

  /// The key service still missing a key, if any.
  final KeyService? needsKey;
  final bool imagery;
}

/// The running tile service and its HTTP front.
final class TileEngine {
  TileEngine(this.service, this.server, this.cachePath);
  final TileService service;
  final TileServer server;

  /// The SQLite cache file; overlay imports open their own connection to it.
  final String cachePath;

  String urlTemplate(String source) => server.urlTemplate(source);
}

final class MapSettingsController extends Notifier<MapSettings> {
  @override
  MapSettings build() {
    final j = ref.read(settingsStoreProvider).get<Map>('maps');
    return j == null ? const MapSettings() : MapSettings.fromJson(j.cast());
  }

  void _save(MapSettings s) {
    state = s;
    ref.read(settingsStoreProvider).set('maps', s.toJson());
  }

  /// Pushes settings into a running [TileService].
  static void applyTo(TileService service, MapSettings s) {
    service
      ..offline = s.offline
      ..setCustomSources(s.custom);
    service.keys
      ..clear()
      ..addAll(s.keys);
    service.cache.maxBytes = s.cacheLimitMb * 1024 * 1024;
    final wanted = {for (final l in s.local) l['id'] as String};
    for (final existing in service.localSources.map((l) => l.id).toList()) {
      if (!wanted.contains(existing)) service.removeLocalSource(existing);
    }
    for (final l in s.local) {
      if (service.localSources.any((x) => x.id == l['id'])) continue;
      try {
        service.addLocalSource(LocalTileSource.fromJson(l));
      } catch (_) {
        // A moved or deleted file: the choice stays listed and shows as unavailable.
      }
    }
  }

  void setBaseMap(String id) => _save(state.copyWith(baseMap: id));

  void setKey(String service, String key) {
    final keys = Map.of(state.keys);
    if (key.trim().isEmpty) {
      keys.remove(service);
    } else {
      keys[service] = key.trim();
    }
    _save(state.copyWith(keys: keys));
  }

  void setOffline(bool v) => _save(state.copyWith(offline: v));
  void setShareOnLan(bool v) => _save(state.copyWith(shareOnLan: v));
  void setCacheLimit(int mb) => _save(state.copyWith(cacheLimitMb: mb));

  void addCustom(CustomSource c) => _save(state.copyWith(custom: [...state.custom.where((x) => x.id != c.id), c]));

  void removeCustom(String id) =>
      _save(state.copyWith(custom: state.custom.where((c) => c.id != id).toList(), baseMap: _fallback(id)));

  /// Adds an MBTiles file or tile folder; throws with a readable message if
  /// it can't be opened.
  void addLocal(LocalTileSource source) {
    source.close(); // validated; the engine opens its own handle
    _save(state.copyWith(local: [...state.local.where((l) => l['id'] != source.id), source.toJson()]));
  }

  void removeLocal(String id) =>
      _save(state.copyWith(local: state.local.where((l) => l['id'] != id).toList(), baseMap: _fallback(id)));

  String _fallback(String removed) => state.baseMap == removed ? MapProviders.defaultId : state.baseMap;
}

final mapSettingsProvider = NotifierProvider<MapSettingsController, MapSettings>(MapSettingsController.new);

/// Starts the tile cache, service and loopback server. Rebuilt only when LAN
/// sharing changes (the server must rebind); other settings apply live.
final tileEngineProvider = FutureProvider<TileEngine>((ref) async {
  final lan = ref.watch(mapSettingsProvider.select((s) => s.shareOnLan));
  final dir = ref.watch(dataDirProvider);
  final cachePath = '${dir.path}${Platform.pathSeparator}tiles.db';
  final service = TileService(cache: TileCache.open(cachePath));
  MapSettingsController.applyTo(service, ref.read(mapSettingsProvider));
  // Everything except LAN sharing applies to the running service.
  ref.listen(mapSettingsProvider, (_, s) => MapSettingsController.applyTo(service, s));
  final server = await TileServer.start(service, shareOnLan: lan);
  final engine = TileEngine(service, server, cachePath);
  ref.onDispose(() async {
    await server.close();
    service
      ..close()
      ..cache.close();
  });
  return engine;
});

/// Every base map the user can choose, in display order.
final baseMapChoicesProvider = Provider<List<BaseMapChoice>>((ref) {
  final s = ref.watch(mapSettingsProvider);
  final engine = ref.watch(tileEngineProvider).value;
  KeyService? missing(MapProvider p) => p.key != null && (s.keys[p.key!.id]?.isEmpty ?? true) ? p.key : null;
  return [
    for (final p in [...MapProviders.builtIn, ...s.custom.map((c) => c.toProvider())])
      BaseMapChoice(
        id: p.id,
        name: p.name,
        group: p.group,
        attribution: p.attribution,
        maxZoom: p.maxZoom,
        provider: p,
        needsKey: missing(p),
        imagery: p.imagery,
      ),
    for (final l in s.local)
      () {
        final live = engine?.service.localSources.where((x) => x.id == l['id']).firstOrNull;
        return BaseMapChoice(
          id: l['id'] as String,
          name: live?.name ?? (l['name'] as String? ?? File(l['path'] as String).uri.pathSegments.last),
          group: 'Offline files',
          attribution: live?.attribution ?? '',
          maxZoom: live?.maxZoom ?? 19,
        );
      }(),
  ];
});

/// The base map in use (falls back to OpenStreetMap if the saved one is gone).
final currentBaseMapProvider = Provider<BaseMapChoice>((ref) {
  final id = ref.watch(mapSettingsProvider.select((s) => s.baseMap));
  final all = ref.watch(baseMapChoicesProvider);
  return all.where((c) => c.id == id).firstOrNull ?? all.first;
});
