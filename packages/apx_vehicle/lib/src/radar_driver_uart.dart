// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:typed_data';

/// Represents a single decoded UART radar frame.
final class UartRadarPacket {
  const UartRadarPacket({
    required this.distanceM,
    required this.signalQuality,
    required this.strength,
    required this.temperatureC,
    required this.valid,
  });

  /// Measured distance in meters.
  final double distanceM;

  /// Signal quality percentage (0..100%).
  final int signalQuality;

  /// Raw signal strength (amplitude).
  final int strength;

  /// Sensor internal temperature in degrees Celsius.
  final double temperatureC;

  /// Whether measurement meets reliability criteria (strength > 100 && distance > 0).
  final bool valid;
}

/// Pure Dart streaming parser for 9-byte UART radar packets.
///
/// Packet layout:
/// - Byte 0: Header 1 (0x59)
/// - Byte 1: Header 2 (0x59)
/// - Byte 2: Distance Low (cm)
/// - Byte 3: Distance High (cm)
/// - Byte 4: Signal Strength Low
/// - Byte 5: Signal Strength High
/// - Byte 6: Temperature Low / mode
/// - Byte 7: Temperature High / mode
/// - Byte 8: Checksum (8-bit sum of bytes 0..7)
final class UartRadarParser {
  UartRadarParser({this.baudRate = defaultBaudRate});

  static const int headerByte = 0x59;
  static const int packetLength = 9;
  static const int defaultBaudRate = 115200;

  /// Configured baud rate.
  final int baudRate;

  final _controller = StreamController<UartRadarPacket>.broadcast();

  /// Stream of successfully decoded radar packets.
  Stream<UartRadarPacket> get readings => _controller.stream;

  int _state = 0; // 0: wait H1, 1: wait H2, 2: read payload
  final Uint8List _buf = Uint8List(7);
  int _bufIdx = 0;

  /// Feed incoming raw byte chunks into the parser.
  ///
  /// Calls [onReading] whenever a valid frame is successfully verified.
  void parseBytes(
    List<int> bytes,
    void Function(double distanceM, int quality, bool valid) onReading,
  ) {
    for (var i = 0; i < bytes.length; i++) {
      final byte = bytes[i] & 0xFF;
      switch (_state) {
        case 0:
          if (byte == headerByte) {
            _state = 1;
          }
          break;
        case 1:
          if (byte == headerByte) {
            _state = 2;
            _bufIdx = 0;
          } else {
            // Not a second header; if this byte is headerByte, stay in state 1, else reset
            _state = (byte == headerByte) ? 1 : 0;
          }
          break;
        case 2:
          _buf[_bufIdx++] = byte;
          if (_bufIdx >= 7) {
            // Calculate 8-bit checksum: sum(0x59, 0x59, payload[0..5]) & 0xFF
            var csum = (headerByte + headerByte) & 0xFF;
            for (var j = 0; j < 6; j++) {
              csum = (csum + _buf[j]) & 0xFF;
            }

            final packetChecksum = _buf[6];
            if (csum == packetChecksum) {
              final distCm = _buf[0] | (_buf[1] << 8);
              final strength = _buf[2] | (_buf[3] << 8);
              final rawTemp = _buf[4] | (_buf[5] << 8);
              final tempC = (rawTemp / 8.0) - 256.0;

              final distanceM = distCm * 0.01;
              final quality = (strength / 10).clamp(0, 100).toInt();
              final valid = strength > 100 && distCm > 0;

              final packet = UartRadarPacket(
                distanceM: distanceM,
                signalQuality: quality,
                strength: strength,
                temperatureC: tempC,
                valid: valid,
              );

              _controller.add(packet);
              onReading(distanceM, quality, valid);
              _state = 0;
            } else {
              // Checksum mismatch: resynchronize state machine
              _state = 0;
            }
          }
          break;
      }
    }
  }

  /// Resets parser internal state and buffer index.
  void reset() {
    _state = 0;
    _bufIdx = 0;
  }

  /// Closes internal stream controller.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Utility function to encode distance, strength, and temperature into a standard 9-byte packet.
  static List<int> encodePacket({
    required int distCm,
    required int strength,
    int tempRaw = 2248, // approx 25°C
  }) {
    final distL = distCm & 0xFF;
    final distH = (distCm >> 8) & 0xFF;
    final strL = strength & 0xFF;
    final strH = (strength >> 8) & 0xFF;
    final tempL = tempRaw & 0xFF;
    final tempH = (tempRaw >> 8) & 0xFF;

    final csum = (headerByte + headerByte + distL + distH + strL + strH + tempL + tempH) & 0xFF;

    return [
      headerByte,
      headerByte,
      distL,
      distH,
      strL,
      strH,
      tempL,
      tempH,
      csum,
    ];
  }
}
