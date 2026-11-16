// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection.dart';

/// The connected vehicle's parameters, or null until a vehicle answers
/// (the session creates its services only then).
final paramServiceProvider = Provider<ParameterService?>((ref) {
  final session = ref.watch(connectionProvider)?.session;
  if (session == null) return null;
  if (!session.isBound) {
    final sub = session.state.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(sub.cancel);
    return null;
  }
  return session.parameters;
});

/// Parameter download progress (idle when not connected).
final paramProgressProvider = Provider<ParamLoadProgress>((ref) {
  final svc = ref.watch(paramServiceProvider);
  if (svc == null) return const ParamLoadProgress(ParamLoadState.idle, 0, 0);
  final sub = svc.progress.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return svc.progress.value;
});

/// Bumps when any parameter value arrives, at most ~5 times a second, so
/// lists of parameters rebuild on change rather than every frame.
final paramRevisionProvider = NotifierProvider<ParamRevision, int>(ParamRevision.new);

class ParamRevision extends Notifier<int> {
  @override
  int build() {
    final svc = ref.watch(paramServiceProvider);
    if (svc == null) return 0;
    Timer? pending;
    final sub = svc.changes.listen((_) {
      pending ??= Timer(const Duration(milliseconds: 200), () {
        pending = null;
        state++;
      });
    });
    ref.onDispose(() {
      pending?.cancel();
      sub.cancel();
    });
    return 0;
  }
}

/// One parameter's current value, rebuilt only when that parameter changes.
final paramValueProvider = Provider.family<({double value, bool isInteger})?, String>((ref, name) {
  final svc = ref.watch(paramServiceProvider);
  if (svc == null) return null;
  final sub = svc.changes.where((p) => p.name == name).listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  final p = svc[name];
  return p == null ? null : (value: p.value, isInteger: p.isInteger);
});
