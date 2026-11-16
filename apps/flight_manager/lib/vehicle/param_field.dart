// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/fields.dart';
import '../design/tokens.dart';
import '../state/vehicle_params.dart';

/// How a curated parameter is shown: label, friendly unit and the factor
/// from the firmware's unit (e.g. cm/s → m/s is 0.01).
final class ParamView {
  const ParamView(this.name, this.label, {this.unit = '', this.scale = 1, this.decimals = 1, this.options, this.help});
  final String name, label, unit;
  final double scale;
  final int decimals;
  final Map<int, String>? options;
  final String? help;
}

/// One vehicle parameter, edited in place. Uses the firmware's own range and
/// description (generated from APX's param_manager.cpp) and reports when
/// APX silently clamps a value or doesn't answer.
class ParamField extends ConsumerStatefulWidget {
  const ParamField(this.view, {super.key});
  final ParamView view;

  @override
  ConsumerState<ParamField> createState() => _ParamFieldState();
}

class _ParamFieldState extends ConsumerState<ParamField> {
  String? _status;
  bool _statusIsError = false;
  bool _busy = false;

  Future<void> _set(ParameterService svc, double raw) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final r = await svc.set(widget.view.name, raw);
    if (!mounted) return;
    final v = widget.view;
    String show(double x) => '${(x * v.scale).toStringAsFixed(v.decimals)}${v.unit.isEmpty ? '' : ' ${v.unit}'}';
    setState(() {
      _busy = false;
      switch (r.outcome) {
        case ParamSetOutcome.applied:
          _status = 'Saved on the vehicle';
          _statusIsError = false;
        case ParamSetOutcome.clamped:
          _status = 'The vehicle limited it to ${show(r.stored!)}';
          _statusIsError = true;
        case ParamSetOutcome.noReply:
          _status = 'No reply from the vehicle; not changed';
          _statusIsError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    final v = widget.view;
    // Rebuilds when this parameter changes, not every frame.
    final svc = ref.watch(paramServiceProvider);
    final param = ref.watch(paramValueProvider(v.name));
    final meta = ParamMeta.of(v.name);
    final help = [v.help, meta?.description].nonNulls.join('\n');
    if (svc == null || param == null) {
      return InputDecorator(
        decoration: InputDecoration(labelText: v.label, isDense: true, enabled: false),
        child: Text(svc == null ? '—' : 'Not on this vehicle', style: TextStyle(color: p.ink2)),
      );
    }
    final modified = meta != null && (param.value - meta.defaultValue).abs() > 1e-6 * (1 + meta.defaultValue.abs());
    final field = v.options != null
        ? ChoiceField<int>(
            label: v.label,
            value: param.value.round(),
            options: {
              ...v.options!,
              if (!v.options!.containsKey(param.value.round())) param.value.round(): '${param.value.round()}',
            },
            onChanged: (x) => _set(svc, x.toDouble()),
          )
        : NumField(
            label: v.label,
            unit: v.unit,
            value: param.value * v.scale,
            min: meta == null ? null : meta.min * v.scale,
            max: meta == null ? null : meta.max * v.scale,
            decimals: v.decimals,
            integer: param.isInteger && v.scale == 1,
            help: help,
            enabled: !_busy,
            onChanged: (x) => _set(svc, x / v.scale),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: field),
            if (modified)
              Tooltip(
                message:
                    'Changed from the default (${(meta.defaultValue * v.scale).toStringAsFixed(v.decimals)}). Click to reset.',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.rotateCcw, size: 15, color: AlloyPalette.accent),
                  onPressed: _busy ? null : () => _set(svc, meta.defaultValue),
                ),
              ),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Text(
              _status!,
              style: TextStyle(fontSize: 11, color: _statusIsError ? AlloyPalette.warning : p.okInk),
            ),
          ),
      ],
    );
  }
}

/// A grid of curated parameters.
class ParamGrid extends StatelessWidget {
  const ParamGrid(this.views, {super.key});
  final List<ParamView> views;
  @override
  Widget build(BuildContext context) => FieldGrid(children: [for (final v in views) ParamField(v)]);
}
