// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/storage.dart';

/// What fills the Fly view; the other one can float in a picture‑in‑picture
/// window (map/video swap).
enum FlyPrimary { map, video }

enum PipCorner { topLeft, topRight, bottomLeft, bottomRight }

/// The four arrangements offered in the Fly view.
enum FlyLayoutMode {
  mapOnly('Map only'),
  mapWithVideo('Map + video window'),
  videoWithMap('Video + map window'),
  videoOnly('Video only');

  const FlyLayoutMode(this.label);
  final String label;
}

final class VideoLayout {
  const VideoLayout({
    this.primary = FlyPrimary.map,
    this.pipVisible = true,
    this.corner = PipCorner.topLeft,
    this.pipWidth = 340,
  });

  final FlyPrimary primary;

  /// Whether the secondary surface floats in the window (else it is hidden).
  final bool pipVisible;
  final PipCorner corner;

  /// Window width in logical pixels; the height follows the aspect.
  final double pipWidth;

  static const minWidth = 200.0, maxWidth = 900.0;

  FlyLayoutMode get mode => switch ((primary, pipVisible)) {
    (FlyPrimary.map, false) => FlyLayoutMode.mapOnly,
    (FlyPrimary.map, true) => FlyLayoutMode.mapWithVideo,
    (FlyPrimary.video, true) => FlyLayoutMode.videoWithMap,
    (FlyPrimary.video, false) => FlyLayoutMode.videoOnly,
  };

  VideoLayout copyWith({FlyPrimary? primary, bool? pipVisible, PipCorner? corner, double? pipWidth}) => VideoLayout(
    primary: primary ?? this.primary,
    pipVisible: pipVisible ?? this.pipVisible,
    corner: corner ?? this.corner,
    pipWidth: (pipWidth ?? this.pipWidth).clamp(minWidth, maxWidth),
  );

  Map<String, Object?> toJson() => {
    'primary': primary.name,
    'pipVisible': pipVisible,
    'corner': corner.name,
    'pipWidth': pipWidth,
  };

  factory VideoLayout.fromJson(Map<String, Object?> j) => VideoLayout(
    primary: FlyPrimary.values.firstWhere((e) => e.name == j['primary'], orElse: () => FlyPrimary.map),
    pipVisible: j['pipVisible'] as bool? ?? true,
    corner: PipCorner.values.firstWhere((e) => e.name == j['corner'], orElse: () => PipCorner.topLeft),
    pipWidth: ((j['pipWidth'] as num?)?.toDouble() ?? 340).clamp(minWidth, maxWidth),
  );
}

final class VideoLayoutController extends Notifier<VideoLayout> {
  static const _key = 'videoLayout';

  @override
  VideoLayout build() {
    final raw = ref.read(settingsStoreProvider).get<Map<String, Object?>>(_key);
    try {
      return raw == null ? const VideoLayout() : VideoLayout.fromJson(raw);
    } catch (_) {
      return const VideoLayout();
    }
  }

  void _set(VideoLayout l) {
    state = l;
    ref.read(settingsStoreProvider).set(_key, l.toJson());
  }

  void setMode(FlyLayoutMode m) => _set(
    state.copyWith(
      primary: m == FlyLayoutMode.videoOnly || m == FlyLayoutMode.videoWithMap ? FlyPrimary.video : FlyPrimary.map,
      pipVisible: m == FlyLayoutMode.mapWithVideo || m == FlyLayoutMode.videoWithMap,
    ),
  );

  /// Map ↔ video, keeping the window.
  void swap() => _set(
    state.copyWith(primary: state.primary == FlyPrimary.map ? FlyPrimary.video : FlyPrimary.map, pipVisible: true),
  );

  void setPipVisible(bool v) => _set(state.copyWith(pipVisible: v));
  void setCorner(PipCorner c) => _set(state.copyWith(corner: c));
  void setWidth(double w) => _set(state.copyWith(pipWidth: w));
}

final videoLayoutProvider = NotifierProvider<VideoLayoutController, VideoLayout>(VideoLayoutController.new);
