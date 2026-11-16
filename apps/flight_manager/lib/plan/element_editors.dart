// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_mission/apx_mission.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/fields.dart';
import '../design/tokens.dart';
import '../state/plan.dart';

IconData elementIcon(MissionElement e) => switch (e) {
  WaypointElement() => LucideIcons.mapPin,
  CommandElement(:final payload) when payload != null => LucideIcons.plug,
  CommandElement() => LucideIcons.slidersHorizontal,
  LandElement() => LucideIcons.planeLanding,
  SurveyElement() => LucideIcons.grid3x3,
  CorridorElement() => LucideIcons.route,
  OrbitElement() => LucideIcons.rotateCw,
};

/// One line under the element's title in the list.
String elementSummary(MissionElement e, MissionPlan plan, CompiledMission c) {
  final n = c.of(e.id).length;
  String pl(PatternPayload p) => p.active ? ' · ${plan.payload(p.payloadId)?.name ?? '?'}' : '';
  String m(double v) => v >= 10000 ? '${(v / 10000).toStringAsFixed(2)} ha' : '${v.round()} m²';
  return switch (e) {
    WaypointElement() =>
      '${e.altitude.toStringAsFixed(0)} m${e.speed != null ? ' · ${e.speed} m/s' : ''}'
          '${e.heading != null ? ' · heading ${e.heading!.round()}°' : ''}'
          '${e.actions.isNotEmpty ? ' · ${e.actions.length} payload action${e.actions.length > 1 ? 's' : ''}' : ''}',
    CommandElement(:final payload?) =>
      '${plan.payload(payload.payloadId)?.name ?? '?'} ${payload.tiltDeg != null ? 'tilt ${payload.tiltDeg!.round()}°' : (payload.on ? 'on' : 'off')}',
    CommandElement() => _commandSummary(e),
    LandElement() => e.position == null ? 'Descends at home and disarms' : 'Descends here and disarms',
    SurveyElement() =>
      '${m(polygonArea(e.polygon))} · ${e.spacing} m apart · '
          '${surveyPasses(e.polygon, spacing: e.spacing, angleDeg: e.angleDeg).length} passes${pl(e.payload)} · $n items',
    CorridorElement() => '${e.lanes} lanes · ${e.width} m wide${pl(e.payload)} · $n items',
    OrbitElement() =>
      'r ${e.radius} m · ${e.sweepDeg.round()}° in ${e.legs} legs · '
          '${switch (e.heading) {
            OrbitHeading.travel => 'facing travel',
            OrbitHeading.center => 'facing centre',
            OrbitHeading.outward => 'facing out',
            OrbitHeading.fixed => 'heading ${e.fixedHeading.round()}°',
          }}${pl(e.payload)}',
  };
}

