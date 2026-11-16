// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';
import 'dart:math' as math;

import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../state/view_items.dart';

/// Attitude sphere ringed by a heading card, with a wind arrow on the ring.
class AttitudeIndicator extends StatelessWidget {
  const AttitudeIndicator({
    super.key,
    required this.rollRad,
    required this.pitchRad,
    required this.headingDeg,
    this.windFromDeg,
    this.size = 196,
  });

  final double rollRad, pitchRad, headingDeg;
  final double? windFromDeg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final rollDeg = rollRad * 180 / math.pi, pitchDeg = pitchRad * 180 / math.pi;
    return Semantics(
      label:
          'Attitude: roll ${rollDeg.round()} degrees, pitch ${pitchDeg.round()} degrees, '
          'heading ${headingDeg.round()} degrees',
      child: CustomPaint(size: Size.square(size), painter: _AdiPainter(rollRad, pitchDeg, headingDeg, windFromDeg, p)),
    );
  }
}

class _AdiPainter extends CustomPainter {
  _AdiPainter(this.roll, this.pitchDeg, this.heading, this.windFrom, this.p);

  final double roll, pitchDeg, heading;
  final double? windFrom;
  final AlloyPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, 96 * s, Paint()..color = p.inset);

    // Heading card: rotate so the current heading sits under the top index.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-heading * math.pi / 180);
    final tick = Paint()
      ..color = p.ink2
      ..strokeCap = StrokeCap.round;
    for (var d = 0; d < 360; d += 10) {
      final major = d % 30 == 0;
      final a = d * math.pi / 180;
      final dir = Offset(math.sin(a), -math.cos(a));
      tick.strokeWidth = (major ? 2.0 : 1.2) * s;
      canvas.drawLine(dir * (major ? 82 : 85) * s, dir * 91 * s, tick);
    }
    for (final (label, deg) in [('N', 0), ('E', 90), ('S', 180), ('W', 270)]) {
      final a = deg * math.pi / 180;
      _text(canvas, label, Offset(math.sin(a), -math.cos(a)) * 73 * s, 11 * s, deg == 0 ? p.ink : p.ink2, rotate: a);
    }
    if (windFrom != null && !windFrom!.isNaN) {
      final a = windFrom! * math.pi / 180;
      final dir = Offset(math.sin(a), -math.cos(a));
      final arrow = Paint()
        ..color = AlloyPalette.accent
        ..strokeWidth = 2.5 * s
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final tip = dir * 77 * s, tail = dir * 97 * s;
      canvas.drawLine(tail, tip, arrow);
      final side = Offset(-dir.dy, dir.dx) * 5 * s;
      canvas.drawPath(
        Path()
          ..moveTo((tip + dir * 7 * s + side).dx, (tip + dir * 7 * s + side).dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo((tip + dir * 7 * s - side).dx, (tip + dir * 7 * s - side).dy),
        arrow,
      );
    }
    canvas.restore();

    // Fixed heading index.
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - 99 * s)
        ..lineTo(c.dx + 6 * s, c.dy - 89 * s)
        ..lineTo(c.dx - 6 * s, c.dy - 89 * s)
        ..close(),
      Paint()..color = AlloyPalette.accent,
    );

    // Sphere.
    final r = 66 * s;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-roll);
    final pxPerDeg = 2.2 * s;
    canvas.translate(0, pitchDeg * pxPerDeg);
    const big = 400.0;
    canvas.drawRect(
      Rect.fromLTRB(-big, -big, big, 0),
      Paint()
        ..shader = LinearGradient(
          colors: p.sky,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTRB(-r, -r * 2, r, 0)),
    );
    canvas.drawRect(
      Rect.fromLTRB(-big, 0, big, big),
      Paint()
        ..shader = LinearGradient(
          colors: p.ground,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTRB(-r, 0, r, r * 2)),
    );
    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5 * s;
    canvas.drawLine(const Offset(-big, 0), const Offset(big, 0), white);
    white.strokeWidth = 1.2 * s;
    for (final deg in [-20, -10, 10, 20]) {
      final y = -deg * pxPerDeg;
      final half = (deg.abs() == 10 ? 10 : 16) * s;
      canvas.drawLine(Offset(-half, y), Offset(half, y), white);
    }
    canvas.restore();
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..color = p.glassEdge,
    );

    // Aircraft symbol.
    final wing = Path()
      ..moveTo(c.dx - 44 * s, c.dy)
      ..lineTo(c.dx - 16 * s, c.dy)
      ..lineTo(c.dx - 8 * s, c.dy + 8 * s)
      ..moveTo(c.dx + 44 * s, c.dy)
      ..lineTo(c.dx + 16 * s, c.dy)
      ..lineTo(c.dx + 8 * s, c.dy + 8 * s);
    canvas.drawPath(
      wing,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF1D1F23),
    );
    canvas.drawPath(
      wing,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AlloyPalette.instrumentYellow,
    );
    canvas.drawCircle(c, 3.5 * s, Paint()..color = AlloyPalette.instrumentYellow);
  }

  void _text(Canvas canvas, String t, Offset at, double size, Color color, {double rotate = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontFamily: AlloyText.family, fontSize: size, fontWeight: FontWeight.w700, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rotate);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AdiPainter o) =>
      o.roll != roll || o.pitchDeg != pitchDeg || o.heading != heading || o.windFrom != windFrom || o.p != p;
}

/// Vertical moving tape (speed or altitude) with a centred readout.
class Tape extends StatelessWidget {
  const Tape({
    super.key,
    required this.title,
    required this.value,
    required this.step,
    this.decimals = 1,
    this.width = 70,
    this.height = 196,
    this.trend,
    this.minValue,
  });

  /// Lowest value worth a tick (0 for ground speed).
  final double? minValue;

