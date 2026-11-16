// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

/// Default folder for recordings and snapshots on this platform:
/// - Windows: `%USERPROFILE%\Videos\APX Flight Manager`
/// - Linux: the XDG videos folder (usually `~/Videos`) + `APX Flight Manager`
/// - macOS (sandboxed): the app's Documents folder + `Video`
/// - Android: the app's own Movies folder (no storage permission needed;
///   `Android/data/<app>/files/Movies`); finished files can also be copied to
///   the gallery
/// - iOS: the app's Documents folder + `Video` (visible in the Files app)
Future<Directory> defaultRecordingDir() async {
  const name = 'APX Flight Manager';
  String path;
  if (Platform.isAndroid) {
    final dirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
    path = (dirs != null && dirs.isNotEmpty)
        ? dirs.first.path
        : '${(await getApplicationDocumentsDirectory()).path}/Video';
  } else if (Platform.isIOS || Platform.isMacOS) {
    path = '${(await getApplicationDocumentsDirectory()).path}/Video';
  } else if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'] ?? (await getApplicationDocumentsDirectory()).path;
    path = '$home\\Videos\\$name';
  } else {
    path = '${_xdgVideosDir() ?? '${Platform.environment['HOME'] ?? '.'}/Videos'}/$name';
  }
  return Directory(path);
}

/// XDG_VIDEOS_DIR from ~/.config/user-dirs.dirs (localised folder names).
String? _xdgVideosDir() {
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  final env = Platform.environment['XDG_VIDEOS_DIR'];
  if (env != null && env.isNotEmpty) return env;
  final f = File('${Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config'}/user-dirs.dirs');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final m = RegExp(r'^XDG_VIDEOS_DIR="(.*)"').firstMatch(line.trim());
    if (m != null) {
      final v = m.group(1)!.replaceAll(r'$HOME', home);
      // "$HOME/" means "no videos folder configured".
      return v == home || v == '$home/' ? null : v;
    }
  }
  return null;
}

/// File name stem for a new recording: `APX_2026-11-07_14-03-22`.
String recordingStem(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'APX_${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
}

const recordingExtensions = {'mkv', 'mp4', 'mov'};
const snapshotExtensions = {'jpg'};

/// Recordings and snapshots this app wrote into [dir], newest first.
List<File> listMedia(Directory dir, {bool snapshots = true}) {
  if (!dir.existsSync()) return const [];
  final exts = {...recordingExtensions, if (snapshots) ...snapshotExtensions};
  final files = <(File, DateTime)>[];
  for (final e in dir.listSync(followLinks: false)) {
    if (e is! File) continue;
    final name = e.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    if (!name.startsWith('APX_') || dot < 0 || !exts.contains(name.substring(dot + 1).toLowerCase())) continue;
    try {
      files.add((e, e.lastModifiedSync()));
    } catch (_) {}
  }
  files.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final f in files) f.$1];
}

/// Deletes the oldest recordings until the folder's recordings total at most
/// [limitBytes] minus [reserveBytes] (room for the one about to start). Only
/// files this app named are touched. Returns the deleted files.
List<File> enforceStorageLimit(Directory dir, int limitBytes, {int reserveBytes = 0, Set<String> keep = const {}}) {
  if (limitBytes <= 0) return const [];
  final files = listMedia(dir, snapshots: false).reversed.toList(); // oldest first
  var total = files.fold<int>(0, (s, f) => s + _size(f));
  final deleted = <File>[];
  for (final f in files) {
    if (total + reserveBytes <= limitBytes) break;
    if (keep.contains(f.path)) continue;
    final size = _size(f);
    try {
      f.deleteSync();
      total -= size;
      deleted.add(f);
    } catch (_) {}
  }
  return deleted;
}

int _size(File f) {
  try {
    return f.lengthSync();
  } catch (_) {
    return 0;
  }
}

/// Bytes free for this user on the volume holding [path], or null when the
/// platform call isn't available (then the recorder relies on write checks).
int? freeBytes(String path) {
  try {
    if (Platform.isWindows) return _freeWindows(path);
    if (Platform.isLinux || Platform.isAndroid || Platform.isMacOS || Platform.isIOS) return _freeStatvfs(path);
  } catch (_) {}
  return null;
}

typedef _StatvfsC = Int32 Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _StatvfsDart = int Function(Pointer<Utf8>, Pointer<Uint8>);

int? _freeStatvfs(String path) {
  // struct statvfs starts with: unsigned long f_bsize, f_frsize; then
  // fsblkcnt_t f_blocks, f_bfree, f_bavail. fsblkcnt_t is 64-bit on 64-bit
  // glibc/bionic and 32-bit on Darwin. 32-bit Android isn't handled (null).
  if (sizeOf<IntPtr>() != 8) return null;
  final darwin = Platform.isMacOS || Platform.isIOS;
  final fn = DynamicLibrary.process().lookupFunction<_StatvfsC, _StatvfsDart>('statvfs');
  final buf = calloc<Uint8>(512);
  final p = path.toNativeUtf8();
  try {
    if (fn(p, buf) != 0) return null;
    final d = buf.cast<Uint64>();
    final frsize = d[1];
    final bavail = darwin ? buf.cast<Uint32>()[6] : d[4];
    return frsize * bavail;
  } finally {
    calloc.free(buf);
    calloc.free(p);
  }
}

typedef _GetFreeC = Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetFreeDart = int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

int? _freeWindows(String path) {
  final fn = DynamicLibrary.open('kernel32.dll').lookupFunction<_GetFreeC, _GetFreeDart>('GetDiskFreeSpaceExW');
  final p = path.toNativeUtf16();
  final avail = calloc<Uint64>();
  try {
    if (fn(p, avail, nullptr, nullptr) == 0) return null;
    return avail.value;
  } finally {
    calloc.free(p);
    calloc.free(avail);
  }
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
