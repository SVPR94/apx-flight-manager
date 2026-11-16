// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mission/apx_mission.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage.dart';

/// Payloads fitted to the vehicle (Vehicle → Payloads). Every plan uses this
/// list; saved plans keep their own copy so they stay self‑contained.
final class PayloadsController extends Notifier<List<Payload>> {
  @override
  List<Payload> build() {
    final saved = ref.read(settingsStoreProvider).get<List>('payloads');
    if (saved == null) return const [Payload.defaultSprayer];
    return [for (final p in saved) Payload.fromJson((p as Map).cast())];
  }

  void _save(List<Payload> list) {
    state = list;
    ref.read(settingsStoreProvider).set('payloads', [for (final p in list) p.toJson()]);
  }

  void put(Payload p) {
    final i = state.indexWhere((x) => x.id == p.id);
    _save(i < 0 ? [...state, p] : ([...state]..[i] = p));
  }

  void remove(String id) => _save(state.where((p) => p.id != id).toList());

  String newId() => 'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}

final payloadsProvider = NotifierProvider<PayloadsController, List<Payload>>(PayloadsController.new);