  final String title;
  final double value;

  /// Units between labelled ticks.
  final double step;
  final int decimals;
  final double width, height;

  /// Optional rate (e.g. climb m/s) shown as a marker on the right edge.
  final double? trend;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final v = value.isNaN ? 0.0 : value;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: p.inset, borderRadius: BorderRadius.circular(14)),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TapePainter(v, step, p, trend, minValue))),
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Text(title, textAlign: TextAlign.center, style: AlloyText.label(p.ink2).copyWith(fontSize: 10)),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              margin: EdgeInsets.only(left: 4, right: trend == null ? 4 : 14),
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(9)),
              child: Text(value.isNaN ? '—' : v.toStringAsFixed(decimals), style: AlloyText.mono(17, color: p.onInk)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter(this.value, this.step, this.p, this.trend, this.minValue);
  final double value, step;
  final AlloyPalette p;
  final double? trend, minValue;

  @override
  void paint(Canvas canvas, Size size) {
    final pxPerUnit = 30 / step; // 30 px between labelled ticks
    final mid = size.height / 2;
    final paint = Paint()
      ..color = p.ink2
      ..strokeWidth = 1;
    final first = ((value - mid / pxPerUnit) / step).floor() - 1;
    final last = ((value + mid / pxPerUnit) / step).ceil() + 1;
    for (var i = first; i <= last; i++) {
      final u = i * step;
      if (minValue != null && u < minValue!) continue;
      final y = mid - (u - value) * pxPerUnit;
      if (y < 22 || y > size.height - 6) continue;
      canvas.drawLine(Offset(0, y), Offset(6, y), paint);
      final tp = TextPainter(
        text: TextSpan(
          text: _fmt(u),
          style: AlloyText.mono(11, weight: FontWeight.w500, color: p.ink2),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(10, y - tp.height / 2));
    }
    final t = trend;
    if (t != null && !t.isNaN) {
      final x = size.width - 7;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(x - 2.5, 26, x + 2.5, size.height - 10), const Radius.circular(3)),
        Paint()..color = p.hairline,
      );
      // ±5 m/s spans the bar.
      final y = (mid - t.clamp(-5.0, 5.0) / 5 * (mid - 30)).toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: 9, height: 4), const Radius.circular(2)),
        Paint()..color = AlloyPalette.accent,
      );
    }
  }

  static String _fmt(double u) => u == u.roundToDouble() ? u.toStringAsFixed(0) : u.toStringAsFixed(1);

  @override
  bool shouldRepaint(_TapePainter o) => o.value != value || o.p != p || o.trend != trend || o.minValue != minValue;
}

/// Top‑down vehicle glyph matching the frame or custom transparent PNG graphic.
class VehicleGlyph extends ConsumerWidget {
  const VehicleGlyph({
    super.key,
    this.arms,
    required this.headingDeg,
    this.size = 56,
    this.vehicleType,
    this.customIconPath,
  });

  final int? arms;
  final double headingDeg;
  final double size;
  final int? vehicleType;
  final String? customIconPath;

  /// Arm count for a MAVLink vehicle type.
  static int armsOf(int? vehicleType) => switch (vehicleType) {
    MavType.hexarotor => 6,
    MavType.octorotor => 8,
    _ => 4,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveArms = arms ?? armsOf(vehicleType);
    String? resolvedPath = customIconPath;
    if (resolvedPath == null && vehicleType != null) {
      try {
        final settings = ref.watch(viewItemSettingsProvider);
        resolvedPath = settings.customVehicleIcons[vehicleType];
      } catch (_) {
        // Fallback gracefully if used outside a ProviderScope
      }
    }

    final palette = Theme.of(context).extension<AlloyPalette>() ?? AlloyPalette.silver;
    Widget fallback(BuildContext context) => CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(effectiveArms, palette),
    );

    Widget glyph;
    final file = (resolvedPath != null && resolvedPath.isNotEmpty) ? File(resolvedPath) : null;
    if (file != null && file.existsSync()) {
      glyph = Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback(context),
      );
    } else {
      glyph = fallback(context);
    }

    return Transform.rotate(
      angle: headingDeg * math.pi / 180,
      child: SizedBox(
        width: size,
        height: size,
        child: glyph,
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.arms, this.p);
  final int arms;
  final AlloyPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final s = size.width / 56;
    canvas.drawCircle(c, 26 * s, Paint()..color = AlloyPalette.accent.withValues(alpha: 0.16));
    final body = p.brightness == Brightness.light ? const Color(0xFF1D1F23) : const Color(0xFFECEEF1);
    final armPaint = Paint()
      ..color = body
      ..strokeWidth = 3.5 * s
      ..strokeCap = StrokeCap.round;
    final rotor = Paint()..color = Colors.white;
    final rotorEdge = Paint()
      ..color = body
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s;
    final offset = arms == 4 ? math.pi / 4 : 0.0; // X frames
    final reach = 15 * s, rr = (arms == 8 ? 4.0 : 5.5) * s;
    for (var i = 0; i < arms; i++) {
      final a = offset + i * 2 * math.pi / arms;
      final end = c + Offset(math.sin(a), -math.cos(a)) * reach;
      canvas.drawLine(c, end, armPaint);
      canvas.drawCircle(end, rr, rotor);
      canvas.drawCircle(end, rr, rotorEdge);
    }
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - 25 * s)
        ..lineTo(c.dx + 6 * s, c.dy - 16 * s)
        ..lineTo(c.dx - 6 * s, c.dy - 16 * s)
        ..close(),
      Paint()..color = AlloyPalette.accent,
    );
    canvas.drawCircle(c, 4.5 * s, Paint()..color = AlloyPalette.accent);
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.arms != arms || o.p != p;
}
