// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

enum FrameClass {
  quad(1, 'Quadrotor (4 motors)', 4),
  hexa(2, 'Hexarotor (6 motors)', 6),
  octa(3, 'Octorotor (8 motors)', 8);

  const FrameClass(this.paramValue, this.label, this.motorCount);
  final int paramValue;
  final String label;
  final int motorCount;
}

enum FrameType {
  plus(0, '+ (Plus) Configuration'),
  x(1, 'X Configuration');

  const FrameType(this.paramValue, this.label);
  final int paramValue;
  final String label;
}

class MotorInfo {
  const MotorInfo({
    required this.number,
    required this.channel,
    required this.angleDeg,
    required this.isCw,
    required this.label,
  });

  final int number;
  final int channel; // PWM servo output channel (usually 1..8)
  final double angleDeg; // 0 = 12 o'clock (front), clockwise
  final bool isCw; // true = clockwise, false = counter-clockwise
  final String label;
}

/// Computes motor positions and rotation directions for APX standard multirotor frames.
List<MotorInfo> getMotorLayout(FrameClass frameClass, FrameType frameType) {
  switch (frameClass) {
    case FrameClass.quad:
      if (frameType == FrameType.x) {
        // Quad X: 1: Front-Right (CCW), 2: Rear-Left (CCW), 3: Front-Left (CW), 4: Rear-Right (CW)
        return const [
          MotorInfo(number: 1, channel: 1, angleDeg: 45, isCw: false, label: 'Front-Right · CCW'),
          MotorInfo(number: 2, channel: 2, angleDeg: 225, isCw: false, label: 'Rear-Left · CCW'),
          MotorInfo(number: 3, channel: 3, angleDeg: 315, isCw: true, label: 'Front-Left · CW'),
          MotorInfo(number: 4, channel: 4, angleDeg: 135, isCw: true, label: 'Rear-Right · CW'),
        ];
      } else {
        // Quad +: 1: Front (CCW), 2: Rear (CCW), 3: Left (CW), 4: Right (CW)
        return const [
          MotorInfo(number: 1, channel: 1, angleDeg: 0, isCw: false, label: 'Front · CCW'),
          MotorInfo(number: 2, channel: 2, angleDeg: 180, isCw: false, label: 'Rear · CCW'),
          MotorInfo(number: 3, channel: 3, angleDeg: 270, isCw: true, label: 'Left · CW'),
          MotorInfo(number: 4, channel: 4, angleDeg: 90, isCw: true, label: 'Right · CW'),
        ];
      }

    case FrameClass.hexa:
      if (frameType == FrameType.x) {
        // Hexa X: 6 motors radially at 30, 90, 150, 210, 270, 330 deg
        return const [
          MotorInfo(number: 1, channel: 1, angleDeg: 30, isCw: false, label: 'Front-Right · CCW'),
          MotorInfo(number: 2, channel: 2, angleDeg: 210, isCw: true, label: 'Rear-Left · CW'),
          MotorInfo(number: 3, channel: 3, angleDeg: 90, isCw: true, label: 'Right · CW'),
          MotorInfo(number: 4, channel: 4, angleDeg: 270, isCw: false, label: 'Left · CCW'),
          MotorInfo(number: 5, channel: 5, angleDeg: 330, isCw: true, label: 'Front-Left · CW'),
          MotorInfo(number: 6, channel: 6, angleDeg: 150, isCw: false, label: 'Rear-Right · CCW'),
        ];
      } else {
        // Hexa +: motors at 0, 60, 120, 180, 240, 300 deg
        return const [
          MotorInfo(number: 1, channel: 1, angleDeg: 0, isCw: false, label: 'Front · CCW'),
          MotorInfo(number: 2, channel: 2, angleDeg: 180, isCw: true, label: 'Rear · CW'),
          MotorInfo(number: 3, channel: 3, angleDeg: 60, isCw: true, label: 'Right-Front · CW'),
          MotorInfo(number: 4, channel: 4, angleDeg: 240, isCw: false, label: 'Left-Rear · CCW'),
          MotorInfo(number: 5, channel: 5, angleDeg: 300, isCw: true, label: 'Left-Front · CW'),
          MotorInfo(number: 6, channel: 6, angleDeg: 120, isCw: false, label: 'Right-Rear · CCW'),
        ];
      }

    case FrameClass.octa:
      // Octa X: 8 motors radially every 45 deg
      final isX = frameType == FrameType.x;
      final offset = isX ? 22.5 : 0.0;
      return List.generate(8, (i) {
        final angle = (offset + i * 45.0) % 360.0;
        final isCw = i.isOdd;
        return MotorInfo(
          number: i + 1,
          channel: i + 1,
          angleDeg: angle,
          isCw: isCw,
          label: 'Motor ${i + 1} · ${isCw ? "CW" : "CCW"}',
        );
      });
  }
}

