// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:apx_link/apx_link.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:test/test.dart';

final _vehicle = MavFrameWriter(systemId: 1, componentId: 1);
Uint8List _hb() => _vehicle.encode(const Heartbeat(type: 2, autopilot: 3));

Future<int> _freeUdpPort() async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  s.close();
  return p;
}

void main() {
  test('UDP listen learns the sender and replies to it', () async {
    final port = await _freeUdpPort();
    final gcs = UdpLink.listen(port: port);
    await gcs.open();

    final vehicle = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final replies = <List<int>>[];
    vehicle.listen((e) {
      if (e == RawSocketEvent.read) replies.add(vehicle.receive()!.data);
    });

    final first = gcs.frames.first;
    vehicle.send(_hb(), InternetAddress.loopbackIPv4, port);
    final frame = await first.timeout(const Duration(seconds: 2));
    expect(frame.message, isA<Heartbeat>());

    await gcs.send(MavFrameWriter().encode(const Heartbeat(type: MavType.gcs)));
    await _until(() => replies.isNotEmpty);
    expect(replies, hasLength(1));

    await gcs.dispose();
    vehicle.close();
  });

  test('UDP target registers with the vehicle by sending first', () async {
    final vehicle = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final heard = <Datagram>[];
    vehicle.listen((e) {
      if (e == RawSocketEvent.read) heard.add(vehicle.receive()!);
    });
    final gcs = UdpLink.target('127.0.0.1', port: vehicle.port);
    await gcs.open();
    await gcs.send(MavFrameWriter().encode(const Heartbeat(type: MavType.gcs)));
    await _until(() => heard.isNotEmpty);

    // The vehicle answers to whoever spoke (as APX does).
    final got = gcs.frames.first;
    vehicle.send(_hb(), heard.first.address, heard.first.port);
    expect((await got.timeout(const Duration(seconds: 2))).systemId, 1);
    await gcs.dispose();
    vehicle.close();
  });

  test('TCP reconnects by itself after the peer drops the connection', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final clients = <Socket>[];
    server.listen((c) {
      clients.add(c);
      c.add(_hb());
    });

    final link = TcpLink('127.0.0.1', port: server.port);
    final frames = <MavlinkFrame>[];
    link.frames.listen(frames.add);
    final states = <LinkState>[];
    link.state.changes.listen(states.add);

    await link.open();
    await _until(() => frames.length == 1);

    clients.single.destroy(); // vehicle side hangs up
    await _until(() => frames.length == 2, timeout: const Duration(seconds: 5));
    expect(states, containsAllInOrder([LinkState.up, LinkState.reconnecting, LinkState.up]));
    expect(clients, hasLength(2));

    await link.dispose();
    await server.close();
  });

  test('TCP reports reconnecting while nothing listens', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final link = TcpLink('127.0.0.1', port: port);
    await link.open();
    expect(link.state.value, LinkState.reconnecting);
    expect(link.lastError, isNotNull);
    await link.dispose();
    expect(link.state.value, LinkState.closed);
  });
}

Future<void> _until(bool Function() ok, {Duration timeout = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
