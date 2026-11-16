// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/tokens.dart';
import 'video_layout.dart';

/// A floating picture‑in‑picture window over the Fly view (standard GCS
/// PiP): drag it anywhere — it settles into the nearest corner — resize it by
/// the grip or with two fingers, tap it to swap with the main view.
///
/// Fills its parent [Stack] but only the window itself takes touches.
class PipWindow extends StatefulWidget {
  const PipWindow({
    super.key,
    required this.layout,
    required this.insets,
    required this.label,
    required this.child,
    required this.onSwap,
    required this.onHide,
    required this.onCorner,
    required this.onWidth,
    this.onFullscreen,
    this.actions = const [],
    this.aspect = 16 / 9,
  });

  final VideoLayout layout;

  /// Clear space to keep from the edges (status rail, tool column).
  final EdgeInsets insets;
  final String label;
  final Widget child;
  final VoidCallback onSwap, onHide;
  final VoidCallback? onFullscreen;
  final ValueChanged<PipCorner> onCorner;
  final ValueChanged<double> onWidth;

  /// Extra header buttons (e.g. record).
  final List<Widget> actions;
  final double aspect;

  @override
  State<PipWindow> createState() => _PipWindowState();
}

class _PipWindowState extends State<PipWindow> {
  /// Top-left while being dragged; null when resting in its corner.
  Offset? _drag;

  /// Width while being resized.
  double? _width;
  double _scaleStartWidth = 0;
  bool _hover = false;

  static final _touch = Platform.isAndroid || Platform.isIOS;

  Offset _cornerOrigin(PipCorner c, Size area, Size win) {
    final i = widget.insets;
    final left = i.left, right = area.width - i.right - win.width;
    final top = i.top, bottom = area.height - i.bottom - win.height;
    return switch (c) {
      PipCorner.topLeft => Offset(left, top),
      PipCorner.topRight => Offset(right, top),
      PipCorner.bottomLeft => Offset(left, bottom),
      PipCorner.bottomRight => Offset(right, bottom),
    };
  }

  PipCorner _nearest(Offset origin, Size area, Size win) {
    final c = origin + Offset(win.width / 2, win.height / 2);
    final left = c.dx < area.width / 2, top = c.dy < area.height / 2;
    return top
        ? (left ? PipCorner.topLeft : PipCorner.topRight)
        : (left ? PipCorner.bottomLeft : PipCorner.bottomRight);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final area = box.biggest;
          final i = widget.insets;
          // Never larger than 60 % of the free width or 60 % of the height.
          final maxW = [
            VideoLayout.maxWidth,
            (area.width - i.horizontal) * 0.6,
            (area.height - i.vertical) * 0.6 * widget.aspect,
          ].reduce((a, b) => a < b ? a : b);
          final w = (_width ?? widget.layout.pipWidth).clamp(
            VideoLayout.minWidth < maxW ? VideoLayout.minWidth : maxW,
            maxW,
          );
          final win = Size(w, w / widget.aspect);
          final origin = _drag ?? _cornerOrigin(widget.layout.corner, area, win);
          return Stack(
            children: [
              AnimatedPositioned(
                duration: _drag == null && _width == null ? Alloy.panel : Duration.zero,
                curve: Alloy.curve,
                left: origin.dx.clamp(0, (area.width - win.width).clamp(0, double.infinity)),
                top: origin.dy.clamp(0, (area.height - win.height).clamp(0, double.infinity)),
                width: win.width,
                height: win.height,
                child: _window(context, area, win, origin),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _window(BuildContext context, Size area, Size win, Offset origin) {
    final p = context.alloy;
    final showHeader = _touch || _hover || _drag != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSwap,
        onScaleStart: (d) {
          _scaleStartWidth = win.width;
          if (d.pointerCount < 2) setState(() => _drag = origin);
        },
        onScaleUpdate: (d) {
          setState(() {
            if (d.pointerCount >= 2) {
              _drag = null;
              _width = _scaleStartWidth * d.scale;
            } else {
              _drag = (_drag ?? origin) + d.focalPointDelta;
            }
          });
        },
        onScaleEnd: (_) {
          final drag = _drag, width = _width;
          setState(() {
            _drag = null;
            _width = null;
          });
          if (drag != null) widget.onCorner(_nearest(drag, area, win));
          if (width != null) widget.onWidth(width);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.glassEdge, width: 1.5),
            boxShadow: [BoxShadow(color: p.shadow, blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                // Header: what this is, and its buttons.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: AnimatedOpacity(
                    opacity: showHeader ? 1 : 0,
                    duration: Alloy.fast,
                    child: IgnorePointer(ignoring: !showHeader, child: _header()),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(opacity: showHeader ? 1 : 0, duration: Alloy.fast, child: _resizeGrip(win)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xB0000000), Color(0x00000000)],
      ),
    ),
    child: Row(
      children: [
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        ...widget.actions,
        _HeaderButton(icon: LucideIcons.arrowLeftRight, tooltip: 'Swap with the main view', onPressed: widget.onSwap),
        if (widget.onFullscreen != null)
          _HeaderButton(icon: LucideIcons.maximize, tooltip: 'Full screen', onPressed: widget.onFullscreen!),
        _HeaderButton(icon: LucideIcons.minus, tooltip: 'Hide window', onPressed: widget.onHide),
      ],
    ),
  );

  /// Bottom-right grip: drag to resize (mouse; two fingers work anywhere).
  Widget _resizeGrip(Size win) => MouseRegion(
    cursor: SystemMouseCursors.resizeDownRight,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _scaleStartWidth = win.width,
      onPanUpdate: (d) => setState(() => _width = (_width ?? _scaleStartWidth) + d.delta.dx),
      onPanEnd: (_) {
        final w = _width;
        setState(() => _width = null);
        if (w != null) widget.onWidth(w);
      },
      child: const SizedBox(
        width: 26,
        height: 26,
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Icon(LucideIcons.moveDiagonal2, size: 14, color: Colors.white70),
          ),
        ),
      ),
    ),
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 16,
    color: Colors.white,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    icon: Icon(icon),
  );
}
