// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter/material.dart';

/// Alloy design tokens (docs/03_UI_CONCEPT.md). Read with `context.alloy`.
@immutable
class AlloyPalette extends ThemeExtension<AlloyPalette> {
  const AlloyPalette({
    required this.brightness,
    required this.canvas,
    required this.plate,
    required this.hairline,
    required this.ink,
    required this.ink2,
    required this.onInk,
    required this.glass,
    required this.glassEdge,
    required this.shadow,
    required this.pill,
    required this.inset,
    required this.accentBg,
    required this.accentInk,
    required this.cautionBg,
    required this.cautionInk,
    required this.warningBg,
    required this.warningInk,
    required this.okBg,
    required this.okInk,
    required this.sky,
    required this.ground,
  });

  final Brightness brightness;
  final Color canvas, plate, hairline, ink, ink2, onInk;
  final Color glass, glassEdge, shadow, pill, inset;
  final Color accentBg, accentInk;
  final Color cautionBg, cautionInk, warningBg, warningInk, okBg, okInk;
  final List<Color> sky, ground;

  // Shared across themes.
  static const accent = Color(0xFF0E9AA7);
  static const ok = Color(0xFF2FA36B);
  static const caution = Color(0xFFD99A1E);
  static const warning = Color(0xFFE0622B);
  static const critical = Color(0xFFD93A3A);
  static const instrumentYellow = Color(0xFFF2C14E);

  static const silver = AlloyPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFE6E8EB),
    plate: Color(0xFFF4F5F7),
    hairline: Color(0xFFC9CDD3),
    ink: Color(0xFF1D1F23),
    ink2: Color(0xFF545961),
    onInk: Color(0xFFF7F8FA),
    glass: Color(0xCCF7F8FA),
    glassEdge: Color(0xF2FFFFFF),
    shadow: Color(0x291E2228),
    pill: Color(0x0D1D1F23),
    inset: Color(0x0F1D1F23),
    accentBg: Color(0x1F0E9AA7),
    accentInk: Color(0xFF0B7C87),
    cautionBg: Color(0xFFF6EBD3),
    cautionInk: Color(0xFF6E4B06),
    warningBg: Color(0xFFF9E1D5),
    warningInk: Color(0xFF8A3410),
    okBg: Color(0xFFDDF1E6),
    okInk: Color(0xFF1F6E47),
    sky: [Color(0xFF9DB7CB), Color(0xFFC9D7E2)],
    ground: [Color(0xFF8C8275), Color(0xFF6B6358)],
  );

  static const graphite = AlloyPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF16181B),
    plate: Color(0xFF1E2125),
    hairline: Color(0xFF33373D),
    ink: Color(0xFFECEEF1),
    ink2: Color(0xFFA3A9B1),
    onInk: Color(0xFF16181B),
    glass: Color(0xCC1E2125),
    glassEdge: Color(0x1AFFFFFF),
    shadow: Color(0x73000000),
    pill: Color(0x0FFFFFFF),
    inset: Color(0x4D000000),
    accentBg: Color(0x242FB8C4),
    accentInk: Color(0xFF5CCFD9),
    cautionBg: Color(0x2ED99A1E),
    cautionInk: Color(0xFFF0C268),
    warningBg: Color(0x2EE0622B),
    warningInk: Color(0xFFF4A27E),
    okBg: Color(0x2E2FA36B),
    okInk: Color(0xFF7FD6A8),
    sky: [Color(0xFF3E5869), Color(0xFF2A3D4A)],
    ground: [Color(0xFF4B4339), Color(0xFF332E27)],
  );

  @override
  AlloyPalette copyWith() => this;

  @override
  AlloyPalette lerp(AlloyPalette? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Spacing, radii and motion.
abstract final class Alloy {
  static const gap = 8.0;
  static const radiusControl = 10.0;
  static const radiusPanel = 18.0;
  static const radiusCapsule = 22.0;
  static const touch = 44.0;
  static const fast = Duration(milliseconds: 180);
  static const panel = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;
  static const blur = 24.0;
}

/// Type helpers. Live numbers use [mono] so digits never change width.
abstract final class AlloyText {
  static const family = 'Inter';
  static const monoFamily = 'JetBrainsMono';

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w600, Color? color}) => TextStyle(
    fontFamily: monoFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
    height: 1.1,
  );

  static TextStyle label(Color color) =>
      TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: color);
}

extension AlloyContext on BuildContext {
  AlloyPalette get alloy => Theme.of(this).extension<AlloyPalette>()!;
}

ThemeData alloyTheme(AlloyPalette p) {
  final base = ThemeData(
    brightness: p.brightness,
    fontFamily: AlloyText.family,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AlloyPalette.accent,
      brightness: p.brightness,
    ).copyWith(surface: p.plate, onSurface: p.ink, primary: AlloyPalette.accent, error: AlloyPalette.critical),
    scaffoldBackgroundColor: p.canvas,
    extensions: [p],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    dividerColor: p.hairline,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      // Room for the label inside the box (see AlloyFieldBorder).
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      fillColor: p.brightness == Brightness.light ? Colors.white : const Color(0xFF26292E),
      border: AlloyFieldBorder(borderSide: BorderSide(color: p.hairline)),
      enabledBorder: AlloyFieldBorder(borderSide: BorderSide(color: p.hairline)),
      focusedBorder: const AlloyFieldBorder(borderSide: BorderSide(color: AlloyPalette.accent, width: 1.6)),
      errorBorder: const AlloyFieldBorder(borderSide: BorderSide(color: AlloyPalette.warning)),
      focusedErrorBorder: const AlloyFieldBorder(borderSide: BorderSide(color: AlloyPalette.warning, width: 1.6)),
      disabledBorder: AlloyFieldBorder(borderSide: BorderSide(color: p.hairline.withValues(alpha: 0.5))),
      labelStyle: TextStyle(color: p.ink2),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: p.onInk, fontSize: 12),
    ),
  );
}

/// A rounded box border whose label sits inside the field (like a filled
/// field) instead of cutting a gap in the outline. An outline label straddles
/// the edge, half over the field's fill and half over whatever is behind it,
/// which looks muddy on glass and tinted panels.
class AlloyFieldBorder extends OutlineInputBorder {
  const AlloyFieldBorder({super.borderSide = const BorderSide(), super.borderRadius = _radius});

  static const _radius = BorderRadius.all(Radius.circular(Alloy.radiusControl));

  @override
  bool get isOutline => false;

  @override
  AlloyFieldBorder copyWith({BorderSide? borderSide, BorderRadius? borderRadius, double? gapPadding}) =>
      AlloyFieldBorder(borderSide: borderSide ?? this.borderSide, borderRadius: borderRadius ?? this.borderRadius);

  @override
  AlloyFieldBorder scale(double t) => AlloyFieldBorder(borderSide: borderSide.scale(t), borderRadius: borderRadius * t);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is OutlineInputBorder
      ? AlloyFieldBorder(
          borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is OutlineInputBorder
      ? AlloyFieldBorder(
          borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
          borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        )
      : super.lerpTo(b, t);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) => super.paint(canvas, rect, textDirection: textDirection);
}
