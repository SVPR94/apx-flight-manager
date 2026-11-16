// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/components.dart';
import '../design/fields.dart';
import '../design/tokens.dart';
import '../fly/instruments.dart';
import '../state/appearance.dart';
import '../state/audio.dart';
import '../state/units.dart';
import '../state/view_items.dart';
import 'exit_dialog.dart';
import 'map_settings.dart';
import 'video_settings_section.dart';

/// App settings. Vehicle configuration lives in the Vehicle space.
/// Developer options (diagnostics, redundant sensor monitoring, MAVLink inspector)
/// are grouped here to keep primary pilot interfaces clean and distraction-free.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.initialSection = 0});
  final int initialSection;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late int _section = widget.initialSection;

  static const _sections = [
    (LucideIcons.slidersHorizontal, 'General'),
    (LucideIcons.ruler, 'Units & Formats'),
    (LucideIcons.volume2, 'Audio & Speech'),
    (LucideIcons.map, 'Maps'),
    (LucideIcons.video, 'Video'),
    (LucideIcons.eye, 'View Items'),
    (LucideIcons.info, 'About'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AlloyPalette>() ?? AlloyPalette.silver;
    // Material, not ColoredBox: list tiles and switches paint their ink on it.
    return Material(
      color: p.plate,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 230,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                ),
                for (final (i, (icon, label)) in _sections.indexed)
                  ListTile(
                    dense: true,
                    selected: _section == i,
                    selectedTileColor: p.accentBg,
                    selectedColor: p.accentInk,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Alloy.radiusControl)),
                    leading: Icon(icon, size: 18),
                    title: Text(label),
                    onTap: () => setState(() => _section = i),
                  ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: p.hairline),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: switch (_section) {
                    0 => const _General(),
                    1 => const _UnitsSection(),
                    2 => const _AudioSection(),
                    3 => const MapSettingsSection(),
                    4 => const VideoSettingsSection(),
                    5 => const ViewItemsSection(),
                    _ => const _About(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _General extends ConsumerWidget {
  const _General();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider);
    final p = context.alloy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Appearance',
          subtitle: 'Silver for daylight, Graphite for night and dim cabins.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<AlloyPalette>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: AlloyPalette.silver, label: Text('Silver · day')),
                ButtonSegment(value: AlloyPalette.graphite, label: Text('Graphite · night')),
              ],
              selected: {current},
              onSelectionChanged: (v) => ref.read(appearanceProvider.notifier).set(v.single),
            ),
          ),
        ),
        Text(
          'Drone setup (payloads, sprayer, navigation, battery, flight modes, parameters) is in the Vehicle space.',
          style: TextStyle(fontSize: 12, color: p.ink2),
        ),
      ],
    );
  }
}

