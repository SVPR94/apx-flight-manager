// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';

/// A current value plus a broadcast stream of changes.
///
/// Small on purpose: the protocol packages stay free of Flutter and
/// third‑party reactive libraries.
final class Signal<T> {
  Signal(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast(sync: true);

  T get value => _value;

  set value(T next) {
    if (next == _value) return;
    _value = next;
    _controller.add(next);
  }

  Stream<T> get changes => _controller.stream;

  Future<void> dispose() => _controller.close();
}
