// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

/// Represents a raw CAN radar frame.
final class CanRadarFrame {
  const CanRadarFrame(this.id, this.data, this.dlc);

  /// 11-bit or 29-bit CAN identifier.
  final int id;

  /// Payload bytes (up to 8 bytes).
  final List<int> data;

  /// Data Length Code.
  final int dlc;
}

/// Decoded CAN radar reading.
final class CanRadarReading {
  const CanRadarReading({
    required this.sector,
    required this.distanceM,
    required this.angleDeg,
    required this.signalQuality,
    required this.valid,
  });

  /// Radar sector / channel index (0..9).
  final int sector;

  /// Measured distance in meters.
  final double distanceM;

  /// Pointing / azimuth angle in degrees.
  final int angleDeg;

  /// Signal quality percentage (0..100%).
  final int signalQuality;

  /// Whether measurement is valid.
  final bool valid;
}

/// Pure Dart parser for CAN radar frames.
///
/// Base CAN ID is typically 0x200. Channels 0..9 map to CAN IDs (baseCanId + 0)
/// through (baseCanId + 9).
///
/// Frame payload layout:
/// - data[0]: Distance low byte (cm)
/// - data[1]: Distance high byte (cm)
/// - data[2]: Angle low byte (0.1 deg)
/// - data[3]: Angle high byte (0.1 deg)
/// - data[4]: Signal quality (0..100%), optional (defaults to 100 if DLC == 4)
final class CanRadarParser {
  CanRadarParser({this.baseCanId = defaultBaseCanId});

  static const int defaultBaseCanId = 0x200;
  static const int channelCount = 10;

  /// Base CAN identifier.
  final int baseCanId;

  final _controller = StreamController<CanRadarReading>.broadcast();

  /// Stream of successfully decoded CAN radar readings.
  Stream<CanRadarReading> get readings => _controller.stream;

  /// Parses an incoming [CanRadarFrame].
  ///
  /// Returns `true` if frame ID belongs to this radar system and DLC is valid,
  /// invoking [onReading] with parsed sector, distance, angle, and quality.
  bool parseFrame(
    CanRadarFrame frame,
    void Function(int sector, double distanceM, int angleDeg, int quality) onReading,
  ) {
    if (frame.id < baseCanId || frame.id >= baseCanId + channelCount) {
      return false;
    }

    if (frame.dlc < 4 || frame.data.length < 4) {
      return false;
    }

    final sector = frame.id - baseCanId;
    final distCm = (frame.data[1] << 8) | frame.data[0];
    final angle01Deg = (frame.data[3] << 8) | frame.data[2];

    final rawQuality = (frame.dlc >= 5 && frame.data.length >= 5) ? frame.data[4] : 100;
    final quality = rawQuality.clamp(0, 100);

    final distanceM = distCm * 0.01;
    final angleDeg = (angle01Deg * 0.1).round();

    final reading = CanRadarReading(
      sector: sector,
      distanceM: distanceM,
      angleDeg: angleDeg,
      signalQuality: quality,
      valid: distCm > 0 && quality > 10,
    );

    _controller.add(reading);
    onReading(sector, distanceM, angleDeg, quality);
    return true;
  }

  /// Closes internal stream controller.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Encodes parameters into a [CanRadarFrame] matching the CAN radar protocol.
  static CanRadarFrame encodeFrame({
    int baseCanId = defaultBaseCanId,
    required int sector,
    required int distCm,
    required int angleDeg,
    int quality = 100,
  }) {
    if (sector < 0 || sector >= channelCount) {
      throw ArgumentError.value(sector, 'sector', 'Sector must be between 0 and 9');
    }

    final angle01Deg = (angleDeg * 10).round() & 0xFFFF;
    final data = [
      distCm & 0xFF,
      (distCm >> 8) & 0xFF,
      angle01Deg & 0xFF,
      (angle01Deg >> 8) & 0xFF,
      quality.clamp(0, 100),
    ];

    return CanRadarFrame(baseCanId + sector, data, 5);
  }
}
