// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_link/apx_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../state/connection.dart';
import '../state/storage.dart';

enum _Kind { tcp, udpListen, udpTarget, serial }

/// Pick a transport and connect. Supports TCP, UDP, and Serial interfaces,
/// remembers last selected settings, and displays actionable connection error states.
class ConnectForm extends ConsumerStatefulWidget {
  const ConnectForm({super.key});

  @override
  ConsumerState<ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends ConsumerState<ConnectForm> {
  _Kind _kind = _Kind.tcp;
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '5760');
  final _serialPort = TextEditingController(text: '/dev/ttyACM0');
  int _serialBaud = 115200;
  List<SerialPortInfo> _discoveredPorts = [];
  bool _scanningPorts = false;
  bool _isConnecting = false;
  String? _error;
  bool _initialized = false;

  static const _defaultPort = {
    _Kind.tcp: '5760',
    _Kind.udpListen: '14550',
    _Kind.udpTarget: '14551',
    _Kind.serial: '115200',
  };

  @override
  void initState() {
    super.initState();
    _scanSerialPorts();
  }

  void _loadSavedSettings() {
    if (_initialized) return;
    _initialized = true;
    final store = ref.read(settingsStoreProvider);

    final savedKind = store.get<String>('conn_last_kind');
    if (savedKind != null) {
      for (final k in _Kind.values) {
        if (k.name == savedKind) {
          _kind = k;
          break;
        }
      }
    }

    final savedTcpHost = store.get<String>('conn_tcp_host');
    final savedTcpPort = store.get<String>('conn_tcp_port');
    final savedUdpListenPort = store.get<String>('conn_udp_listen_port');
    final savedUdpTargetHost = store.get<String>('conn_udp_target_host');
    final savedUdpTargetPort = store.get<String>('conn_udp_target_port');
    final savedSerialPort = store.get<String>('conn_serial_port');
    final savedSerialBaud = store.get<int>('conn_serial_baud');

    if (savedSerialPort != null && savedSerialPort.isNotEmpty) {
      _serialPort.text = savedSerialPort;
    }
    if (savedSerialBaud != null) {
      _serialBaud = savedSerialBaud;
    }

    switch (_kind) {
      case _Kind.tcp:
        if (savedTcpHost != null) _host.text = savedTcpHost;
        if (savedTcpPort != null) _port.text = savedTcpPort;
      case _Kind.udpListen:
        if (savedUdpListenPort != null) _port.text = savedUdpListenPort;
      case _Kind.udpTarget:
        if (savedUdpTargetHost != null) _host.text = savedUdpTargetHost;
        if (savedUdpTargetPort != null) _port.text = savedUdpTargetPort;
      case _Kind.serial:
        break;
    }
  }

