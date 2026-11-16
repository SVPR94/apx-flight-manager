// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// A number entry that commits on Enter or when focus leaves, and checks
/// the range before committing (out of range shows the limits and keeps the
/// old value).
class NumField extends StatefulWidget {
  const NumField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.unit = '',
    this.min,
    this.max,
    this.decimals = 1,
    this.help,
    this.enabled = true,
    this.integer = false,
  });

  final String label, unit;
  final double value;
  final ValueChanged<double> onChanged;
  final double? min, max;
  final int decimals;
  final String? help;
  final bool enabled, integer;

  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final _c = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();
  String? _error;

  String _fmt(double v) {
    if (v.isNaN) return '';
    if (widget.integer) return v.round().toString();
    final s = v.toStringAsFixed(widget.decimals);
    // Trim zeros after the decimal point only ("360" stays "360").
    return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _c.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_c.text.trim().replaceAll(',', '.'));
    if (v == null) {
      setState(() => _error = 'Enter a number');
      return;
    }
    if ((widget.min != null && v < widget.min!) || (widget.max != null && v > widget.max!)) {
      setState(() => _error = '${_fmt(widget.min ?? double.negativeInfinity)}–${_fmt(widget.max ?? double.infinity)}');
      return;
    }
    setState(() => _error = null);
    final out = widget.integer ? v.roundToDouble() : v;
    if (out != widget.value) widget.onChanged(out);
    _c.text = _fmt(out);
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.help ?? '',
    waitDuration: const Duration(milliseconds: 600),
    child: TextField(
      controller: _c,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer, signed: (widget.min ?? -1) < 0),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
      onSubmitted: (_) => _commit(),
      style: AlloyText.mono(14, weight: FontWeight.w500),
      decoration: InputDecoration(labelText: widget.label, suffixText: widget.unit, errorText: _error, isDense: true),
    ),
  );
}

/// A value that follows a default unless the user sets it.
class OptionalNumField extends StatelessWidget {
  const OptionalNumField({
    super.key,
    required this.label,
    required this.value,
    required this.defaultLabel,
    required this.onChanged,
    required this.fallback,
    this.unit = '',
    this.min,
    this.max,
    this.decimals = 1,
  });

  final String label, unit, defaultLabel;
  final double? value;

  /// Value used when the user switches from default to custom.
  final double fallback;
  final ValueChanged<double?> onChanged;
  final double? min, max;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Row(
      children: [
        Expanded(
          child: value == null
              ? InputDecorator(
                  decoration: InputDecoration(labelText: label, isDense: true),
                  child: Text(defaultLabel, style: TextStyle(color: p.ink2)),
                )
              : NumField(
                  label: label,
                  value: value!,
                  unit: unit,
                  min: min,
                  max: max,
                  decimals: decimals,
                  onChanged: onChanged,
                ),
        ),
        Tooltip(
          message: value == null ? 'Set a value' : 'Use the default',
          child: Checkbox(value: value != null, onChanged: (v) => onChanged(v == true ? fallback : null)),
        ),
      ],
    );
  }
}

/// A dropdown with a label, in the same style as the text fields.
class ChoiceField<T> extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: options.containsKey(value) ? value : null,
    isDense: true,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      for (final e in options.entries)
        DropdownMenuItem(
          value: e.key,
          child: Text(e.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

/// Lays fields out two per row on wide panels, one per row when narrow.
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children, this.columns = 2});
  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth < 300 ? 1 : columns;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 12,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    },
  );
}

/// A titled card for settings pages.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    // Material (not a coloured box) so list tiles and switches inside show ink.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: p.brightness == Brightness.light ? Colors.white : p.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!, style: TextStyle(fontSize: 12, color: p.ink2)),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
