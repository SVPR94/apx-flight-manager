// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:typed_data';

/// CRC‑16/MCRF4XX (X.25 seed 0xFFFF, no final xor) as used by MAVLink.
abstract final class MavCrc {
  static const int seed = 0xFFFF;

  static int accumulate(int byte, int crc) {
    var tmp = (byte ^ (crc & 0xFF)) & 0xFF;
    tmp = (tmp ^ (tmp << 4)) & 0xFF;
    return ((crc >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4)) & 0xFFFF;
  }

  static int compute(Uint8List bytes, int start, int end, [int crc = seed]) {
    for (var i = start; i < end; i++) {
      crc = accumulate(bytes[i], crc);
    }
    return crc;
  }
}
