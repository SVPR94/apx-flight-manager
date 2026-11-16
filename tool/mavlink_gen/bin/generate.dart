// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
/// writes `packages/apx_mavlink/lib/src/generated/*.g.dart`.
///
/// Only the messages in [kMessages] get typed classes; every message in the
/// dialect gets a CRC table entry so unknown frames can still be validated.
library;

import 'dart:io';

import 'package:xml/xml.dart';

/// Messages APX sends or accepts (docs/01_APX_CAPABILITY_MATRIX.md §3–5).
const kMessages = <String>{
  'HEARTBEAT',
  'SYS_STATUS',
  'SET_MODE',
  'PARAM_REQUEST_READ',
  'PARAM_REQUEST_LIST',
  'PARAM_VALUE',
  'PARAM_SET',
  'GPS_RAW_INT',
  'ATTITUDE',
  'GLOBAL_POSITION_INT',
  'SERVO_OUTPUT_RAW',
  'MISSION_REQUEST',
  'MISSION_CURRENT',
  'MISSION_REQUEST_LIST',
  'MISSION_COUNT',
  'MISSION_CLEAR_ALL',
  'MISSION_ITEM_REACHED',
  'MISSION_ACK',
  'MISSION_REQUEST_INT',
  'RC_CHANNELS',
  'MANUAL_CONTROL',
  'RC_CHANNELS_OVERRIDE',
  'MISSION_ITEM_INT',
  'VFR_HUD',
  'COMMAND_INT',
  'COMMAND_LONG',
  'COMMAND_ACK',
  'SET_POSITION_TARGET_LOCAL_NED',
  'SET_POSITION_TARGET_GLOBAL_INT',
  'HIGHRES_IMU',
  'GPS2_RAW',
  'BATTERY_STATUS',
  'AUTOPILOT_VERSION',
  'WIND',
  'STATUSTEXT',
  'FENCE_STATUS',
  'HOME_POSITION',
};

/// Enums emitted as integer constant holders.
const kEnums = <String>{
  'MAV_TYPE',
  'MAV_AUTOPILOT',
  'MAV_MODE_FLAG',
  'MAV_STATE',
  'MAV_CMD',
  'MAV_RESULT',
  'MAV_FRAME',
  'MAV_MISSION_RESULT',
  'MAV_MISSION_TYPE',
  'MAV_SEVERITY',
  'MAV_PARAM_TYPE',
  'GPS_FIX_TYPE',
  'MAV_SYS_STATUS_SENSOR',
  'MAV_PROTOCOL_CAPABILITY',
  'POSITION_TARGET_TYPEMASK',
};

void main(List<String> args) {
  final root = Directory.current.path;
  final defs = '$root/tool/mavlink_gen/definitions';
  final out = '$root/packages/apx_mavlink/lib/src/generated';

  final dialect = Dialect()..load(File('$defs/apxmega.xml'));
  final selected = dialect.messages.where((m) => kMessages.contains(m.name)).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final missing = kMessages.difference(selected.map((m) => m.name).toSet());
  if (missing.isNotEmpty) {
    stderr.writeln('Messages not found in definitions: $missing');
    exit(1);
  }

  Directory(out).createSync(recursive: true);
  File('$out/crc_table.g.dart').writeAsStringSync(_crcTable(dialect));
  File('$out/messages.g.dart').writeAsStringSync(_messages(selected));
  File('$out/enums.g.dart').writeAsStringSync(_enums(dialect));
  stdout.writeln(
    'Generated ${selected.length} messages, '
    '${dialect.messages.length} CRC entries, '
    '${dialect.enums.where((e) => kEnums.contains(e.name)).length} enums.',
  );
}

// ---------------------------------------------------------------- model

class Field {
  Field(this.type, this.name, this.arrayLength, this.isExtension, this.description);

  /// Base C type, e.g. `uint16_t`, `char`, `float`.
  final String type;
  final String name;
  final int arrayLength; // 0 = scalar
  final bool isExtension;
  final String description;

  int get typeSize => switch (type) {
    'double' || 'int64_t' || 'uint64_t' => 8,
    'float' || 'int32_t' || 'uint32_t' => 4,
    'int16_t' || 'uint16_t' => 2,
    'int8_t' || 'uint8_t' || 'char' => 1,
    _ => throw StateError('Unknown type $type'),
  };