String _commandSummary(CommandElement e) {
  final s = e.spec;
  if (s == null) return 'Unsupported';
  return [
    for (final p in s.params)
      p.options != null
          ? (p.options![e.param(p.index).round()] ?? '')
          : '${_n(e.param(p.index))}${p.unit.isEmpty ? '' : ' ${p.unit}'}',
  ].where((t) => t.isNotEmpty).join(' · ');
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Editor for the selected element.
class ElementEditor extends StatelessWidget {
  const ElementEditor({
    super.key,
    required this.element,
    required this.plan,
    required this.compiled,
    required this.onChanged,
  });
  final MissionElement element;
  final MissionPlan plan;
  final CompiledMission compiled;
  final ValueChanged<MissionElement> onChanged;

  @override
  Widget build(BuildContext context) => switch (element) {
    final WaypointElement e => _WaypointEditor(e, plan, onChanged),
    final CommandElement e => _CommandEditor(e, plan, onChanged),
    final LandElement e => _LandEditor(e, onChanged),
    final SurveyElement e => _SurveyEditor(e, plan, onChanged),
    final CorridorElement e => _CorridorEditor(e, plan, onChanged),
    final OrbitElement e => _OrbitEditor(e, plan, onChanged),
  };
}

Widget _position(GeoPoint p, ValueChanged<GeoPoint> on) => FieldGrid(
  children: [
    NumField(label: 'Latitude', value: p.lat, decimals: 7, min: -90, max: 90, onChanged: (v) => on(GeoPoint(v, p.lon))),
    NumField(
      label: 'Longitude',
      value: p.lon,
      decimals: 7,
      min: -180,
      max: 180,
      onChanged: (v) => on(GeoPoint(p.lat, v)),
    ),
  ],
);

NumField _alt(double v, ValueChanged<double> on) =>
    NumField(label: 'Altitude', unit: 'm', value: v, min: 0.5, max: 500, help: 'Above home', onChanged: on);

OptionalNumField _speed(double? v, ValueChanged<double?> on) => OptionalNumField(
  label: 'Speed',
  unit: 'm/s',
  value: v,
  fallback: 5,
  min: 0.5,
  max: 20,
  defaultLabel: 'Mission speed',
  onChanged: on,
);

OptionalNumField _radius(double? v, ValueChanged<double?> on) => OptionalNumField(
  label: 'Corner radius',
  unit: 'm',
  value: v,
  fallback: 1,
  min: 0.1,
  max: 50,
  defaultLabel: 'Vehicle default',
  onChanged: on,
);

class _WaypointEditor extends StatelessWidget {
  const _WaypointEditor(this.e, this.plan, this.on);
  final WaypointElement e;
  final MissionPlan plan;
  final ValueChanged<MissionElement> on;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      _position(e.position, (p) => on(e.copyWith(position: p))),
      FieldGrid(
        children: [
          _alt(e.altitude, (v) => on(e.copyWith(altitude: v))),
          _speed(e.speed, (v) => on(e.copyWith(speed: v, clearSpeed: v == null))),
          _radius(e.acceptRadius, (v) => on(e.copyWith(acceptRadius: v, clearRadius: v == null))),
          OptionalNumField(
            label: 'Heading',
            unit: '°',
            value: e.heading,
            fallback: 0,
            min: 0,
            max: 360,
            defaultLabel: 'Automatic',
            onChanged: (v) => on(e.copyWith(heading: v, clearHeading: v == null)),
          ),
        ],
      ),
      if (e.heading != null)
        const _Hint('APX stops to turn before this leg, then keeps the heading for the rest of the mission.'),
      _ActionsEditor(
        actions: e.actions,
        payloads: plan.payloads,
        onChanged: (a) => on(e.copyWith(actions: a)),
      ),
    ],
  );
}

/// Payload actions at a waypoint.
class _ActionsEditor extends StatelessWidget {
  const _ActionsEditor({required this.actions, required this.payloads, required this.onChanged});
  final List<PayloadAction> actions;
  final List<Payload> payloads;
  final ValueChanged<List<PayloadAction>> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(
          'On arrival',
          style: TextStyle(fontSize: 12, color: p.ink2, fontWeight: FontWeight.w600),
        ),
        for (final (i, a) in actions.indexed)
          _ActionRow(
            action: a,
            payloads: payloads,
            onChanged: (n) => onChanged([...actions]..[i] = n),
            onRemove: () => onChanged([...actions]..removeAt(i)),
          ),
        if (payloads.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Payload action'),
              onPressed: () => onChanged([...actions, PayloadAction(payloads.first.id)]),
            ),
          )
        else
          Text('Add payloads in Vehicle → Payloads.', style: TextStyle(fontSize: 12, color: p.ink2)),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.payloads, required this.onChanged, required this.onRemove});
  final PayloadAction action;
  final List<Payload> payloads;
  final ValueChanged<PayloadAction> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final pl = payloads.where((p) => p.id == action.payloadId).firstOrNull;
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: ChoiceField<String>(
            label: 'Payload',
            value: action.payloadId,
            options: {
              for (final p in payloads) p.id: p.name,
              if (pl == null) action.payloadId: '${action.payloadId} (missing)',
            },
            onChanged: (id) {
              final np = payloads.firstWhere((p) => p.id == id);
              onChanged(
                PayloadAction(
                  id,
                  on: action.on,
                  tiltDeg: np.kind == PayloadKind.gimbal ? (action.tiltDeg ?? -90) : null,
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 120,
          child: pl?.kind == PayloadKind.gimbal
              ? NumField(
                  label: 'Tilt',
                  unit: '°',
                  value: action.tiltDeg ?? -90,
                  min: -90,
                  max: 0,
                  onChanged: (v) => onChanged(PayloadAction(action.payloadId, tiltDeg: v)),
                )
              : ChoiceField<bool>(
                  label: 'State',
                  value: action.on,
                  options: const {true: 'On', false: 'Off'},
                  onChanged: (v) => onChanged(PayloadAction(action.payloadId, on: v)),
                ),
        ),
        if (onRemove != null)
          IconButton(tooltip: 'Remove', icon: const Icon(LucideIcons.x, size: 16), onPressed: onRemove),
      ],
    );
  }
}

class _CommandEditor extends StatelessWidget {
  const _CommandEditor(this.e, this.plan, this.on);
  final CommandElement e;
  final MissionPlan plan;
  final ValueChanged<MissionElement> on;

