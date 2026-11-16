// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'param_meta.g.dart';

/// What the firmware declares about one parameter (generated from APX's
/// `modules/params/param_manager.cpp` by `tool/param_meta_gen`).
final class ParamMeta {
  const ParamMeta(this.name, this.isInteger, this.defaultValue, this.min, this.max, this.description);

  final String name;
  final bool isInteger;
  final double defaultValue, min, max;
  final String description;

  /// The value the firmware would store for [v] (it clamps silently).
  double clamp(double v) => v.clamp(min, max).toDouble();

  bool inRange(double v) => v >= min && v <= max;

  static ParamMeta? of(String name) => apxParamMeta[name];

  /// Every parameter APX declares.
  static Map<String, ParamMeta> get all => apxParamMeta;
}