/// Visual interactive diagram rendering drone airframe, motor numbering,
/// rotation arrows (CW/CCW), PWM channel assignments, and animated propellers.
class MotorLayoutDiagram extends StatefulWidget {
  const MotorLayoutDiagram({
    super.key,
    required this.frameClass,
    required this.frameType,
    this.highlightedMotor,
    this.size = 300,
    this.animate = true,
    this.onMotorSelected,
  });

  final FrameClass frameClass;
  final FrameType frameType;
  final int? highlightedMotor;
  final double size;
  final bool animate;
  final ValueChanged<int>? onMotorSelected;

  @override
  State<MotorLayoutDiagram> createState() => _MotorLayoutDiagramState();
}

class _MotorLayoutDiagramState extends State<MotorLayoutDiagram> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MotorLayoutDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details) {
    if (widget.onMotorSelected == null) return;
    final motors = getMotorLayout(widget.frameClass, widget.frameType);
    final center = Offset(widget.size / 2, widget.size / 2 + 10);
    final armRadius = widget.size * 0.33;

    for (final m in motors) {
      final rad = (m.angleDeg - 90) * math.pi / 180.0;
      final motorCenter = Offset(center.dx + armRadius * math.cos(rad), center.dy + armRadius * math.sin(rad));
      final distance = (details.localPosition - motorCenter).distance;
      if (distance <= 26) {
        widget.onMotorSelected!(m.number);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final motors = getMotorLayout(widget.frameClass, widget.frameType);

    return GestureDetector(
      onTapUp: _handleTap,
      child: Container(
        width: widget.size,
        height: widget.size,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.plate,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _MotorDiagramPainter(
              motors: motors,
              palette: p,
              animationValue: _controller.value,
              highlightedMotor: widget.highlightedMotor,
            ),
          ),
        ),
      ),
    );
  }
}

class _MotorDiagramPainter extends CustomPainter {
  _MotorDiagramPainter({
    required this.motors,
    required this.palette,
    required this.animationValue,
    this.highlightedMotor,
  });

  final List<MotorInfo> motors;
  final AlloyPalette palette;
  final double animationValue;
  final int? highlightedMotor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    final armRadius = size.width * 0.33;
    const chassisRadius = 30.0;

    // --- 1. Forward orientation indicator (Nose Arrow & FRONT label) ---
    final arrowTop = Offset(center.dx, center.dy - armRadius - 32);
    final arrowPaint = Paint()
      ..color = palette.accentInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final arrowPath = Path()
      ..moveTo(arrowTop.dx, arrowTop.dy)
      ..lineTo(arrowTop.dx - 7, arrowTop.dy + 10)
      ..moveTo(arrowTop.dx, arrowTop.dy)
      ..lineTo(arrowTop.dx + 7, arrowTop.dy + 10)
      ..moveTo(arrowTop.dx, arrowTop.dy)
      ..lineTo(arrowTop.dx, arrowTop.dy + 18);
    canvas.drawPath(arrowPath, arrowPaint);

