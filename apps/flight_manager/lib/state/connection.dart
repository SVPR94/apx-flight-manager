// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';

import 'package:apx_link/apx_link.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How to reach a vehicle. Kept separate from the live [Link] so it can be
/// shown, edited and saved.
sealed class LinkConfig {
  const LinkConfig();
  Link build();
  String get title;
}

final class TcpConfig extends LinkConfig {
  const TcpConfig(this.host, this.port);
  final String host;
  final int port;
  @override
  Link build() => TcpLink(host, port: port, label: 'TCP');
  @override
  String get title => 'TCP $host:$port';
}

/// Receives a vehicle that streams to this machine (APX SITL → 14550).
final class UdpListenConfig extends LinkConfig {
  const UdpListenConfig(this.port);
  final int port;
  @override
  Link build() => UdpLink.listen(port: port, label: 'UDP');
  @override
  String get title => 'UDP listen :$port';
}

/// Registers with a remote APX by sending to its UDP port (14551).
final class UdpTargetConfig extends LinkConfig {
  const UdpTargetConfig(this.host, this.port);
  final String host;
  final int port;
  @override
  Link build() => UdpLink.target(host, port: port, label: 'UDP');
  @override
  String get title => 'UDP $host:$port';
}

/// Connects via hardware USB CDC or telemetry radio serial port.
final class SerialConfig extends LinkConfig {
  const SerialConfig(this.port, {this.baudRate = 115200});
  final String port;
  final int baudRate;
  @override
  Link build() => SerialLink(PosixSerialPortAdapter(), port, baudRate: baudRate, label: 'Serial');
  @override
  String get title => 'Serial $port @ $baudRate';
}

/// A live connection: link + vehicle session + alerts.
final class Connection {
  Connection(this.config, this.session, this.alerts);
  final LinkConfig config;
  final VehicleSession session;
  final AlertsEngine alerts;
  String? error;
}

class ConnectionController extends Notifier<Connection?> {
  // Riverpod forbids reading `state` inside onDispose, so keep our own handle.
  Connection? _live;

  @override
  Connection? build() {
    ref.onDispose(() => _close(_live));
    return null;
  }

  Future<String?> connect(LinkConfig config) async {
    await disconnect();
    final link = config.build();
    final session = VehicleSession(link);
    final alerts = AlertsEngine()..attach(session);
    final c = Connection(config, session, alerts);
    try {
      await session.start();
      state = _live = c;
      return null;
    } on TimeoutException catch (e) {
      final msg = 'Connection timed out: ${e.message ?? config.title}';
      c.error = msg;
      await _close(c);
      return msg;
    } on SocketException catch (e) {
      final msg = 'Failed to connect: ${e.message}';
      c.error = msg;
      await _close(c);
      return msg;
    } on FileSystemException catch (e) {
      final msg = 'Serial port error: ${e.message}';
      c.error = msg;
      await _close(c);
      return msg;
    } on Object catch (e) {
      final msg = 'Failed to connect: $e';
      c.error = msg;
      await _close(c);
      return msg;
    }
  }

  Future<void> disconnect() async {
    final c = _live;
    state = _live = null;
    await _close(c);
  }

  static Future<void> _close(Connection? c) async {
    if (c == null) return;
    await c.alerts.dispose();
    await c.session.dispose();
    await c.session.link.dispose();
  }
}

final connectionProvider = NotifierProvider<ConnectionController, Connection?>(ConnectionController.new);

/// Display‑rate tick (~15 Hz). Telemetry arrives at ~140 msg/s; widgets that
/// show live values watch this and read the snapshot, instead of rebuilding
/// per message.
final frameTickProvider = StreamProvider<int>((ref) => Stream.periodic(const Duration(milliseconds: 66), (i) => i));
