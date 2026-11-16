// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';

import 'package:apx_flight_manager/shell/exit_dialog.dart';
import 'package:apx_flight_manager/state/audio.dart';
import 'package:apx_flight_manager/state/map_tiles.dart';
import 'package:apx_flight_manager/state/storage.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fresh, empty data folder for one test.
Directory tempDataDir() {
  final d = Directory.systemTemp.createTempSync('apx_fm_test_');
  addTearDown(() {
    if (d.existsSync()) d.deleteSync(recursive: true);
  });
  return d;
}

/// Overrides for running the app in tests. Widget tests run on a fake clock
/// where a real HTTP server can't make progress, so by default the tile
/// engine never starts (the map shows no tiles); pass [engine] for tests
/// that drive real I/O.
List<Override> testOverrides(Directory dataDir, {bool engine = false, ExitHandler? exitHandler}) => [
  dataDirProvider.overrideWithValue(dataDir),
  audioProcessRunnerProvider.overrideWithValue((exe, args) async => ProcessResult(0, 0, '', '')),
  appExitHandlerProvider.overrideWithValue(exitHandler ?? (code) {}),
  if (!engine) tileEngineProvider.overrideWith((ref) => Completer<TileEngine>().future),
];