    final frontTp = TextPainter(
      text: TextSpan(
        text: '▲ FRONT',
        style: TextStyle(color: palette.accentInk, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    frontTp.paint(canvas, Offset(center.dx - frontTp.width / 2, arrowTop.dy - 14));

    // --- 2. Arms (drawn starting STRICTLY from chassis outer perimeter) ---
    // This completely prevents arms from crossing into the central chassis and APX badge!
    final armPaint = Paint()
      ..color = const Color(0xFF1E232A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round;

    final armSpinePaint = Paint()
      ..color = const Color(0xFF384350)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (final m in motors) {
      final rad = (m.angleDeg - 90) * math.pi / 180.0;
      final armStart = Offset(
        center.dx + (chassisRadius - 2) * math.cos(rad),
        center.dy + (chassisRadius - 2) * math.sin(rad),
      );
      final armEnd = Offset(center.dx + (armRadius - 10) * math.cos(rad), center.dy + (armRadius - 10) * math.sin(rad));

      canvas.drawLine(armStart, armEnd, armPaint);
      canvas.drawLine(armStart, armEnd, armSpinePaint);
    }

    // --- 3. Central Chassis Plate (Layered Octagonal Carbon Fiber Hub) ---
    _drawChassisPlate(canvas, center, chassisRadius);

    // --- 4. Motors, Propellers, Direction Arrows, and Badges ---
    for (final m in motors) {
      final rad = (m.angleDeg - 90) * math.pi / 180.0;
      final motorX = center.dx + armRadius * math.cos(rad);
      final motorY = center.dy + armRadius * math.sin(rad);
      final motorCenter = Offset(motorX, motorY);
      final isHighlighted = highlightedMotor == m.number;

      // Draw Animated Propeller Blades behind the motor hub
      _drawPropeller(
        canvas: canvas,
        motorCenter: motorCenter,
        isCw: m.isCw,
        isHighlighted: isHighlighted,
        propRadius: 32.0,
      );

      // Motor Stator Mount & Base
      const motorR = 17.5;
      final motorBasePaint = Paint()
        ..color = const Color(0xFF14171C)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(motorCenter, motorR + 1.5, motorBasePaint);

      // Highlight Glow if motor is under test
      if (isHighlighted) {
        final pulse = (math.sin(animationValue * 2 * math.pi * 3) + 1) / 2;
        final glowRadius = motorR + 4 + pulse * 6;
        final glowPaint = Paint()
          ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35 + pulse * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(motorCenter, glowRadius, glowPaint);
      }

      // Motor Bell Body
      final cwColor = const Color(0xFFF59E0B); // Amber for CW
      final ccwColor = const Color(0xFF38BDF8); // Sky blue for CCW

      final motorBg = Paint()
        ..color = isHighlighted
            ? const Color(0xFF00E5FF).withValues(alpha: 0.3)
            : (m.isCw ? cwColor.withValues(alpha: 0.18) : ccwColor.withValues(alpha: 0.18))
        ..style = PaintingStyle.fill;

      final motorBorder = Paint()
        ..color = isHighlighted ? const Color(0xFF00E5FF) : (m.isCw ? cwColor : ccwColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHighlighted ? 2.8 : 2.2;

      canvas.drawCircle(motorCenter, motorR, motorBg);
      canvas.drawCircle(motorCenter, motorR, motorBorder);

      // Stator cooling notches (subtle metallic lines)
      final notchPaint = Paint()
        ..color = (m.isCw ? cwColor : ccwColor).withValues(alpha: 0.45)
        ..strokeWidth = 1.0;
      for (int i = 0; i < 6; i++) {
        final a = i * math.pi / 3;
        canvas.drawLine(
          Offset(motorCenter.dx + (motorR - 5) * math.cos(a), motorCenter.dy + (motorR - 5) * math.sin(a)),
          Offset(motorCenter.dx + (motorR - 1) * math.cos(a), motorCenter.dy + (motorR - 1) * math.sin(a)),
          notchPaint,
        );
      }

      // Rotation direction circular arc arrow - bold stroke and generous clearance from circle
      final rotPaint = Paint()
        ..color = isHighlighted ? const Color(0xFF00E5FF) : (m.isCw ? cwColor : ccwColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;

      const arcR = 26.5; // Well-spaced from the 17.5 motor radius
      final startAngle = m.isCw ? -0.8 : 0.8;
      final sweepAngle = m.isCw ? 2.5 : -2.5;
      canvas.drawArc(Rect.fromCircle(center: motorCenter, radius: arcR), startAngle, sweepAngle, false, rotPaint);

      // Bold, filled arrowhead on rotation arc
      final headAngle = startAngle + sweepAngle;
      final headX = motorCenter.dx + arcR * math.cos(headAngle);
      final headY = motorCenter.dy + arcR * math.sin(headAngle);
      final arrowTan = headAngle + (m.isCw ? math.pi / 2 : -math.pi / 2);
      const arrowLen = 7.5;
      final tipP = Offset(headX, headY);
      final wing1 = Offset(headX - arrowLen * math.cos(arrowTan - 0.45), headY - arrowLen * math.sin(arrowTan - 0.45));
      final wing2 = Offset(headX - arrowLen * math.cos(arrowTan + 0.45), headY - arrowLen * math.sin(arrowTan + 0.45));

      final tipPath = Path()
        ..moveTo(tipP.dx, tipP.dy)
        ..lineTo(wing1.dx, wing1.dy)
        ..lineTo(wing2.dx, wing2.dy)
        ..close();

      final tipFill = Paint()
        ..color = isHighlighted ? const Color(0xFF00E5FF) : (m.isCw ? cwColor : ccwColor)
        ..style = PaintingStyle.fill;
      canvas.drawPath(tipPath, tipFill);

      // Center motor shaft / bullet nut badge with distinct background color for CW vs CCW
      final numBgColor = isHighlighted
          ? const Color(0xFF00E5FF)
          : (m.isCw ? const Color(0xFFD97706) : const Color(0xFF0284C7));
      final shaftPaint = Paint()
        ..color = numBgColor
        ..style = PaintingStyle.fill;
      final shaftBorder = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(motorCenter, 9.0, shaftPaint);
      canvas.drawCircle(motorCenter, 9.0, shaftBorder);

      // Motor number text (centered in motor shaft)
      final numTp = TextPainter(
        text: TextSpan(
          text: '${m.number}',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      numTp.paint(canvas, Offset(motorCenter.dx - numTp.width / 2, motorCenter.dy - numTp.height / 2 - 0.5));
    }
  }

  void _drawChassisPlate(Canvas canvas, Offset center, double radius) {
    // Octagonal carbon composite plate path
    final platePath = Path();
    const sides = 8;
    for (int i = 0; i < sides; i++) {
      final a = (i * 2 * math.pi / sides) + (math.pi / 8);
      final pt = Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a));
      if (i == 0) {
        platePath.moveTo(pt.dx, pt.dy);
      } else {
        platePath.lineTo(pt.dx, pt.dy);
      }
    }
    platePath.close();

    // Plate background
    final plateFill = Paint()
      ..color = const Color(0xFF15191F)
      ..style = PaintingStyle.fill;
    canvas.drawPath(platePath, plateFill);

    // Plate bevel border
    final plateBorder = Paint()
      ..color = const Color(0xFF333D4B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(platePath, plateBorder);

    // Standoff screws at corners
    final screwPaint = Paint()
      ..color = const Color(0xFF7A889B)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 4; i++) {
      final a = (i * math.pi / 2) + (math.pi / 4);
      final sPt = Offset(center.dx + (radius - 7.5) * math.cos(a), center.dy + (radius - 7.5) * math.sin(a));
      canvas.drawCircle(sPt, 2.2, screwPaint);
    }

    // Inner FC emblem circle
    final fcCirclePaint = Paint()
      ..color = const Color(0xFF0D1117)
      ..style = PaintingStyle.fill;
    final fcBorderPaint = Paint()
      ..color = palette.accentInk.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(center, radius - 10, fcCirclePaint);
    canvas.drawCircle(center, radius - 10, fcBorderPaint);

    // APX Text Logo
    final apxTp = TextPainter(
      text: TextSpan(
        text: 'APX',
        style: TextStyle(color: palette.accentInk, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.6),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    apxTp.paint(canvas, Offset(center.dx - apxTp.width / 2, center.dy - apxTp.height / 2));
  }

  void _drawPropeller({
    required Canvas canvas,
    required Offset motorCenter,
    required bool isCw,
    required bool isHighlighted,
    required double propRadius,
  }) {
    // Calculate rotation angle based on CW/CCW and animationValue
    final speed = isHighlighted ? 6.0 : 1.5;
    final rotAngle = isCw ? (animationValue * 2 * math.pi * speed) : -(animationValue * 2 * math.pi * speed);

    canvas.save();
    canvas.translate(motorCenter.dx, motorCenter.dy);
    canvas.rotate(rotAngle);

    final bladePaint = Paint()
      ..color = isHighlighted ? const Color(0xFF00E5FF).withValues(alpha: 0.45) : palette.ink.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    final bladeBorder = Paint()
      ..color = isHighlighted ? const Color(0xFF00E5FF).withValues(alpha: 0.7) : palette.ink.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final tipPaint = Paint()
      ..color = isCw ? palette.warningInk.withValues(alpha: 0.7) : palette.okInk.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    // Draw dual aerodynamic propeller blades (blade 1 at 0 rad, blade 2 at pi rad)
    for (int b = 0; b < 2; b++) {
      final angle = b * math.pi;
      canvas.save();
      canvas.rotate(angle);

      final propPath = Path();
      propPath.moveTo(4, -3);
      propPath.quadraticBezierTo(propRadius * 0.55, -7.5, propRadius, 0);
      propPath.quadraticBezierTo(propRadius * 0.55, 6.0, 4, 3);
      propPath.close();

      canvas.drawPath(propPath, bladePaint);
      canvas.drawPath(propPath, bladeBorder);

      // Tip color band
      final tipPath = Path();
      tipPath.moveTo(propRadius - 6, -3.5);
      tipPath.quadraticBezierTo(propRadius - 2, -4.5, propRadius, 0);
      tipPath.quadraticBezierTo(propRadius - 2, 4.0, propRadius - 6, 3.0);
      tipPath.close();
      canvas.drawPath(tipPath, tipPaint);

      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MotorDiagramPainter old) => true;
}