class _UnitsSection extends ConsumerWidget {
  const _UnitsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitsProvider);
    final ctrl = ref.read(unitsProvider.notifier);

    final isMetric =
        (units.altitude == AltitudeUnit.meters &&
        units.speed == SpeedUnit.metersPerSecond &&
        units.distance == DistanceUnit.metric &&
        units.temperature == TemperatureUnit.celsius);
    final isImperial =
        (units.altitude == AltitudeUnit.feet &&
        units.speed == SpeedUnit.milesPerHour &&
        units.distance == DistanceUnit.imperial &&
        units.temperature == TemperatureUnit.fahrenheit);
    final isAviation =
        (units.altitude == AltitudeUnit.feet &&
        units.speed == SpeedUnit.knots &&
        units.distance == DistanceUnit.imperial &&
        units.temperature == TemperatureUnit.celsius);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'System Presets',
          subtitle: 'Quickly configure standard measurement conventions.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AlloyButton(
                icon: LucideIcons.globe,
                label: 'Metric (SI)',
                primary: isMetric,
                onPressed: ctrl.setPresetMetric,
              ),
              AlloyButton(
                icon: LucideIcons.flag,
                label: 'Imperial (US)',
                primary: isImperial,
                onPressed: ctrl.setPresetImperial,
              ),
              AlloyButton(
                icon: LucideIcons.plane,
                label: 'Aviation Standard',
                primary: isAviation,
                onPressed: ctrl.setPresetAviation,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Custom Units',
          subtitle: 'Fine-tune specific physical quantities to match your preference or regional standards.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _UnitSelectorTile<AltitudeUnit>(
                label: 'Altitude & Elevation',
                description: 'Used for AGL/MSL readouts, climb rates, and waypoint heights',
                icon: LucideIcons.mountain,
                value: units.altitude,
                items: const [(AltitudeUnit.meters, 'Meters (m)'), (AltitudeUnit.feet, 'Feet (ft)')],
                onChanged: ctrl.setAltitude,
              ),
              const Divider(height: 1),
              _UnitSelectorTile<SpeedUnit>(
                label: 'Ground & Air Speed',
                description: 'Used for HUD speedometer, mission cruise velocity, and wind display',
                icon: LucideIcons.gauge,
                value: units.speed,
                items: const [
                  (SpeedUnit.metersPerSecond, 'Meters per second (m/s)'),
                  (SpeedUnit.kilometersPerHour, 'Kilometers per hour (km/h)'),
                  (SpeedUnit.milesPerHour, 'Miles per hour (mph)'),
                  (SpeedUnit.knots, 'Knots (kt)'),
                ],
                onChanged: ctrl.setSpeed,
              ),
              const Divider(height: 1),
              _UnitSelectorTile<DistanceUnit>(
                label: 'Horizontal Distance',
                description: 'Used for distance to home, mission leg lengths, and geofence radii',
                icon: LucideIcons.route,
                value: units.distance,
                items: const [(DistanceUnit.metric, 'Metric (m, km)'), (DistanceUnit.imperial, 'Imperial (ft, mi)')],
                onChanged: ctrl.setDistance,
              ),
              const Divider(height: 1),
              _UnitSelectorTile<TemperatureUnit>(
                label: 'Temperature',
                description: 'Used for IMU thermal status and battery temperature',
                icon: LucideIcons.thermometer,
                value: units.temperature,
                items: const [
                  (TemperatureUnit.celsius, 'Celsius (°C)'),
                  (TemperatureUnit.fahrenheit, 'Fahrenheit (°F)'),
                ],
                onChanged: ctrl.setTemperature,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Sample Readouts',
          subtitle: 'How telemetry will appear in Fly View and the Cockpit HUD.',
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _PreviewReading(
                label: 'Altitude (AGL)',
                value: units.convertAltitude(45.0).toStringAsFixed(1),
                unit: units.altitude.symbol,
              ),
              _PreviewReading(
                label: 'Ground Speed',
                value: units.convertSpeed(12.5).toStringAsFixed(1),
                unit: units.speed.symbol,
              ),
              _PreviewReading(label: 'Distance to Home', value: units.formatDistance(320.0), unit: null),
              _PreviewReading(
                label: 'IMU Temp',
                value: units.convertTemperature(38.0).toStringAsFixed(1),
                unit: units.temperature.symbol,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewReading extends StatelessWidget {
  const _PreviewReading({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AlloyPalette>() ?? AlloyPalette.silver;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: p.ink2)),
        const SizedBox(height: 2),
        Reading(value, unit: unit, size: 16),
      ],
    );
  }
}

