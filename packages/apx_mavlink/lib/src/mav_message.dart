// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:typed_data';

/// Base class of every generated message.
abstract class MavMessage {
  const MavMessage();

  int get id;
  String get name;

  /// Full payload length including extension fields.
  int get payloadLength;

  /// Writes the payload in wire order into [d] (length ≥ [payloadLength]).
  void encodeInto(ByteData d);

  /// Field name → value, for the inspector and logs.
  Map<String, Object> toMap();

  /// Full payload; MAVLink v2 trailing‑zero truncation is applied by the framer.
  Uint8List encodePayload() {
    final bytes = Uint8List(payloadLength);
    encodeInto(ByteData.sublistView(bytes));
    return bytes;
  }

  static String readString(ByteData d, int offset, int length) {
    final bytes = <int>[];
    for (var i = 0; i < length; i++) {
      final b = d.getUint8(offset + i);
      if (b == 0) break;
      bytes.add(b);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static void writeString(ByteData d, int offset, int length, String value) {
    final bytes = utf8.encode(value);
    for (var i = 0; i < length && i < bytes.length; i++) {
      d.setUint8(offset + i, bytes[i]);
    }
  }

  @override
  String toString() => '$name${toMap()}';
}
