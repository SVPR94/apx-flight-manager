// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The app's data folder: settings.json, tiles.db (map cache and rendered
/// overlays) and overlays/ (copies of imported files).
///
/// Resolved once in `main` and injected, so tests can point it at a temp dir.
final dataDirProvider = Provider<Directory>((ref) => throw UnimplementedError('dataDirProvider is set in main()'));

Future<Directory> resolveDataDir() async {
  final dir = await getApplicationSupportDirectory();
  dir.createSync(recursive: true);
  if (Platform.isLinux || Platform.isMacOS) {
    // Holds API keys: keep it private to this user.
    await Process.run('chmod', ['700', dir.path]);
  }
  return dir;
}

/// Small JSON key/value store for user settings. Writes are debounced and
/// atomic (temp file + rename), so a crash never leaves a half‑written file.
final class SettingsStore {
  SettingsStore._(this.file, this._data);

  factory SettingsStore.open(Directory dir) {
    final f = File('${dir.path}${Platform.pathSeparator}settings.json');
    var data = <String, Object?>{};
    if (f.existsSync()) {
      try {
        data = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
      } catch (_) {
        // Unreadable: keep a copy for inspection and start fresh.
        f.copySync('${f.path}.bad');
      }
    }
    return SettingsStore._(f, data);
  }

  final File file;
  final Map<String, Object?> _data;
  Timer? _pending;

  T? get<T>(String key) {
    final v = _data[key];
    return v is T ? v : null;
  }

  void set(String key, Object? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 300), flush);
  }

  void flush() {
    _pending?.cancel();
    _pending = null;
    // The data folder was removed under us (e.g. a finished test): nothing to save into.
    if (!file.parent.existsSync()) return;
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(_data), flush: true);
    tmp.renameSync(file.path);
  }
}

final settingsStoreProvider = Provider<SettingsStore>((ref) {
  final store = SettingsStore.open(ref.watch(dataDirProvider));
  ref.onDispose(store.flush);
  return store;
});