  @override
  Widget build(BuildContext context) {
    final kinds = <int, String>{-1: 'Payload', for (final c in ApxCatalog.standalone) c.id: c.name};
    final current = e.payload != null ? -1 : e.command;
    final spec = e.spec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        ChoiceField<int>(
          label: 'Action',
          value: kinds.containsKey(current) ? current : MavCmd.doChangeSpeed,
          options: kinds,
          onChanged: (k) {
            if (k == -1) {
              if (plan.payloads.isEmpty) return;
              on(CommandElement(id: e.id, payload: PayloadAction(plan.payloads.first.id)));
            } else {
              on(CommandElement(id: e.id, command: k));
            }
          },
        ),
        if (e.payload != null)
          _ActionRow(
            action: e.payload!,
            payloads: plan.payloads,
            onChanged: (a) => on(CommandElement(id: e.id, payload: a)),
            onRemove: null,
          )
        else if (spec != null) ...[
          FieldGrid(
            children: [
              for (final p in spec.params)
                p.options != null
                    ? ChoiceField<int>(
                        label: p.label,
                        value: e.param(p.index).round(),
                        options: p.options!,
                        onChanged: (v) => on(e.copyWith(params: {...e.params, p.index: v.toDouble()})),
                      )
                    : NumField(
                        label: p.label,
                        unit: p.unit,
                        value: e.param(p.index),
                        min: p.min,
                        max: p.max,
                        help: p.help,
                        onChanged: (v) => on(e.copyWith(params: {...e.params, p.index: v})),
                      ),
            ],
          ),
          if (spec.note != null) _Hint(spec.note!),
        ],
      ],
    );
  }
}

class _LandEditor extends StatelessWidget {
  const _LandEditor(this.e, this.on);
  final LandElement e;
  final ValueChanged<MissionElement> on;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Land at home'),
        value: e.position == null,
        onChanged: (home) => on(LandElement(id: e.id, position: home ? null : const GeoPoint(0, 0))),
      ),
      if (e.position != null) _position(e.position!, (p) => on(LandElement(id: e.id, position: p))),
      const _Hint('The vehicle descends, disarms on touchdown and the mission ends.'),
    ],
  );
}

/// Payload choice for a pattern.
class _PatternPayloadEditor extends StatelessWidget {
  const _PatternPayloadEditor({
    required this.value,
    required this.payloads,
    required this.onChanged,
    this.passes = true,
  });
  final PatternPayload value;
  final List<Payload> payloads;
  final ValueChanged<PatternPayload> onChanged;
  final bool passes;

  @override
  Widget build(BuildContext context) {
    final pl = payloads.where((p) => p.id == value.payloadId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        ChoiceField<String>(
          label: 'Payload',
          value: value.payloadId ?? '',
          options: {'': 'None', for (final p in payloads) p.id: p.name},
          onChanged: (id) => onChanged(id.isEmpty ? value.copyWith(clear: true) : value.copyWith(payloadId: id)),
        ),
        if (pl != null && passes)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Only on the passes'),
            subtitle: Text(value.onlyOnLines ? 'Off in the turns' : 'On for the whole pattern'),
            value: value.onlyOnLines,
            onChanged: (v) => onChanged(value.copyWith(onlyOnLines: v)),
          ),
        if (pl?.kind == PayloadKind.gimbal)
          NumField(
            label: 'Gimbal tilt',
            unit: '°',
            value: value.gimbalTiltDeg,
            min: -90,
            max: 0,
            onChanged: (v) => onChanged(value.copyWith(gimbalTiltDeg: v)),
          ),
      ],
    );
  }
}

