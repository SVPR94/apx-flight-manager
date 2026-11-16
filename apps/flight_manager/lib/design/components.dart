// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'tokens.dart';

/// Frosted panel that floats over the map.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = Alloy.radiusPanel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    // Panels float over a map that redraws as it moves: a repaint boundary
    // keeps each panel's own drawing (shadow, border) from being redone with
    // it, and grouped backdrops share one capture of what's behind them
    // (see the BackdropGroup in the shell) instead of one per panel.
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: p.shadow, blurRadius: 32, offset: const Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter.grouped(
            filter: ImageFilter.blur(sigmaX: Alloy.blur, sigmaY: Alloy.blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.glass,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: p.glassEdge),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

enum Tone { neutral, accent, ok, caution, warning, critical, inverted }

({Color bg, Color fg}) toneColors(AlloyPalette p, Tone t) => switch (t) {
  Tone.neutral => (bg: p.pill, fg: p.ink),
  Tone.accent => (bg: p.accentBg, fg: p.accentInk),
  Tone.ok => (bg: p.okBg, fg: p.okInk),
  Tone.caution => (bg: p.cautionBg, fg: p.cautionInk),
  Tone.warning => (bg: p.warningBg, fg: p.warningInk),
  Tone.critical => (bg: AlloyPalette.critical, fg: Colors.white),
  Tone.inverted => (bg: p.ink, fg: p.onInk),
};

/// Capsule used in the status rail. Status is never colour‑only: always an
/// icon and words.
class Pill extends StatelessWidget {
  const Pill({super.key, this.icon, required this.children, this.tone = Tone.neutral, this.onTap, this.tooltip});

  final IconData? icon;
  final List<Widget> children;
  final Tone tone;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(context.alloy, tone);
    Widget body = AnimatedContainer(
      duration: Alloy.fast,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(18)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: c.fg, fontSize: 13, fontWeight: FontWeight.w500),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            if (icon != null) Icon(icon, size: 16, color: c.fg),
            ...children,
          ],
        ),
      ),
    );
    if (onTap != null) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: body),
      );
    }
    return tooltip == null ? body : Tooltip(message: tooltip!, child: body);
  }
}

/// Number + unit in the telemetry font.
class Reading extends StatelessWidget {
  const Reading(this.value, {super.key, this.unit, this.size = 13, this.color});
  final String value;
  final String? unit;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: AlloyText.mono(size, color: color),
          ),
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: TextStyle(fontSize: size * 0.85, color: p.ink2),
            ),
        ],
      ),
    );
  }
}

class AlloyButton extends StatelessWidget {
  const AlloyButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.expand = false,
    this.stacked = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool expand;

  /// Icon above the label, for narrow buttons side by side.
  final bool stacked;

  static const _iconSize = 18.0;
  // fontFamily explicitly: a ButtonStyle textStyle replaces the theme's.
  static const _text = TextStyle(fontFamily: AlloyText.family, fontWeight: FontWeight.w600, fontSize: 13);

