// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:apx_flight_manager/video/video_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  test('recording names sort by time', () {
    expect(recordingStem(DateTime(2026, 3, 4, 5, 6, 7)), 'APX_2026-03-04_05-06-07');
  });

  test('lists only this app\'s media, newest first', () {
    final d = tempDataDir();
    File('${d.path}/APX_a.mkv').writeAsStringSync('1');
    File('${d.path}/APX_b.jpg').writeAsStringSync('1');
    File('${d.path}/notes.mkv').writeAsStringSync('1');
    File('${d.path}/APX_c.txt').writeAsStringSync('1');
    File('${d.path}/APX_a.mkv').setLastModifiedSync(DateTime(2020));
    expect(listMedia(d).map((f) => f.uri.pathSegments.last), ['APX_b.jpg', 'APX_a.mkv']);
    expect(listMedia(d, snapshots: false).map((f) => f.uri.pathSegments.last), ['APX_a.mkv']);
    expect(listMedia(Directory('${d.path}/missing')), isEmpty);
  });

  test('storage limit deletes oldest recordings only down to the limit', () {
    final d = tempDataDir();
    for (var i = 1; i <= 4; i++) {
      File('${d.path}/APX_$i.mp4')
        ..writeAsBytesSync(List.filled(1000, 0))
        ..setLastModifiedSync(DateTime(2020, 1, i));
    }
    File('${d.path}/APX_snap.jpg').writeAsBytesSync(List.filled(5000, 0));
    final removed = enforceStorageLimit(d, 2500);
    expect(removed.map((f) => f.uri.pathSegments.last), ['APX_1.mp4', 'APX_2.mp4']);
    expect(File('${d.path}/APX_snap.jpg').existsSync(), isTrue, reason: 'snapshots are not recordings');
    expect(enforceStorageLimit(d, 0), isEmpty, reason: '0 = no limit');
  });

  test('free space agrees with df', () async {
    final d = tempDataDir();
    final free = freeBytes(d.path);
    expect(free, isNotNull);
    final df = await Process.run('df', ['-Pk', d.path]);
    final availKb = int.parse((df.stdout as String).trim().split('\n').last.split(RegExp(r'\s+'))[3]);
    // Same syscall underneath; a wrong struct layout would be off by orders
    // of magnitude. Allow for other tests/processes writing meanwhile.
    expect((free! / 1024 - availKb).abs(), lessThan(512 * 1024));
  }, skip: !(Platform.isLinux || Platform.isMacOS));

  test('default folder is under the user\'s videos', () async {
    final d = await defaultRecordingDir();
    expect(d.path, contains('APX Flight Manager'));
  }, skip: !Platform.isLinux);

  test('byte formatting', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
    expect(formatBytes(5 * 1024 * 1024 * 1024), '5.00 GB');
  });
}