  int get wireSize => typeSize * (arrayLength == 0 ? 1 : arrayLength);
}

class Message {
  Message(this.id, this.name, this.fields, this.description);
  final int id;
  final String name;
  final List<Field> fields; // declaration order
  final String description;

  /// Wire order: base fields sorted by type size (stable), then extensions.
  List<Field> get wireOrder {
    final base = fields.where((f) => !f.isExtension).toList();
    final indexed = [for (var i = 0; i < base.length; i++) (i, base[i])];
    indexed.sort((a, b) {
      final c = b.$2.typeSize.compareTo(a.$2.typeSize);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [...indexed.map((e) => e.$2), ...fields.where((f) => f.isExtension)];
  }

  int get minLength => fields.where((f) => !f.isExtension).fold(0, (s, f) => s + f.wireSize);
  int get maxLength => fields.fold(0, (s, f) => s + f.wireSize);

  int get crcExtra {
    var crc = 0xFFFF;
    void acc(int b) {
      var tmp = (b ^ (crc & 0xFF)) & 0xFF;
      tmp = (tmp ^ (tmp << 4)) & 0xFF;
      crc = ((crc >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4)) & 0xFFFF;
    }

    void str(String s) => s.codeUnits.forEach(acc);
    str('$name ');
    for (final f in wireOrder.where((f) => !f.isExtension)) {
      str('${f.type} ');
      str('${f.name} ');
      if (f.arrayLength > 0) acc(f.arrayLength);
    }
    return ((crc & 0xFF) ^ (crc >> 8)) & 0xFF;
  }
}

class EnumEntry {
  EnumEntry(this.name, this.value, this.description);
  final String name;
  final int value;
  final String description;
}

class MavEnum {
  MavEnum(this.name, this.entries, this.description);
  final String name;
  final List<EnumEntry> entries;
  final String description;
}

class Dialect {
  final messages = <Message>[];
  final enums = <MavEnum>[];
  final _loaded = <String>{};
  final _enumIndex = <String, MavEnum>{};

  void load(File file) {
    final path = file.absolute.path;
    if (!_loaded.add(path)) return;
    final doc = XmlDocument.parse(file.readAsStringSync());
    final root = doc.rootElement;
    for (final inc in root.findElements('include')) {
      load(File('${file.parent.path}/${inc.innerText.trim()}'));
    }
    for (final e in root.findAllElements('enum')) {
      final name = e.getAttribute('name')!;
      final entries = [
        for (final en in e.findElements('entry'))
          if (en.getAttribute('value') != null)
            EnumEntry(en.getAttribute('name')!, _parseInt(en.getAttribute('value')!), _desc(en)),
      ];
      // Enums may be split across included files; merge entries.
      final existing = _enumIndex[name];
      if (existing != null) {
        existing.entries.addAll(entries);
      } else {
        final me = MavEnum(name, entries, _desc(e));
        _enumIndex[name] = me;
        enums.add(me);
      }
    }
    for (final m in root.findAllElements('message')) {
      final id = int.parse(m.getAttribute('id')!);
      if (messages.any((x) => x.id == id)) continue;
      var ext = false;
      final fields = <Field>[];
      for (final child in m.childElements) {
        if (child.name.local == 'extensions') {
          ext = true;
        } else if (child.name.local == 'field') {
          var t = child.getAttribute('type')!;
          var len = 0;
          final br = RegExp(r'^(\w+)\[(\d+)\]$').firstMatch(t);
          if (br != null) {
            t = br.group(1)!;
            len = int.parse(br.group(2)!);
          }
          if (t == 'uint8_t_mavlink_version') t = 'uint8_t';
          fields.add(Field(t, child.getAttribute('name')!, len, ext, child.innerText.trim()));
        }
      }
      messages.add(Message(id, m.getAttribute('name')!, fields, _desc(m)));
    }
  }

  static String _desc(XmlElement e) {
    final d = e.getElement('description');
    return (d?.innerText ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static int _parseInt(String v) {
    v = v.trim();
    final pow = RegExp(r'^2\*\*(\d+)$').firstMatch(v);
    if (pow != null) return 1 << int.parse(pow.group(1)!);
    if (v.startsWith('0x') || v.startsWith('0X')) return int.parse(v.substring(2), radix: 16);
    return int.parse(v);
  }
}

// ---------------------------------------------------------------- emitters

const _header =
    '// GENERATED by tool/mavlink_gen — do not edit by hand.\n'
    '// Source: MAVLink XML definitions (MIT), see tool/mavlink_gen/definitions.\n'
    '// ignore_for_file: constant_identifier_names, lines_longer_than_80_chars\n\n';

String _crcTable(Dialect d) {
  final b = StringBuffer(_header)
    ..writeln("import '../message_meta.dart';\n")
    ..writeln('/// Every message in the dialect: id → (name, CRC_EXTRA, min and max payload length).')
    ..writeln('const Map<int, MessageMeta> kMessageMeta = {');
  final sorted = [...d.messages]..sort((a, b) => a.id.compareTo(b.id));
  for (final m in sorted) {
    b.writeln("  ${m.id}: MessageMeta(${m.id}, '${m.name}', ${m.crcExtra}, ${m.minLength}, ${m.maxLength}),");
  }
  b.writeln('};');
  return b.toString();
}

/// Field names that would shadow [MavMessage] members.
const _reserved = {'id': 'instanceId', 'name': 'nameField'};

String _camel(String snake, {bool upper = false}) {
  if (!upper && _reserved.containsKey(snake)) return _reserved[snake]!;
  final parts = snake.toLowerCase().split('_').where((p) => p.isNotEmpty).toList();
  final s = parts.indexed.map((e) => (e.$1 == 0 && !upper) ? e.$2 : e.$2[0].toUpperCase() + e.$2.substring(1)).join();
  return s;
}

String _dartType(Field f) {
  if (f.type == 'char' && f.arrayLength > 0) return 'String';
  final scalar = (f.type == 'float' || f.type == 'double') ? 'double' : 'int';
  return f.arrayLength > 0 ? 'List<$scalar>' : scalar;
}

String _default(Field f) {
  if (f.type == 'char' && f.arrayLength > 0) return "''";
  if (f.arrayLength > 0) return 'const []';
  return (f.type == 'float' || f.type == 'double') ? '0.0' : '0';
}

String _getter(String type, String off) => switch (type) {
  'uint8_t' || 'char' => 'd.getUint8($off)',
  'int8_t' => 'd.getInt8($off)',
  'uint16_t' => 'd.getUint16($off, Endian.little)',
  'int16_t' => 'd.getInt16($off, Endian.little)',
  'uint32_t' => 'd.getUint32($off, Endian.little)',
  'int32_t' => 'd.getInt32($off, Endian.little)',
  'uint64_t' => 'd.getUint64($off, Endian.little)',
  'int64_t' => 'd.getInt64($off, Endian.little)',
  'float' => 'd.getFloat32($off, Endian.little)',
  'double' => 'd.getFloat64($off, Endian.little)',
  _ => throw StateError(type),
};

String _setter(String type, String off, String v) => switch (type) {
  'uint8_t' || 'char' => 'd.setUint8($off, $v)',
  'int8_t' => 'd.setInt8($off, $v)',
  'uint16_t' => 'd.setUint16($off, $v, Endian.little)',
  'int16_t' => 'd.setInt16($off, $v, Endian.little)',
  'uint32_t' => 'd.setUint32($off, $v, Endian.little)',
  'int32_t' => 'd.setInt32($off, $v, Endian.little)',
  'uint64_t' => 'd.setUint64($off, $v, Endian.little)',
  'int64_t' => 'd.setInt64($off, $v, Endian.little)',
  'float' => 'd.setFloat32($off, $v, Endian.little)',
  'double' => 'd.setFloat64($off, $v, Endian.little)',
  _ => throw StateError(type),
};

String _messages(List<Message> msgs) {
  final b = StringBuffer(_header)
    ..writeln("import 'dart:typed_data';\n")
    ..writeln("import '../mav_message.dart';\n");

  for (final m in msgs) {
    final cls = _camel(m.name, upper: true);
    final wire = m.wireOrder;
    final offsets = <Field, int>{};
    var off = 0;
    for (final f in wire) {
      offsets[f] = off;
      off += f.wireSize;
    }
    if (m.description.isNotEmpty) b.writeln('/// ${m.description}');
    b.writeln('final class $cls extends MavMessage {');
    b.writeln('  const $cls({');
    for (final f in m.fields) {
      b.writeln('    this.${_camel(f.name)} = ${_default(f)},');
    }
    b.writeln('  });\n');
    b.writeln('  static const int msgId = ${m.id};');
    b.writeln('  static const int crcExtra = ${m.crcExtra};');
    b.writeln('  static const int minLength = ${m.minLength};');
    b.writeln('  static const int maxLength = ${m.maxLength};\n');
    for (final f in m.fields) {
      final doc = f.description.replaceAll(RegExp(r'\s+'), ' ');
      if (doc.isNotEmpty) b.writeln('  /// $doc${f.isExtension ? ' (extension)' : ''}');
      b.writeln('  final ${_dartType(f)} ${_camel(f.name)};');
    }
    b.writeln('\n  @override\n  int get id => msgId;');
    b.writeln("\n  @override\n  String get name => '${m.name}';");
    b.writeln('\n  @override\n  int get payloadLength => maxLength;');

    // decode
    b.writeln('\n  /// Decodes a payload already zero‑padded to [maxLength].');
    b.writeln('  factory $cls.decode(ByteData d) => $cls(');
    for (final f in m.fields) {
      final o = offsets[f]!;
      final n = _camel(f.name);
      if (f.type == 'char' && f.arrayLength > 0) {
        b.writeln('        $n: MavMessage.readString(d, $o, ${f.arrayLength}),');
      } else if (f.arrayLength > 0) {
        b.writeln(
          '        $n: [for (var i = 0; i < ${f.arrayLength}; i++) ${_getter(f.type, '$o + i * ${f.typeSize}')}],',
        );
      } else {
        b.writeln('        $n: ${_getter(f.type, '$o')},');
      }
    }
    b.writeln('      );');

    // encode
    b.writeln('\n  @override\n  void encodeInto(ByteData d) {');
    for (final f in wire) {
      final o = offsets[f]!;
      final n = _camel(f.name);
      if (f.type == 'char' && f.arrayLength > 0) {
        b.writeln('    MavMessage.writeString(d, $o, ${f.arrayLength}, $n);');
      } else if (f.arrayLength > 0) {
        b.writeln('    for (var i = 0; i < ${f.arrayLength} && i < $n.length; i++) {');
        b.writeln('      ${_setter(f.type, '$o + i * ${f.typeSize}', '$n[i]')};');
        b.writeln('    }');
      } else {
        b.writeln('    ${_setter(f.type, '$o', n)};');
      }
    }
    b.writeln('  }');

    // toMap
    b.writeln('\n  @override\n  Map<String, Object> toMap() => {');
    for (final f in m.fields) {
      b.writeln("        '${f.name}': ${_camel(f.name)},");
    }
    b.writeln('      };');
    b.writeln('}\n');
  }

  b.writeln('/// Decodes a known message, or returns null for an id without a typed class.');
  b.writeln('MavMessage? decodeKnownMessage(int id, ByteData payload) => switch (id) {');
  for (final m in msgs) {
    b.writeln('      ${m.id} => ${_camel(m.name, upper: true)}.decode(payload),');
  }
  b.writeln('      _ => null,');
  b.writeln('    };');
  return b.toString();
}

String _enums(Dialect d) {
  final b = StringBuffer(_header);
  for (final e in d.enums.where((e) => kEnums.contains(e.name))) {
    final cls = _camel(e.name, upper: true);
    if (e.description.isNotEmpty) b.writeln('/// ${e.description}');
    b.writeln('abstract final class $cls {');
    final prefix = '${e.name}_';
    final seen = <String>{};
    for (final en in e.entries) {
      var n = en.name.startsWith(prefix) ? en.name.substring(prefix.length) : en.name;
      n = _camel(n);
      if (RegExp(r'^\d').hasMatch(n)) n = 'v$n';
      if (!seen.add(n)) continue;
      if (en.description.isNotEmpty) b.writeln('  /// ${en.description}');
      b.writeln('  static const int $n = ${en.value};');
    }
    b.writeln('\n  /// Entry names by value (for display).');
    b.writeln('  static const Map<int, String> names = {');
    final vals = <int>{};
    for (final en in e.entries) {
      if (vals.add(en.value)) b.writeln("    ${en.value}: '${en.name}',");
    }
    b.writeln('  };');
    b.writeln('}\n');
  }
  return b.toString();
}
