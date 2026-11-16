// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import 'storage.dart';

/// Silver (daylight) or Graphite (night), remembered between runs.
final class AppearanceController extends Notifier<AlloyPalette> {
  @override
  AlloyPalette build() => ref.read(settingsStoreProvider).get<String>('appearance') == 'graphite'
      ? AlloyPalette.graphite
      : AlloyPalette.silver;

  void set(AlloyPalette p) {
    state = p;
    ref.read(settingsStoreProvider).set('appearance', p == AlloyPalette.graphite ? 'graphite' : 'silver');
  }
}

final appearanceProvider = NotifierProvider<AppearanceController, AlloyPalette>(AppearanceController.new);
