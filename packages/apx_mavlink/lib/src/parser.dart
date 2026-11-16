// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:typed_data';

import 'crc.dart';
import 'frame.dart';
import 'generated/crc_table.g.dart';

/// Counters a link exposes in its statistics panel.
final class ParserStats {
  int frames = 0;
  int crcErrors = 0;
  int unknownIds = 0;
  int bytesDiscarded = 0;

  /// Frames missing according to per‑sender sequence numbers.
  int sequenceLost = 0;

  double get lossRatio {
    final total = frames + sequenceLost;
    return total == 0 ? 0 : sequenceLost / total;
  }
}

/// Byte‑stream → validated frames. Accepts MAVLink v1 and v2.
///
/// Keep one parser per link: interleaving two links' bytes in one parser
/// corrupts frames (APX's firmware hit exactly this bug).
final class MavParser {
  final ParserStats stats = ParserStats();
  final Map<int, int> _nextSeq = {}; // (sysid << 8 | compid) → expected sequence

  Uint8List _buf = Uint8List(4096);
  int _start = 0;
  int _end = 0;

  /// Feeds bytes; returns every complete, CRC‑valid frame they finish.
  List<MavlinkFrame> add(List<int> bytes) {
    _append(bytes);
    final out = <MavlinkFrame>[];
    while (true) {
      // Resync to a start byte.
      while (_start < _end && _buf[_start] != kMagicV2 && _buf[_start] != kMagicV1) {
        _start++;
        stats.bytesDiscarded++;
      }
      final avail = _end - _start;
      if (avail < 3) break;
      final v2 = _buf[_start] == kMagicV2;
      final headerLen = v2 ? 10 : 6;
      if (avail < headerLen) break;
      final payloadLen = _buf[_start + 1];
      // Unknown incompat flags mean "cannot parse": drop at once instead of
      // waiting for a length that a false start byte invented.
      if (v2 && (_buf[_start + 2] & ~kIncompatSigned) != 0) {
        _skipOne();
        continue;
      }
      final signed = v2 && (_buf[_start + 2] & kIncompatSigned) != 0;
      final total = headerLen + payloadLen + 2 + (signed ? kSignatureLength : 0);
      if (avail < total) break;

      final msgId = v2 ? _buf[_start + 7] | (_buf[_start + 8] << 8) | (_buf[_start + 9] << 16) : _buf[_start + 5];
      final meta = kMessageMeta[msgId];
      if (meta == null) {
        stats.unknownIds++;
        _skipOne();
        continue;
      }
      final crcPos = _start + headerLen + payloadLen;
      var crc = MavCrc.compute(_buf, _start + 1, crcPos);
      crc = MavCrc.accumulate(meta.crcExtra, crc);
      if ((_buf[crcPos] | (_buf[crcPos + 1] << 8)) != crc) {
        stats.crcErrors++;
        _skipOne();
        continue;
      }

      final raw = Uint8List.fromList(_buf.sublist(_start, _start + total));
      final frame = MavlinkFrame(
        version: v2 ? 2 : 1,
        sequence: v2 ? raw[4] : raw[2],
        systemId: v2 ? raw[5] : raw[3],
        componentId: v2 ? raw[6] : raw[4],
        messageId: msgId,
        incompatFlags: v2 ? raw[2] : 0,
        compatFlags: v2 ? raw[3] : 0,
        payload: Uint8List.sublistView(raw, headerLen, headerLen + payloadLen),
        raw: raw,
      );
      _trackSequence(frame);
      stats.frames++;
      out.add(frame);
      _start += total;
    }
    return out;
  }

  void reset() {
    _start = _end = 0;
    _nextSeq.clear();
  }

  void _skipOne() {
    _start++;
    stats.bytesDiscarded++;
  }

  void _trackSequence(MavlinkFrame f) {
    final key = (f.systemId << 8) | f.componentId;
    final expected = _nextSeq[key];
    if (expected != null && f.sequence != expected) {
      final gap = (f.sequence - expected) & 0xFF;
      // A large backwards jump is a sender restart, not 200+ lost frames.
      if (gap < 128) stats.sequenceLost += gap;
    }
    _nextSeq[key] = (f.sequence + 1) & 0xFF;
  }

  void _append(List<int> bytes) {
    if (_end + bytes.length > _buf.length) {
      final live = _end - _start;
      final needed = live + bytes.length;
      if (needed > _buf.length) {
        final grown = Uint8List(needed * 2)..setRange(0, live, _buf, _start);
        _buf = grown;
      } else {
        _buf.setRange(0, live, _buf, _start);
      }
      _start = 0;
      _end = live;
    }
    _buf.setRange(_end, _end + bytes.length, bytes);
    _end += bytes.length;
  }
}