  @override
  Widget build(BuildContext context) {
    final b = LayoutBuilder(
      builder: (context, box) {
        // Squeezed buttons give up padding, then the icon, before the label.
        var pad = 16.0, gap = 8.0, showIcon = icon != null;
        if (!stacked && box.hasBoundedWidth) {
          final textWidth = (TextPainter(
            text: TextSpan(text: label, style: _text),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout()).width;
          double need(double pad, double gap, bool withIcon) =>
              2 * pad + textWidth + (withIcon ? _iconSize + gap : 0) + 1;
          if (box.maxWidth < need(pad, gap, showIcon)) {
            pad = 8;
            gap = 6;
            if (showIcon && box.maxWidth < need(pad, gap, true)) showIcon = false;
          }
        }
        if (stacked) pad = 6;
        return _button(context, pad, gap, showIcon);
      },
    );
    return expand ? SizedBox(width: double.infinity, child: b) : b;
  }

  Widget _button(BuildContext context, double pad, double gap, bool showIcon) {
    final p = context.alloy;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, stacked ? 52 : Alloy.touch)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: pad, vertical: stacked ? 6 : 0)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: primary ? BorderSide.none : BorderSide(color: p.hairline),
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return p.pill;
        return primary ? p.ink : p.pill;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return p.ink2.withValues(alpha: 0.6);
        return primary ? p.onInk : p.ink;
      }),
      textStyle: const WidgetStatePropertyAll(_text),
      elevation: const WidgetStatePropertyAll(0),
    );
    final text = Text(label, overflow: TextOverflow.ellipsis, maxLines: 1, textAlign: TextAlign.center);
    final child = stacked
        ? Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 3,
            children: [
              if (icon != null) Icon(icon, size: _iconSize),
              text,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: gap,
            children: [
              if (showIcon) Icon(icon, size: _iconSize),
              Flexible(child: text),
            ],
          );
    final button = TextButton(style: style, onPressed: onPressed, child: child);
    // The label is the name; keep it reachable when it had to be shortened.
    return showIcon || icon == null || stacked ? button : Tooltip(message: label, child: button);
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      color: active ? p.accentInk : p.ink,
      constraints: const BoxConstraints.tightFor(width: Alloy.touch, height: Alloy.touch),
    );
  }
}

/// Deliberate gesture for safety‑critical actions: drag the knob to the end.
/// Releasing early springs back.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.icon,
    required this.onConfirmed,
    this.enabled = true,
    this.tone = Tone.neutral,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onConfirmed;
  final bool enabled;
  final Tone tone;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> with SingleTickerProviderStateMixin {
  static const _knob = 44.0;
  double _drag = 0;
  bool _busy = false;
  late final AnimationController _spring = AnimationController(vsync: this, duration: Alloy.panel)
    ..addListener(() => setState(() => _drag = _from * (1 - Alloy.curve.transform(_spring.value))));
  double _from = 0;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  Future<void> _release(double max) async {
    if (_drag >= max * 0.92 && widget.enabled) {
      setState(() {
        _drag = max;
        _busy = true;
      });
      try {
        await widget.onConfirmed();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;
    _from = _drag;
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final tone = toneColors(p, widget.tone);
    return LayoutBuilder(
      builder: (context, c) {
        final max = c.maxWidth - _knob - 8;
        final progress = max <= 0 ? 0.0 : (_drag / max).clamp(0.0, 1.0);
        return Semantics(
          button: true,
          enabled: widget.enabled,
          label: widget.label,
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.45,
            child: Container(
              height: 52,
              decoration: BoxDecoration(color: p.inset, borderRadius: BorderRadius.circular(26)),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (progress * 0.9 + (progress > 0 ? 0.1 : 0)).clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.tone == Tone.neutral ? p.accentBg : tone.bg.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(left: _knob),
                      child: Text(
                        _busy ? 'Sending…' : widget.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: p.ink2.withValues(alpha: 1 - progress * 0.7),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4 + _drag,
                    child: GestureDetector(
                      onHorizontalDragUpdate: widget.enabled && !_busy
                          ? (d) => setState(() => _drag = (_drag + d.delta.dx).clamp(0, max))
                          : null,
                      onHorizontalDragEnd: widget.enabled && !_busy ? (_) => _release(max) : null,
                      child: Container(
                        width: _knob,
                        height: _knob,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Colors.white, Color(0xFFD4D8DE)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: const [BoxShadow(color: Color(0x40141820), blurRadius: 6, offset: Offset(0, 2))],
                        ),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(13),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1D1F23)),
                              )
                            : Icon(widget.icon, size: 19, color: const Color(0xFF1D1F23)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small uppercase caption above a group.
class Caption extends StatelessWidget {
  const Caption(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: AlloyText.label(context.alloy.ink2));
}

IconData severityIcon(Tone t) => switch (t) {
  Tone.ok => LucideIcons.check,
  Tone.caution => LucideIcons.triangleAlert,
  Tone.warning => LucideIcons.circleAlert,
  Tone.critical => LucideIcons.octagonX,
  _ => LucideIcons.bell,
};