  Future<void> _scanSerialPorts() async {
    setState(() => _scanningPorts = true);
    try {
      final ports = await const PosixSerialPortEnumerator().list();
      if (!mounted) return;
      setState(() {
        _discoveredPorts = ports;
        if (ports.isNotEmpty && (_serialPort.text.isEmpty || _serialPort.text == '/dev/ttyACM0')) {
          _serialPort.text = ports.first.name;
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanningPorts = false);
    }
  }

  void _saveSettings() {
    final store = ref.read(settingsStoreProvider);
    store.set('conn_last_kind', _kind.name);
    switch (_kind) {
      case _Kind.tcp:
        store.set('conn_tcp_host', _host.text.trim());
        store.set('conn_tcp_port', _port.text.trim());
      case _Kind.udpListen:
        store.set('conn_udp_listen_port', _port.text.trim());
      case _Kind.udpTarget:
        store.set('conn_udp_target_host', _host.text.trim());
        store.set('conn_udp_target_port', _port.text.trim());
      case _Kind.serial:
        store.set('conn_serial_port', _serialPort.text.trim());
        store.set('conn_serial_baud', _serialBaud);
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _serialPort.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_isConnecting) return;
    setState(() => _error = null);

    LinkConfig config;
    if (_kind == _Kind.serial) {
      final portName = _serialPort.text.trim();
      if (portName.isEmpty) {
        setState(() => _error = 'Please enter or select a serial port');
        return;
      }
      config = SerialConfig(portName, baudRate: _serialBaud);
    } else {
      final port = int.tryParse(_port.text.trim());
      final host = _host.text.trim();
      if (port == null || port < 1 || port > 65535) {
        setState(() => _error = 'Port must be 1–65535');
        return;
      }
      if (_kind != _Kind.udpListen && host.isEmpty) {
        setState(() => _error = 'Enter the vehicle address');
        return;
      }
      config = switch (_kind) {
        _Kind.tcp => TcpConfig(host, port),
        _Kind.udpListen => UdpListenConfig(port),
        _Kind.udpTarget => UdpTargetConfig(host, port),
        _Kind.serial => throw UnimplementedError(),
      };
    }

    _saveSettings();
    setState(() => _isConnecting = true);

    try {
      final err = await ref.read(connectionProvider.notifier).connect(config);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _error = err;
          _isConnecting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Connection failed: $e';
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _loadSavedSettings();
    final p = context.alloy;
    final hint = switch (_kind) {
      _Kind.tcp => 'APX SITL and companion computers serve TCP 5760–5763.',
      _Kind.udpListen => 'Receives a vehicle that streams to this machine (APX SITL sends to 14550).',
      _Kind.udpTarget => 'Sends to a remote APX on port 14551 so it starts streaming back.',
      _Kind.serial => 'Connects to APX USB CDC flight controller or telemetry radio (e.g. SiK 57600).',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Row(
          spacing: 10,
          children: [
            Icon(LucideIcons.plug, color: p.accentInk),
            const Text('Connect to a vehicle', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ],
        ),
        SegmentedButton<_Kind>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Kind.tcp, label: Text('TCP')),
            ButtonSegment(value: _Kind.udpListen, label: Text('UDP listen')),
            ButtonSegment(value: _Kind.udpTarget, label: Text('UDP host')),
            ButtonSegment(value: _Kind.serial, label: Text('Serial')),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() {
            _kind = v.single;
            _error = null;
            if (_kind != _Kind.serial) {
              _port.text = _defaultPort[_kind]!;
            }
          }),
        ),
        if (_kind == _Kind.serial) ...[
          Row(
            spacing: 10,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _serialPort,
                  decoration: InputDecoration(
                    labelText: 'Serial Port',
                    hintText: '/dev/ttyACM0',
                    suffixIcon: IconButton(
                      icon: _scanningPorts
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(LucideIcons.refreshCw, size: 16),
                      tooltip: 'Rescan available ports',
                      onPressed: _scanningPorts ? null : _scanSerialPorts,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  initialValue: _serialBaud,
                  decoration: const InputDecoration(labelText: 'Baud Rate'),
                  items: [
                    for (final b in SerialLink.commonBaudRates)
                      DropdownMenuItem(value: b, child: Text('$b')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _serialBaud = v);
                  },
                ),
              ),
            ],
          ),
          if (_discoveredPorts.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Detected:', style: TextStyle(fontSize: 11, color: p.ink2)),
                for (final info in _discoveredPorts)
                  ActionChip(
                    label: Text(info.name, style: const TextStyle(fontSize: 11)),
                    tooltip: info.description,
                    onPressed: () => setState(() => _serialPort.text = info.name),
                  ),
              ],
            ),
        ] else ...[
          Row(
            spacing: 10,
            children: [
              if (_kind != _Kind.udpListen)
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    decoration: const InputDecoration(labelText: 'Host'),
                  ),
                ),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _port,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _connect(),
                ),
              ),
            ],
          ),
        ],
        Text(hint, style: TextStyle(color: p.ink2, fontSize: 12)),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.circleAlert, size: 16, color: Color(0xFFFF3B30)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        AlloyButton(
          label: _isConnecting ? 'Connecting…' : 'Connect',
          icon: _isConnecting ? LucideIcons.loader : LucideIcons.plug,
          primary: true,
          expand: true,
          onPressed: _isConnecting ? null : _connect,
        ),
      ],
    );
  }
}
