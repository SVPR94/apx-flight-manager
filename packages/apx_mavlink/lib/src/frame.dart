// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:typed_data';

import 'crc.dart';
import 'generated/crc_table.g.dart';
import 'generated/messages.g.dart';
import 'mav_message.dart';

const int kMagicV1 = 0xFE;
const int kMagicV2 = 0xFD;
const int kIncompatSigned = 0x01;
const int kSignatureLength = 13;

/// One validated MAVLink frame as it arrived on a link.
final class MavlinkFrame {
  MavlinkFrame({
    required this.version,
    required this.sequence,
    required this.systemId,
    required this.componentId,
    required this.messageId,
    required this.payload,
    required this.raw,
    this.incompatFlags = 0,
    this.compatFlags = 0,
  });

  final int version; // 1 or 2
  final int sequence;
  final int systemId;
  final int componentId;
  final int messageId;
  final int incompatFlags;
  final int compatFlags;

  /// Payload exactly as received (v2 frames may be truncated).
  final Uint8List payload;

  /// Complete frame bytes, for logging (.tlog) and forwarding.
  final Uint8List raw;

  MavMessage? _message;
  bool _decoded = false;

  /// Typed message, or null when the id has no generated class.
  MavMessage? get message {
    if (!_decoded) {
      _decoded = true;
      final meta = kMessageMeta[messageId];
      final full = Uint8List(meta?.maxLength ?? payload.length)
        ..setRange(0, payload.length.clamp(0, meta?.maxLength ?? payload.length), payload);
      _message = decodeKnownMessage(messageId, ByteData.sublistView(full));
    }
    return _message;
  }

  String get messageName => kMessageMeta[messageId]?.name ?? 'MSG_$messageId';
}

/// Builds outgoing MAVLink v2 frames with a running sequence number.
final class MavFrameWriter {
  MavFrameWriter({this.systemId = 255, this.componentId = 190});

  /// APX's own tools and GCS use 255 for the GCS; 190 = standard GCS component id.
  final int systemId;
  final int componentId;
  int _sequence = 0;

  /// Sequence number the next frame will carry.
  int get sequence => _sequence;
  set sequence(int value) => _sequence = value & 0xFF;

  Uint8List encode(MavMessage message) {
    final meta = kMessageMeta[message.id];
    if (meta == null) {
      throw ArgumentError('No CRC_EXTRA for message ${message.id}');
    }
    final payload = message.encodePayload();
    // v2 trailing‑zero truncation; at least one payload byte stays.
    var len = payload.length;
    while (len > 1 && payload[len - 1] == 0) {
      len--;
    }
    final frame = Uint8List(10 + len + 2);
    frame[0] = kMagicV2;
    frame[1] = len;
    frame[2] = 0; // incompat flags (no signing)
    frame[3] = 0; // compat flags
    frame[4] = _sequence;
    frame[5] = systemId;
    frame[6] = componentId;
    frame[7] = message.id & 0xFF;
    frame[8] = (message.id >> 8) & 0xFF;
    frame[9] = (message.id >> 16) & 0xFF;
    frame.setRange(10, 10 + len, payload);
    var crc = MavCrc.compute(frame, 1, 10 + len);
    crc = MavCrc.accumulate(meta.crcExtra, crc);
    frame[10 + len] = crc & 0xFF;
    frame[11 + len] = crc >> 8;
    _sequence = (_sequence + 1) & 0xFF;
    return frame;
  }
}
