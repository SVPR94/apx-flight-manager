// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection.dart';

/// Rolling statistics and latest decoded fields for one MAVLink message ID.
final class MessageInspectorEntry {
  MessageInspectorEntry({required this.id, required this.name});

  final int id;
  final String name;

  int count = 0;
  int _lastCount = 0;
  double rateHz = 0.0;
  DateTime? lastSeen;
  Map<String, Object> latestFields = {};

  void record(MavlinkFrame frame) {
    count++;
    lastSeen = DateTime.now();
    final msg = frame.message;
    if (msg != null) {
      latestFields = msg.toMap();
    }
  }

  void sampleRate(double dtSeconds) {
    if (dtSeconds <= 0) return;
    rateHz = (count - _lastCount) / dtSeconds;
    _lastCount = count;
  }
}

/// A point in time for a plotted channel.
final class TimeSeriesPoint {
  const TimeSeriesPoint(this.time, this.value);
  final DateTime time;
  final double value;
}

/// Available live graph channels in Developer Diagnostics.
enum DiagnosticChannel {
  accelZSpread('IMU Accel Z Spread', 'm/s²', 0, 3.0),
  laneAccZ('All Lanes Accel Z', 'm/s²', -15, 0),
  attitude('Roll & Pitch', '°', -45, 45),
  altitude('Relative Altitude', 'm', 0, 50),
  climbRate('Climb Rate', 'm/s', -5, 5),
  batteryVolt('Battery Voltage', 'V', 10, 26),
  groundSpeed('Ground Speed', 'm/s', 0, 20);

  const DiagnosticChannel(this.label, this.unit, this.defaultMin, this.defaultMax);
  final String label;
  final String unit;
  final double defaultMin;
  final double defaultMax;
}

/// Live inspector state containing per-message statistics, overall link counters,
/// and live rolling graph series.
final class InspectorState {
  InspectorState({
    required this.messages,
    required this.selectedMessageId,
    required this.totalFrames,
    required this.frameRateHz,
    required this.byteRateKBs,
    required this.crcErrors,
    required this.lostFrames,
    required this.dropRatio,
    required this.selectedChannel,
    required this.isGraphPaused,
    this.autoScale = true,
    required this.series,
  });

  final Map<int, MessageInspectorEntry> messages;
  final int? selectedMessageId;
  final int totalFrames;
  final double frameRateHz;
  final double byteRateKBs;
  final int crcErrors;
  final int lostFrames;
  final double dropRatio;
  final DiagnosticChannel selectedChannel;
  final bool isGraphPaused;
  final bool autoScale;
  final Map<String, List<TimeSeriesPoint>> series;

  MessageInspectorEntry? get selectedMessage => selectedMessageId == null ? null : messages[selectedMessageId];

  InspectorState copyWith({
    Map<int, MessageInspectorEntry>? messages,
    int? selectedMessageId,
    bool clearSelected = false,
    int? totalFrames,
    double? frameRateHz,
    double? byteRateKBs,
    int? crcErrors,
    int? lostFrames,
    double? dropRatio,
    DiagnosticChannel? selectedChannel,
    bool? isGraphPaused,
    bool? autoScale,
    Map<String, List<TimeSeriesPoint>>? series,
  }) => InspectorState(
    messages: messages ?? this.messages,
    selectedMessageId: clearSelected ? null : (selectedMessageId ?? this.selectedMessageId),
    totalFrames: totalFrames ?? this.totalFrames,
    frameRateHz: frameRateHz ?? this.frameRateHz,
    byteRateKBs: byteRateKBs ?? this.byteRateKBs,
    crcErrors: crcErrors ?? this.crcErrors,
    lostFrames: lostFrames ?? this.lostFrames,
    dropRatio: dropRatio ?? this.dropRatio,
    selectedChannel: selectedChannel ?? this.selectedChannel,
    isGraphPaused: isGraphPaused ?? this.isGraphPaused,
    autoScale: autoScale ?? this.autoScale,
    series: series ?? this.series,
  );
}

/// Controller feeding real-time MAVLink packet inspection & telemetry channels.
final class InspectorController extends Notifier<InspectorState> {
  StreamSubscription<MavlinkFrame>? _frameSub;
  Timer? _rateTimer;
  Timer? _seriesTimer;
  DateTime _lastRateSample = DateTime.now();

  static const int _maxSeriesPoints = 300; // ~30 seconds @ 10 Hz

