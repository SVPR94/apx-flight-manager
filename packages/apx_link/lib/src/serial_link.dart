// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'link.dart';

/// A serial port as the platform exposes it. Implemented in the Flutter app
/// (libserialport on Windows/Linux/macOS, usb_serial on Android) so this
/// package stays pure Dart.
abstract interface class SerialPortAdapter {
  Future<void> open(String port, int baudRate);
  Stream<Uint8List> get input;
  Future<void> write(Uint8List data);
  Future<void> close();
}

/// A port the OS reports, for the connection sheet and auto‑connect.
final class SerialPortInfo {
  const SerialPortInfo(this.name, {this.description = '', this.vendorId, this.productId});

  final String name;
  final String description;
  final int? vendorId;
  final int? productId;

  @override
  String toString() => description.isEmpty ? name : '$name — $description';
}

abstract interface class SerialPortEnumerator {
  Future<List<SerialPortInfo>> list();
}

/// Standard POSIX serial adapter for Linux and macOS.
final class PosixSerialPortAdapter implements SerialPortAdapter {
  IOSink? _sink;
  StreamSubscription<List<int>>? _readSub;
  final _input = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> open(String port, int baudRate) async {
    final devFile = File(port);
    if (!devFile.existsSync()) {
      throw FileSystemException('Serial device not found', port);
    }

    if (Platform.isLinux || Platform.isMacOS) {
      final flag = Platform.isMacOS ? '-f' : '-F';
      final res = await Process.run('stty', [flag, port, '$baudRate', 'raw', '-echo', '-echoe', '-echok']);
      if (res.exitCode != 0) {
        final err = res.stderr.toString().trim();
        throw FileSystemException(
          'Failed to configure serial port $port: $err. Check dialout group permissions.',
          port,
        );
      }
    }

    try {
      _sink = devFile.openWrite(mode: FileMode.writeOnlyAppend);
      _readSub = devFile.openRead().listen(
        (data) => _input.add(Uint8List.fromList(data)),
        onError: (Object e) => _input.addError(e),
        onDone: () => _input.close(),
      );
    } catch (e) {
      await close();
      throw FileSystemException('Failed to open serial port $port: $e', port);
    }
  }

  @override
  Future<void> write(Uint8List data) async {
    final s = _sink;
    if (s == null) return;
    s.add(data);
    await s.flush();
  }

  @override
  Future<void> close() async {
    await _readSub?.cancel();
    _readSub = null;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }
}

/// Enumerates serial ports on POSIX (Linux/macOS).
final class PosixSerialPortEnumerator implements SerialPortEnumerator {
  const PosixSerialPortEnumerator();

  @override
  Future<List<SerialPortInfo>> list() async {
    final ports = <SerialPortInfo>[];
    if (Platform.isLinux) {
      final byId = Directory('/dev/serial/by-id');
      if (byId.existsSync()) {
        try {
          for (final entity in byId.listSync()) {
            final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
            ports.add(SerialPortInfo(entity.path, description: name));
          }
        } catch (_) {}
      }

      final ttyDir = Directory('/sys/class/tty');
      if (ttyDir.existsSync()) {
        try {
          final entries = ttyDir.listSync();
          for (final e in entries) {
            final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
            if (name.startsWith('ttyACM') || name.startsWith('ttyUSB')) {
              final devPath = '/dev/$name';
              if (ports.every((p) => p.name != devPath)) {
                ports.add(SerialPortInfo(devPath, description: name.startsWith('ttyACM') ? 'APX USB CDC' : 'USB Serial'));
              }
            }
          }
        } catch (_) {}
      }
    }
    return ports;
  }
}

/// MAVLink over a serial port: APX USB CDC today, UART radios later.
/// USB CDC ignores the baud rate, a radio does not.
final class SerialLink extends Link {
  SerialLink(this._adapter, this.port, {this.baudRate = 115200, String label = 'Serial'})
    : super(LinkDescriptor(LinkKind.serial, label, 'serial:$port@$baudRate'));

  /// Baud rates offered in the UI; 57600 is the SiK radio default.
  static const commonBaudRates = [57600, 115200, 230400, 460800, 921600];

  final SerialPortAdapter _adapter;
  final String port;
  final int baudRate;
  StreamSubscription<Uint8List>? _sub;

  @override
  Future<void> openTransport() async {
    state.value = LinkState.connecting;
    try {
      await _adapter.open(port, baudRate);
      _sub = _adapter.input.listen(
        onBytes,
        onError: (Object e) {
          lastError = '$e';
          state.value = LinkState.failed;
        },
        onDone: () {
          if (state.value == LinkState.up) {
            lastError = 'Port closed (device unplugged?)';
            state.value = LinkState.failed;
          }
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
  Future<void> writeTransport(Uint8List frame) => _adapter.write(frame);

  @override
  Future<void> closeTransport() async {
    await _sub?.cancel();
    _sub = null;
    await _adapter.close();
  }
}
