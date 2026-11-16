// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:test/test.dart';

/// (id, CRC_EXTRA, base length, full length) compiled into APX firmware,
/// from apx/modules/gcs/mavlink/*/mavlink_msg_*.h (MAVLink build 2026‑09‑28).
const _firmware = <String, (int, int, int, int)>{
  'HEARTBEAT': (0, 50, 9, 9),
  'SYS_STATUS': (1, 124, 31, 43),
  'SET_MODE': (11, 89, 6, 6),
  'PARAM_REQUEST_READ': (20, 214, 20, 20),
  'PARAM_REQUEST_LIST': (21, 159, 2, 2),
  'PARAM_VALUE': (22, 220, 25, 25),
  'PARAM_SET': (23, 168, 23, 23),
  'GPS_RAW_INT': (24, 24, 30, 52),
  'ATTITUDE': (30, 39, 28, 28),
  'GLOBAL_POSITION_INT': (33, 104, 28, 28),
  'SERVO_OUTPUT_RAW': (36, 222, 21, 37),
  'MISSION_REQUEST': (40, 230, 4, 5),
  'MISSION_CURRENT': (42, 28, 2, 6),
  'MISSION_REQUEST_LIST': (43, 132, 2, 3),
  'MISSION_COUNT': (44, 221, 4, 5),
  'MISSION_CLEAR_ALL': (45, 232, 2, 3),
  'MISSION_ITEM_REACHED': (46, 11, 2, 2),
  'MISSION_ACK': (47, 153, 3, 4),
  'MISSION_REQUEST_INT': (51, 196, 4, 5),
  'RC_CHANNELS': (65, 118, 42, 42),
  'MANUAL_CONTROL': (69, 243, 11, 30),
  'RC_CHANNELS_OVERRIDE': (70, 124, 18, 38),
  'MISSION_ITEM_INT': (73, 38, 37, 38),
  'VFR_HUD': (74, 20, 20, 20),
  'COMMAND_INT': (75, 158, 35, 35),
  'COMMAND_LONG': (76, 152, 33, 33),
  'COMMAND_ACK': (77, 143, 3, 10),
  'SET_POSITION_TARGET_LOCAL_NED': (84, 143, 53, 53),
  'SET_POSITION_TARGET_GLOBAL_INT': (86, 5, 53, 53),
  'HIGHRES_IMU': (105, 93, 62, 63),
  'GPS2_RAW': (124, 87, 35, 57),
  'BATTERY_STATUS': (147, 154, 36, 54),
  'AUTOPILOT_VERSION': (148, 178, 60, 78),
  'WIND': (168, 1, 12, 12),
  'STATUSTEXT': (253, 83, 51, 54),
};

Uint8List _hex(String s) =>
    Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

void main() {
  group('matches the APX firmware build', () {
    for (final MapEntry(key: name, value: (id, crc, minLen, fwLen)) in _firmware.entries) {
      test(name, () {
        final meta = kMessageMeta[id]!;
        expect(meta.name, name);
        expect(meta.crcExtra, crc, reason: 'CRC_EXTRA');
        expect(meta.minLength, minLen, reason: 'base payload length');
        // Newer XML may add extensions APX doesn't know; never fewer.
        expect(meta.maxLength, greaterThanOrEqualTo(fwLen));
      });
    }
  });

  group('byte‑exact against pymavlink', () {
    final fixtures = (jsonDecode(File('test/fixtures/pymavlink_frames.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

    for (final f in fixtures) {
      test('${f['name']} decodes and re‑encodes identically', () {
        final bytes = _hex(f['hex'] as String);
        final frames = MavParser().add(bytes);
        expect(frames, hasLength(1));
        final frame = frames.single;
        expect(frame.messageId, f['id']);
        final msg = frame.message!;
        expect(msg.name, f['name']);

        final fields = (f['fields'] as Map).cast<String, Object?>();
        final ours = msg.toMap();
        for (final MapEntry(:key, :value) in fields.entries) {
          if (!ours.containsKey(key)) continue; // extension unknown to our XML version
          final mine = ours[key];
          if (value is double || mine is double) {
            expect((mine as num).toDouble(), closeTo((value as num).toDouble(), 1e-4), reason: key);
          } else {
            expect(mine, value, reason: key);
          }
        }

        final writer = MavFrameWriter(systemId: 1, componentId: 1)..sequence = f['seq'] as int;
        expect(writer.encode(msg), bytes);
      });
    }
  });

  group('parser', () {
    final writer = MavFrameWriter(systemId: 1, componentId: 1);
    Uint8List hb() => writer.encode(const Heartbeat(type: 2, autopilot: 3, customMode: 4));

    test('resyncs after garbage and finds frames split across reads', () {
      final p = MavParser();
      final a = hb(), b = hb();
      final stream = [0x00, 0xFD, 0x13, 0x37, ...a, 0x55, ...b];
      final out = <MavlinkFrame>[];
      for (final byte in stream) {
        out.addAll(p.add([byte]));
      }
      expect(out, hasLength(2));
      expect((out.first.message! as Heartbeat).customMode, 4);
      expect(p.stats.crcErrors + p.stats.bytesDiscarded, greaterThan(0));
    });

    test('rejects a corrupted CRC and keeps going', () {
      final p = MavParser();
      final bad = hb()..[12] ^= 0xFF;
      final out = p.add([...bad, ...hb()]);
      expect(out, hasLength(1));
      expect(p.stats.crcErrors, 1);
    });

    test('counts sequence gaps as loss', () {
      final p = MavParser();
      p.add(hb()); // seq n
      hb(); // seq n+1 never delivered
      hb(); // seq n+2 never delivered
      p.add(hb()); // seq n+3
      expect(p.stats.sequenceLost, 2);
    });

    test('decodes a truncated v2 payload with zero padding', () {
      final frame = MavParser().add(writer.encode(const CommandAck(command: 400))).single;
      expect(frame.payload.length, lessThan(CommandAck.maxLength));
      final ack = frame.message! as CommandAck;
      expect(ack.command, 400);
      expect(ack.result, 0);
    });
  });
}
