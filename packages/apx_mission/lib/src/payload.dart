// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
enum PayloadKind {
  /// APX's built‑in sprayer: DO_SPRAYER, pump rate follows ground speed.
  sprayer,

  /// Granular spreader / seeder on the sprayer's spinner output.
  spreader,

  /// A servo or relay on an aux output (drop, release, light…): on/off PWM.
  servo,

  /// A servo‑driven gimbal tilt: angle mapped to PWM.
  gimbal,
}

/// A device on the vehicle, configured in Vehicle → Payloads and used by
/// every plan. Plans carry a copy so they stay self‑contained.
final class Payload {
  const Payload({
    required this.id,
    required this.name,
    required this.kind,
    this.channel = 9,
    this.onPwm = 1900,
    this.offPwm = 1100,
    this.pwmAtLevel = 1500,
    this.pwmAtDown = 1100,
  });

  final String id, name;
  final PayloadKind kind;

  /// Aux output 9–16 (sprayer: ignored, APX uses SPRAY_PUMP_CH; spreader:
  /// the spinner output).
  final int channel;

  /// Servo / spreader on and off PWM.
  final int onPwm, offPwm;

  /// Gimbal: PWM at 0° (level) and at −90° (straight down).
  final int pwmAtLevel, pwmAtDown;

  bool get isSwitch => kind != PayloadKind.gimbal;

  /// Gimbal tilt (−90..0 °) → PWM, linear between the two calibration points.
  int gimbalPwm(double tiltDeg) {
    final t = (tiltDeg.clamp(-90.0, 0.0)) / -90.0;
    return (pwmAtLevel + (pwmAtDown - pwmAtLevel) * t).round().clamp(800, 2200);
  }

  Payload copyWith({
    String? name,
    PayloadKind? kind,
    int? channel,
    int? onPwm,
    int? offPwm,
    int? pwmAtLevel,
    int? pwmAtDown,
  }) => Payload(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    channel: channel ?? this.channel,
    onPwm: onPwm ?? this.onPwm,
    offPwm: offPwm ?? this.offPwm,
    pwmAtLevel: pwmAtLevel ?? this.pwmAtLevel,
    pwmAtDown: pwmAtDown ?? this.pwmAtDown,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'channel': channel,
    'onPwm': onPwm,
    'offPwm': offPwm,
    'pwmAtLevel': pwmAtLevel,
    'pwmAtDown': pwmAtDown,
  };

  factory Payload.fromJson(Map<String, Object?> j) => Payload(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: PayloadKind.values.byName(j['kind'] as String),
    channel: (j['channel'] as num?)?.toInt() ?? 9,
    onPwm: (j['onPwm'] as num?)?.toInt() ?? 1900,
    offPwm: (j['offPwm'] as num?)?.toInt() ?? 1100,
    pwmAtLevel: (j['pwmAtLevel'] as num?)?.toInt() ?? 1500,
    pwmAtDown: (j['pwmAtDown'] as num?)?.toInt() ?? 1100,
  );

  /// The sprayer every APX vehicle has (SPRAY_* parameters).
  static const defaultSprayer = Payload(id: 'sprayer', name: 'Sprayer', kind: PayloadKind.sprayer);
}

/// Sets one payload's state at a point in the mission.
final class PayloadAction {
  const PayloadAction(this.payloadId, {this.on = true, this.tiltDeg});

  final String payloadId;

  /// Switch payloads: on or off.
  final bool on;

  /// Gimbal: tilt angle, −90 (down) .. 0 (level).
  final double? tiltDeg;

  Map<String, Object?> toJson() => {'payload': payloadId, 'on': on, if (tiltDeg != null) 'tilt': tiltDeg};

  factory PayloadAction.fromJson(Map<String, Object?> j) =>
      PayloadAction(j['payload'] as String, on: j['on'] != false, tiltDeg: (j['tilt'] as num?)?.toDouble());
}

/// How a pattern (survey, corridor, orbit) uses a payload.
final class PatternPayload {
  const PatternPayload({this.payloadId, this.onlyOnLines = true, this.gimbalTiltDeg = -90});

  /// Null = no payload.
  final String? payloadId;

  /// Survey/corridor: on along each pass, off in turns. False = on for the
  /// whole pattern.
  final bool onlyOnLines;

  /// For a gimbal payload: tilt during the pattern.
  final double gimbalTiltDeg;

  bool get active => payloadId != null;

  PatternPayload copyWith({String? payloadId, bool clear = false, bool? onlyOnLines, double? gimbalTiltDeg}) =>
      PatternPayload(
        payloadId: clear ? null : (payloadId ?? this.payloadId),
        onlyOnLines: onlyOnLines ?? this.onlyOnLines,
        gimbalTiltDeg: gimbalTiltDeg ?? this.gimbalTiltDeg,
      );

  Map<String, Object?> toJson() => {'payload': payloadId, 'onlyOnLines': onlyOnLines, 'tilt': gimbalTiltDeg};

  factory PatternPayload.fromJson(Map<String, Object?>? j) => j == null
      ? const PatternPayload()
      : PatternPayload(
          payloadId: j['payload'] as String?,
          onlyOnLines: j['onlyOnLines'] != false,
          gimbalTiltDeg: (j['tilt'] as num?)?.toDouble() ?? -90,
        );
}