class _SurveyEditor extends StatelessWidget {
  const _SurveyEditor(this.e, this.plan, this.on);
  final SurveyElement e;
  final MissionPlan plan;
  final ValueChanged<MissionElement> on;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      FieldGrid(
        children: [
          _alt(e.altitude, (v) => on(e.copyWith(altitude: v))),
          NumField(
            label: 'Pass spacing',
            unit: 'm',
            value: e.spacing,
            min: 0.5,
            max: 500,
            help: 'Swath width × (1 − overlap)',
            onChanged: (v) => on(e.copyWith(spacing: v)),
          ),
          NumField(
            label: 'Pass direction',
            unit: '°',
            value: e.angleDeg,
            min: 0,
            max: 360,
            decimals: 0,
            onChanged: (v) => on(e.copyWith(angleDeg: v)),
          ),
          NumField(
            label: 'Run‑in / run‑out',
            unit: 'm',
            value: e.overshoot,
            min: 0,
            max: 100,
            help: 'Extra distance beyond the edge so the vehicle is straight when the payload switches',
            onChanged: (v) => on(e.copyWith(overshoot: v)),
          ),
          _speed(e.speed, (v) => on(e.copyWith(speed: v, clearSpeed: v == null))),
          _radius(e.acceptRadius, (v) => on(e.copyWith(acceptRadius: v, clearRadius: v == null))),
        ],
      ),
      _SwathHelper(onSpacing: (v) => on(e.copyWith(spacing: v))),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.ruler, size: 16),
            label: const Text('Along longest edge'),
            onPressed: () => on(e.copyWith(angleDeg: PlanController.longestEdgeBearing(e.polygon))),
          ),
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.rotateCw, size: 16),
            label: const Text('Rotate 90°'),
            onPressed: () => on(e.copyWith(angleDeg: (e.angleDeg + 90) % 180)),
          ),
          FilterChip(
            label: const Text('Start from other side'),
            selected: e.reverse,
            onSelected: (v) => on(e.copyWith(reverse: v)),
          ),
        ],
      ),
      _PatternPayloadEditor(
        value: e.payload,
        payloads: plan.payloads,
        onChanged: (p) => on(e.copyWith(payload: p)),
      ),
      const _Hint('Drag the corners on the map; tap a + between corners to add one, long‑press a corner to remove it.'),
    ],
  );
}

/// Spacing from swath width and overlap.
class _SwathHelper extends StatefulWidget {
  const _SwathHelper({required this.onSpacing});
  final ValueChanged<double> onSpacing;
  @override
  State<_SwathHelper> createState() => _SwathHelperState();
}

class _SwathHelperState extends State<_SwathHelper> {
  double _width = 5, _overlap = 10;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    dense: true,
    title: const Text('Spacing from swath width'),
    children: [
      FieldGrid(
        columns: 3,
        children: [
          NumField(
            label: 'Swath width',
            unit: 'm',
            value: _width,
            min: 0.5,
            max: 200,
            onChanged: (v) => setState(() => _width = v),
          ),
          NumField(
            label: 'Overlap',
            unit: '%',
            value: _overlap,
            min: 0,
            max: 90,
            decimals: 0,
            onChanged: (v) => setState(() => _overlap = v),
          ),
          FilledButton.tonal(
            onPressed: () => widget.onSpacing(double.parse((_width * (1 - _overlap / 100)).toStringAsFixed(2))),
            child: Text('Use ${(_width * (1 - _overlap / 100)).toStringAsFixed(2)} m'),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );
}

class _CorridorEditor extends StatelessWidget {
  const _CorridorEditor(this.e, this.plan, this.on);
  final CorridorElement e;
  final MissionPlan plan;
  final ValueChanged<MissionElement> on;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      FieldGrid(
        children: [
          _alt(e.altitude, (v) => on(e.copyWith(altitude: v))),
          NumField(
            label: 'Width',
            unit: 'm',
            value: e.width,
            min: 0.5,
            max: 1000,
            onChanged: (v) => on(e.copyWith(width: v)),
          ),
          NumField(
            label: 'Lane spacing',
            unit: 'm',
            value: e.spacing,
            min: 0.5,
            max: 500,
            onChanged: (v) => on(e.copyWith(spacing: v)),
          ),
          NumField(
            label: 'Run‑in / run‑out',
            unit: 'm',
            value: e.overshoot,
            min: 0,
            max: 100,
            onChanged: (v) => on(e.copyWith(overshoot: v)),
          ),
          _speed(e.speed, (v) => on(e.copyWith(speed: v, clearSpeed: v == null))),
          _radius(e.acceptRadius, (v) => on(e.copyWith(acceptRadius: v, clearRadius: v == null))),
        ],
      ),
      _PatternPayloadEditor(
        value: e.payload,
        payloads: plan.payloads,
        onChanged: (p) => on(e.copyWith(payload: p)),
      ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(LucideIcons.arrowLeftRight, size: 16),
              label: Text(
                'Reverse Corridor Direction (${e.path.length} points)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              onPressed: e.path.length < 2 ? null : () => on(e.copyWith(path: e.path.reversed.toList())),
            ),
          ),
        ],
      ),
      _Hint('${e.lanes} lane${e.lanes > 1 ? 's' : ''}, flown back and forth. Drag the path points on the map.'),
    ],
  );
}