class _UnitSelectorTile<T> extends StatelessWidget {
  const _UnitSelectorTile({
    required this.label,
    required this.description,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String description;
  final IconData icon;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AlloyPalette>() ?? AlloyPalette.silver;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.ink2),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(description, style: TextStyle(fontSize: 11, color: p.ink2)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(Alloy.radiusControl),
            items: [
              for (final (val, text) in items)
                DropdownMenuItem(
                  value: val,
                  child: Text(text, style: const TextStyle(fontSize: 13)),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _AudioSection extends ConsumerWidget {
  const _AudioSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    final audio = ref.watch(audioSettingsProvider);
    final ctrl = ref.read(audioSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Voice Annunciations',
          subtitle: 'Spoken auditory callouts for pilot awareness during flight operations.',
          trailing: Switch(value: audio.enabled, onChanged: ctrl.setEnabled),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(audio.volume == 0 ? LucideIcons.volumeX : LucideIcons.volume2, size: 18, color: p.ink2),
                  const SizedBox(width: 10),
                  Text(
                    'Volume',
                    style: TextStyle(fontSize: 13, color: p.ink, fontWeight: FontWeight.w500),
                  ),
                  Expanded(
                    child: Slider(
                      value: audio.volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      onChanged: audio.enabled ? ctrl.setVolume : null,
                    ),
                  ),
                  SizedBox(width: 44, child: Text('${(audio.volume * 100).round()}%', style: AlloyText.mono(12))),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: AlloyButton(
                  icon: LucideIcons.volume2,
                  label: 'Test Voice Output',
                  onPressed: audio.enabled ? () => ref.read(audioAnnouncerProvider).testVoice() : null,
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Announced Events',
          subtitle: 'Select which telemetry and safety events trigger voice annunciations.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Flight mode changes', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  'e.g. "Mode LOITER", "Mode RTL", "Mode AUTO"',
                  style: TextStyle(fontSize: 11, color: p.ink2),
                ),
                value: audio.announceModes,
                onChanged: audio.enabled ? ctrl.toggleModes : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Arming & Disarming', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  'e.g. "Vehicle armed", "Vehicle disarmed"',
                  style: TextStyle(fontSize: 11, color: p.ink2),
                ),
                value: audio.announceArming,
                onChanged: audio.enabled ? ctrl.toggleArming : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Battery thresholds', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  'e.g. "Battery low", "Battery critical — land now"',
                  style: TextStyle(fontSize: 11, color: p.ink2),
                ),
                value: audio.announceBattery,
                onChanged: audio.enabled ? ctrl.toggleBattery : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mission milestones', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  'e.g. "Waypoint reached", "Mission complete"',
                  style: TextStyle(fontSize: 11, color: p.ink2),
                ),
                value: audio.announceMission,
                onChanged: audio.enabled ? ctrl.toggleMission : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Telemetry link state', style: TextStyle(fontSize: 13)),
                subtitle: Text('e.g. "Link lost", "Link restored"', style: TextStyle(fontSize: 11, color: p.ink2)),
                value: audio.announceLink,
                onChanged: audio.enabled ? ctrl.toggleLink : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _About extends ConsumerWidget {
  const _About();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.alloy;
    return SectionCard(
      title: 'APX Flight Manager 0.1.0',
      subtitle: 'Ground control station for the APX flight controller.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text('Map data and imagery belong to the providers credited on the map.', style: TextStyle(color: p.ink2)),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AlloyButton(
                label: 'Open‑source licences',
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'APX Flight Manager',
                  applicationVersion: '0.1.0',
                ),
              ),
              AlloyButton(
                icon: LucideIcons.power,
                label: 'Exit Application',
                onPressed: () => confirmAndExitApp(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ViewItemsSection extends ConsumerStatefulWidget {
  const ViewItemsSection({super.key});

  @override
  ConsumerState<ViewItemsSection> createState() => _ViewItemsSectionState();
}

class _ViewItemsSectionState extends ConsumerState<ViewItemsSection> {
  int _selectedVehicleType = MavType.quadrotor;
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(viewItemSettingsProvider);
    final ctrl = ref.read(viewItemSettingsProvider.notifier);
    final p = Theme.of(context).extension<AlloyPalette>() ?? AlloyPalette.silver;
    final currentCustomIcon = settings.customVehicleIcons[_selectedVehicleType];

    if (_pathController.text != (currentCustomIcon ?? '') && !_pathController.value.isComposingRangeValid) {
      _pathController.text = currentCustomIcon ?? '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'View Items',
          subtitle: 'Adjust display sizes for vehicle icons, flight plan paths, and breadcrumb trails.',
          trailing: AlloyButton(
            key: const Key('reset_view_items_defaults_button'),
            icon: LucideIcons.rotateCcw,
            label: 'Reset to Defaults',
            onPressed: ctrl.resetDefaults,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drone Icon Size
              Row(
                children: [
                  Icon(LucideIcons.navigation, size: 18, color: p.ink2),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 170,
                    child: Text(
                      'Drone Icon Size',
                      style: TextStyle(fontSize: 13, color: p.ink, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('drone_icon_size_slider'),
                      value: settings.droneIconSize.clamp(ViewItemSettings.minDroneIconSize, ViewItemSettings.maxDroneIconSize),
                      min: ViewItemSettings.minDroneIconSize,
                      max: ViewItemSettings.maxDroneIconSize,
                      divisions: 96,
                      label: '${settings.droneIconSize.round()} px',
                      onChanged: (v) => ctrl.setDroneIconSize(v.roundToDouble()),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text('${settings.droneIconSize.round()} px', style: AlloyText.mono(12)),
                  ),
                ],
              ),
              const Divider(height: 20),
              // Flight Plan Path Size
              Row(
                children: [
                  Icon(LucideIcons.route, size: 18, color: p.ink2),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 170,
                    child: Text(
                      'Flight Plan Path Size',
                      style: TextStyle(fontSize: 13, color: p.ink, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('path_size_slider'),
                      value: settings.pathSize.clamp(ViewItemSettings.minPathSize, ViewItemSettings.maxPathSize),
                      min: ViewItemSettings.minPathSize,
                      max: ViewItemSettings.maxPathSize,
                      divisions: 110,
                      label: '${settings.pathSize.toStringAsFixed(1)} px',
                      onChanged: (v) => ctrl.setPathSize(double.parse(v.toStringAsFixed(1))),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text('${settings.pathSize.toStringAsFixed(1)} px', style: AlloyText.mono(12)),
                  ),
                ],
              ),
              const Divider(height: 20),
              // Vehicle Trail Line Size
              Row(
                children: [
                  Icon(LucideIcons.activity, size: 18, color: p.ink2),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 170,
                    child: Text(
                      'Vehicle Trail Line Size',
                      style: TextStyle(fontSize: 13, color: p.ink, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('trail_size_slider'),
                      value: settings.trailSize.clamp(ViewItemSettings.minTrailSize, ViewItemSettings.maxTrailSize),
                      min: ViewItemSettings.minTrailSize,
                      max: ViewItemSettings.maxTrailSize,
                      divisions: 110,
                      label: '${settings.trailSize.toStringAsFixed(1)} px',
                      onChanged: (v) => ctrl.setTrailSize(double.parse(v.toStringAsFixed(1))),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text('${settings.trailSize.toStringAsFixed(1)} px', style: AlloyText.mono(12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Custom Vehicle Icons',
          subtitle: 'Customize the drone icon per vehicle type using transparent PNG top-head graphics.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Vehicle Type: ', style: TextStyle(fontSize: 13, color: p.ink, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    key: const Key('vehicle_type_dropdown'),
                    value: _selectedVehicleType,
                    items: defaultVehicleTypes
                        .map(
                          (info) => DropdownMenuItem<int>(
                            value: info.type,
                            child: Text(info.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedVehicleType = v;
                          _pathController.text = settings.customVehicleIcons[v] ?? '';
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: p.glass,
                      borderRadius: BorderRadius.circular(Alloy.radiusControl),
                      border: Border.all(color: p.hairline),
                    ),
                    alignment: Alignment.center,
                    child: VehicleGlyph(
                      vehicleType: _selectedVehicleType,
                      headingDeg: 0,
                      size: 56,
                      customIconPath: currentCustomIcon,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentCustomIcon != null ? 'Custom PNG Graphic Set' : 'Default Vector Glyph Active',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: currentCustomIcon != null ? AlloyPalette.accent : p.ink2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: const Key('custom_icon_path_field'),
                          controller: _pathController,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Enter path to transparent PNG...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Alloy.radiusControl)),
                          ),
                          onChanged: (v) {
                            final trimmed = v.trim();
                            if (trimmed.isNotEmpty) {
                              ctrl.setCustomIcon(_selectedVehicleType, trimmed);
                            } else {
                              ctrl.clearCustomIcon(_selectedVehicleType);
                            }
                          },
                          onSubmitted: (v) {
                            final trimmed = v.trim();
                            if (trimmed.isNotEmpty) {
                              ctrl.setCustomIcon(_selectedVehicleType, trimmed);
                            } else {
                              ctrl.clearCustomIcon(_selectedVehicleType);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AlloyButton(
                              icon: LucideIcons.upload,
                              label: 'Select PNG Icon...',
                              onPressed: () async {
                                try {
                                  final file = await openFile(
                                    acceptedTypeGroups: const [
                                      XTypeGroup(
                                        label: 'PNG Image',
                                        extensions: ['png'],
                                        uniformTypeIdentifiers: ['public.png'],
                                      ),
                                    ],
                                  );
                                  if (file != null) {
                                    ctrl.setCustomIcon(_selectedVehicleType, file.path);
                                    _pathController.text = file.path;
                                  }
                                } catch (_) {}
                              },
                            ),
                            if (currentCustomIcon != null)
                              AlloyButton(
                                icon: LucideIcons.trash2,
                                label: 'Clear Icon',
                                onPressed: () {
                                  ctrl.clearCustomIcon(_selectedVehicleType);
                                  _pathController.clear();
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
