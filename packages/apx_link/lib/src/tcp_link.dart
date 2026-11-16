// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'link.dart';

/// MAVLink over a TCP client connection (APX SITL serves 5760–5763).
///
/// Reconnects with capped exponential backoff while [autoReconnect] is set,
/// so a SITL restart or a Wi‑Fi drop recovers without user action.
final class TcpLink extends Link {
  TcpLink(this.host, {this.port = 5760, String label = 'TCP', this.autoReconnect = true})
    : super(LinkDescriptor(LinkKind.tcp, label, 'tcp:$host:$port'));

  final String host;
  final int port;
  final bool autoReconnect;

  static const connectTimeout = Duration(seconds: 3);
  static const maxBackoff = Duration(seconds: 8);

  Socket? _socket;
  bool _closing = false;
  int _attempt = 0;
  Timer? _retry;

  @override
  Future<void> openTransport() async {
    _closing = false;
    _attempt = 0;
    state.value = LinkState.connecting;
    try {
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _attempt = 0;
      lastError = null;
      state.value = LinkState.up;
      socket.listen(onBytes, onError: (Object e) => _dropped('$e'), onDone: () => _dropped('closed by peer'));
    } on TimeoutException {
      final err = 'Connection to $host:$port timed out';
      lastError = err;
      state.value = LinkState.failed;
      throw TimeoutException(err);
    } on SocketException catch (e) {
      final err = 'Failed to connect to $host:$port (${e.message})';
      lastError = err;
      state.value = LinkState.failed;
      throw SocketException(err);
    } on Object catch (e) {
      final err = 'Failed to connect to $host:$port: $e';
      lastError = err;
      state.value = LinkState.failed;
      rethrow;
    }
  }

  Future<void> _connect() async {
    if (_closing) return;
    state.value = LinkState.reconnecting;
    try {
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _attempt = 0;
      lastError = null;
      state.value = LinkState.up;
      socket.listen(onBytes, onError: (Object e) => _dropped('$e'), onDone: () => _dropped('closed by peer'));
    } on Object catch (e) {
      _dropped('$e');
    }
  }

  void _dropped(String reason) {
    _socket?.destroy();
    _socket = null;
    if (_closing) return;
    lastError = reason;
    if (!autoReconnect) {
      state.value = LinkState.failed;
      return;
    }
    _attempt++;
    state.value = LinkState.reconnecting;
    final delay = Duration(milliseconds: min(maxBackoff.inMilliseconds, 250 * (1 << min(_attempt, 6))));
    _retry?.cancel();
    _retry = Timer(delay, _connect);
  }

  @override
  Future<void> writeTransport(Uint8List frame) async => _socket?.add(frame);

  @override
  Future<void> closeTransport() async {
    _closing = true;
    _retry?.cancel();
    await _socket?.close();
    _socket?.destroy();
    _socket = null;
  }
}
