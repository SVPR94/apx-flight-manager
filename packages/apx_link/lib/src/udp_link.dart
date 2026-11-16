// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'link.dart';

/// MAVLink over UDP.
///
/// APX (SITL / Linux) binds `udp_port + 1` (default 14551) and streams to
/// 127.0.0.1:14550, and additionally to any address that has sent to 14551.
/// So:
///  * [UdpLink.listen] on 14550 receives a local SITL with no configuration;
///  * [UdpLink.target] sends to `host:14551`, which makes a remote APX
///    register us and start streaming back.
/// Either way replies go to every peer we have heard from.
final class UdpLink extends Link {
  UdpLink.listen({int port = 14550, String label = 'UDP'})
    : _localPort = port,
      _target = null,
      super(LinkDescriptor(LinkKind.udp, label, 'udp:0.0.0.0:$port'));

  UdpLink.target(String host, {int port = 14551, int localPort = 0, String label = 'UDP'})
    : _localPort = localPort,
      _target = (host, port),
      super(LinkDescriptor(LinkKind.udp, label, 'udp:$host:$port'));

  final int _localPort;
  final (String, int)? _target;
  RawDatagramSocket? _socket;
  final _peers = <(InternetAddress, int)>{};

  /// Peers heard from so far.
  Iterable<String> get peers => _peers.map((p) => '${p.$1.address}:${p.$2}');

  @override
  Future<void> openTransport() async {
    state.value = LinkState.connecting;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _localPort, reuseAddress: true);
      socket.broadcastEnabled = true;
      _socket = socket;
      if (_target case (final host, final port)) {
        final addresses = await InternetAddress.lookup(host);
        _peers.add((addresses.firstWhere((a) => a.type == InternetAddressType.IPv4), port));
      }
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          Datagram? d;
          while ((d = socket.receive()) != null) {
            _peers.add((d!.address, d.port));
            onBytes(d.data);
          }
        },
        onError: (Object e) {
          lastError = '$e';
          state.value = LinkState.failed;
        },
      );
      state.value = LinkState.up;
    } on Object catch (e) {
      lastError = '$e';
      state.value = LinkState.failed;
      rethrow;
    }
  }

  @override
  Future<void> writeTransport(Uint8List frame) async {
    final socket = _socket;
    if (socket == null) return;
    for (final (addr, port) in _peers) {
      socket.send(frame, addr, port);
    }
  }

  @override
  Future<void> closeTransport() async {
    _socket?.close();
    _socket = null;
    _peers.clear();
  }
}
