// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
final class MessageMeta {
  const MessageMeta(this.id, this.name, this.crcExtra, this.minLength, this.maxLength);

  final int id;
  final String name;
  final int crcExtra;

  /// Payload length of the base (non‑extension) fields.
  final int minLength;

  /// Payload length including every extension field.
  final int maxLength;
}