class _OrbitEditor extends StatelessWidget {
  const _OrbitEditor(this.e, this.plan, this.on);
  final OrbitElement e;
  final MissionPlan plan;
  final ValueChanged<MissionElement> on;

  @override
  Widget build(BuildContext context) {
    final p = context.alloy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        _position(e.center, (c) => on(e.copyWith(center: c))),
        FieldGrid(
          children: [
            NumField(
              label: 'Radius',
              unit: 'm',
              value: e.radius,
              min: 2,
              max: 2000,
              onChanged: (v) => on(e.copyWith(radius: v)),
            ),
            _alt(e.altitude, (v) => on(e.copyWith(altitude: v))),
            NumField(
              label: 'Start at',
              unit: '°',
              value: e.startBearing,
              min: 0,
              max: 360,
              decimals: 0,
              help: 'Bearing from the centre',
              onChanged: (v) => on(e.copyWith(startBearing: v)),
            ),
            NumField(
              label: 'Angle to fly',
              unit: '°',
              value: e.sweepDeg,
              min: 1,
              max: 3600,
              decimals: 0,
              help: '360 = one full turn',
              onChanged: (v) => on(e.copyWith(sweepDeg: v)),
            ),
          ],
        ),
        Text(
          'Flight Direction (Circular Orbit)',
          style: TextStyle(fontSize: 12, color: p.ink2, fontWeight: FontWeight.w600),
        ),
        SegmentedButton<bool>(
          showSelectedIcon: true,
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Clockwise (CW)'),
              tooltip: 'Fly circular navigation in clockwise direction',
              icon: Icon(LucideIcons.rotateCw, size: 16),
            ),
            ButtonSegment(
              value: false,
              label: Text('Counter‑Clockwise (CCW)'),
              tooltip: 'Fly circular navigation in counter‑clockwise direction',
              icon: Icon(LucideIcons.rotateCcw, size: 16),
            ),
          ],
          selected: {e.clockwise},
          onSelectionChanged: (v) => on(e.copyWith(clockwise: v.single)),
        ),
        OutlinedButton.icon(
          icon: Icon(e.clockwise ? LucideIcons.rotateCcw : LucideIcons.rotateCw, size: 15),
          label: Text(
            e.clockwise ? 'Reverse to Counter-Clockwise (CCW)' : 'Reverse to Clockwise (CW)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          onPressed: () => on(e.copyWith(clockwise: !e.clockwise)),
        ),
        Text(
          'Leg angle ${e.resolutionDeg.round()}° → ${e.legs} straight legs',
          style: TextStyle(color: p.ink2, fontSize: 12),
        ),
        Slider(
          value: e.resolutionDeg.clamp(5, 90),
          min: 5,
          max: 90,
          divisions: 17,
          label: '${e.resolutionDeg.round()}°',
          onChanged: (v) => on(e.copyWith(resolutionDeg: v)),
        ),
        Text(
          'Heading',
          style: TextStyle(fontSize: 12, color: p.ink2, fontWeight: FontWeight.w600),
        ),
        SegmentedButton<OrbitHeading>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: OrbitHeading.travel, label: Text('Travel')),
            ButtonSegment(value: OrbitHeading.center, label: Text('Centre')),
            ButtonSegment(value: OrbitHeading.outward, label: Text('Outward')),
            ButtonSegment(value: OrbitHeading.fixed, label: Text('Fixed')),
          ],
          selected: {e.heading},
          onSelectionChanged: (v) => on(e.copyWith(heading: v.single)),
        ),
        FieldGrid(
          children: [
            if (e.heading == OrbitHeading.fixed)
              NumField(
                label: 'Heading',
                unit: '°',
                value: e.fixedHeading,
                min: 0,
                max: 360,
                decimals: 0,
                onChanged: (v) => on(e.copyWith(fixedHeading: v)),
              ),
            if (e.heading != OrbitHeading.travel)
              NumField(
                label: 'Turn rate',
                unit: '°/s',
                value: e.yawRate,
                min: 0,
                max: 180,
                decimals: 0,
                help: '0 = firmware default (30 °/s)',
                onChanged: (v) => on(e.copyWith(yawRate: v)),
              ),
            _speed(e.speed, (v) => on(e.copyWith(speed: v, clearSpeed: v == null))),
            _radius(e.acceptRadius, (v) => on(e.copyWith(acceptRadius: v, clearRadius: v == null))),
          ],
        ),
        _PatternPayloadEditor(
          value: e.payload,
          payloads: plan.payloads,
          passes: false,
          onChanged: (v) => on(e.copyWith(payload: v)),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 12, color: context.alloy.ink2));
}