  @override
  InspectorState build() {
    final s = InspectorState(
      messages: SplayTreeMap<int, MessageInspectorEntry>(),
      selectedMessageId: null,
      totalFrames: 0,
      frameRateHz: 0,
      byteRateKBs: 0,
      crcErrors: 0,
      lostFrames: 0,
      dropRatio: 0,
      selectedChannel: DiagnosticChannel.accelZSpread,
      isGraphPaused: false,
      autoScale: true,
      series: {},
    );

    ref.listen<Connection?>(connectionProvider, (prev, next) {
      _bindConnection(next);
    });

    _bindConnection(ref.read(connectionProvider));

    _rateTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) => _onRateTick());
    _seriesTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _onSeriesTick());

    ref.onDispose(() {
      _frameSub?.cancel();
      _rateTimer?.cancel();
      _seriesTimer?.cancel();
    });

    return s;
  }

  void _bindConnection(Connection? c) {
    _frameSub?.cancel();
    _frameSub = null;
    if (c != null) {
      _frameSub = c.session.link.frames.listen(_onFrame);
    }
  }

  void _onFrame(MavlinkFrame frame) {
    final msgs = state.messages;
    var entry = msgs[frame.messageId];
    if (entry == null) {
      entry = MessageInspectorEntry(id: frame.messageId, name: frame.messageName);
      msgs[frame.messageId] = entry;
    }
    entry.record(frame);
  }

  void _onRateTick() {
    final now = DateTime.now();
    final dt = now.difference(_lastRateSample).inMicroseconds / 1e6;
    _lastRateSample = now;
    if (dt <= 0) return;

    for (final entry in state.messages.values) {
      entry.sampleRate(dt);
    }

    final conn = ref.read(connectionProvider);
    if (conn == null) {
      state = state.copyWith(frameRateHz: 0, byteRateKBs: 0);
      return;
    }

    final stats = conn.session.link.stats;
    final parser = conn.session.link.parser.stats;

    state = state.copyWith(
      totalFrames: stats.framesIn,
      frameRateHz: stats.framesInPerSecond,
      byteRateKBs: stats.bytesInPerSecond / 1024.0,
      crcErrors: parser.crcErrors,
      lostFrames: parser.sequenceLost,
      dropRatio: parser.lossRatio,
    );
  }

  void _onSeriesTick() {
    if (state.isGraphPaused) return;

    final conn = ref.read(connectionProvider);
    if (conn == null) return;

    final snap = conn.session.telemetry.snapshot;
    final now = DateTime.now();
    final currentSeries = Map<String, List<TimeSeriesPoint>>.from(state.series);

    void addPoint(String key, double value) {
      final list = currentSeries.putIfAbsent(key, () => <TimeSeriesPoint>[]);
      list.add(TimeSeriesPoint(now, value));
      if (list.length > _maxSeriesPoints) {
        list.removeRange(0, list.length - _maxSeriesPoints);
      }
    }

    switch (state.selectedChannel) {
      case DiagnosticChannel.accelZSpread:
        final lanes = snap.imu.where((l) => l.updated != null).toList();
        if (lanes.length >= 2) {
          final z = lanes.map((l) => l.accZ);
          final spread = z.reduce(math.max) - z.reduce(math.min);
          addPoint('Spread', spread);
        } else {
          addPoint('Spread', 0.0);
        }
      case DiagnosticChannel.laneAccZ:
        for (var i = 0; i < snap.imu.length; i++) {
          addPoint('Lane $i', snap.imu[i].accZ);
        }
      case DiagnosticChannel.attitude:
        addPoint('Roll', snap.roll * 180 / math.pi);
        addPoint('Pitch', snap.pitch * 180 / math.pi);
      case DiagnosticChannel.altitude:
        addPoint('Alt Rel', snap.altRel.isNaN ? 0.0 : snap.altRel);
        addPoint('Alt MSL', snap.altMsl.isNaN ? 0.0 : snap.altMsl);
      case DiagnosticChannel.climbRate:
        addPoint('Climb', snap.climbRate);
      case DiagnosticChannel.batteryVolt:
        addPoint('Voltage', snap.batteryVoltage.isNaN ? 0.0 : snap.batteryVoltage);
      case DiagnosticChannel.groundSpeed:
        addPoint('Speed', snap.groundSpeed);
    }

    state = state.copyWith(series: currentSeries);
  }

  void selectMessage(int? messageId) {
    if (state.selectedMessageId == messageId) {
      state = state.copyWith(clearSelected: true);
    } else {
      state = state.copyWith(selectedMessageId: messageId);
    }
  }

  void selectChannel(DiagnosticChannel channel) {
    state = state.copyWith(selectedChannel: channel, series: {});
  }

  void togglePause() {
    state = state.copyWith(isGraphPaused: !state.isGraphPaused);
  }

  void toggleAutoScale() {
    state = state.copyWith(autoScale: !state.autoScale);
  }

  void clearGraph() {
    state = state.copyWith(series: {});
  }
}

final inspectorProvider = NotifierProvider<InspectorController, InspectorState>(InspectorController.new);
