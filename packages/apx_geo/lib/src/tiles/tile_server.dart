// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../geo/mercator.dart';
import 'tile_service.dart';

/// Local HTTP front for [TileService], local tile caching and serving:
/// the map widget only ever loads `http://<host>:<port>/tiles/<source>/{z}/{x}/{y}`.
///
/// Binds to loopback by default. With [shareOnLan] it listens on all IPv4
/// interfaces so another device (a tablet) can use this machine's cache;
/// only tile reads are exposed, and API keys never appear in URLs.
final class TileServer {
  TileServer._(this.service, this._server, this.shareOnLan) {
    _server.listen(_handle, onError: (_) {});
  }

  static Future<TileServer> start(TileService service, {int port = 0, bool shareOnLan = false}) async {
    final server = await HttpServer.bind(shareOnLan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4, port);
    server.autoCompress = false;
    return TileServer._(service, server, shareOnLan);
  }

  final TileService service;
  final HttpServer _server;
  final bool shareOnLan;
  int requests = 0;

  int get port => _server.port;

  /// URL template for flutter_map.
  String urlTemplate(String source) => 'http://127.0.0.1:$port/tiles/${Uri.encodeComponent(source)}/{z}/{x}/{y}';

  static final _route = RegExp(r'^/tiles/([^/]+)/(\d+)/(\d+)/(\d+)(?:\.\w+)?$');

  Future<void> _handle(HttpRequest req) async {
    requests++;
    final res = req.response;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      if (req.uri.path == '/status') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(_status()));
        return;
      }
      final m = _route.firstMatch(req.uri.path);
      if (m == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final source = Uri.decodeComponent(m.group(1)!);
      final t = TileId(int.parse(m.group(2)!), int.parse(m.group(3)!), int.parse(m.group(4)!));
      final tile = await service.tile(source, t);
      if (tile == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      res.headers
        ..set(HttpHeaders.contentTypeHeader, tile.contentType)
        ..set(HttpHeaders.cacheControlHeader, 'max-age=600')
        ..contentLength = tile.bytes.length;
      if (tile.stale) res.headers.set('X-Tile-Stale', '1');
      if (req.method == 'GET') res.add(tile.bytes);
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
    } finally {
      await res.close().catchError((_) {});
    }
  }

  Map<String, Object?> _status() => {
    'requests': requests,
    'offline': service.offline,
    'cacheBytes': service.cache.sizeBytes,
    'providers': {
      for (final p in service.providers)
        if (service.health(p.id).ok + service.health(p.id).failed + service.health(p.id).cacheHits > 0)
          p.id: {
            'ok': service.health(p.id).ok,
            'failed': service.health(p.id).failed,
            'cacheHits': service.health(p.id).cacheHits,
            'lastError': service.health(p.id).lastError,
          },
    },
  };

  Future<void> close() => _server.close(force: true);
}
