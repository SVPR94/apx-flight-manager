// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_geo/apx_geo.dart';
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../connect/connect_form.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../map/layers_panel.dart';
import '../map/map_dialogs.dart';
import '../map/map_layers.dart';
import '../map/overlay_edit_layer.dart';
import '../map/path_arrows.dart';
import '../state/connection.dart';
import '../state/fence.dart';
import '../state/overlays.dart';
import '../state/storage.dart';
import '../state/trail.dart';
import '../state/view_items.dart';
import '../video/video_fullscreen.dart';
import '../video/video_layout.dart';
import '../video/video_manager.dart';
import '../video/video_pip.dart';
import '../video/video_settings.dart';
import '../video/video_widgets.dart';
import 'geofence_panel.dart';
import 'instruments.dart';
import 'motion.dart';
import 'panels.dart';
import 'status_rail.dart';

/// Map‑first cockpit: everything floats over the map on glass.
class FlyView extends ConsumerStatefulWidget {
  const FlyView({super.key});

  @override
  ConsumerState<FlyView> createState() => _FlyViewState();
}

class _FlyViewState extends ConsumerState<FlyView> with SingleTickerProviderStateMixin {
  final _map = MapController();
  bool _follow = true;
  bool _centred = false;

  /// Smoothed attitude/position, advanced every frame.
  late final _motion = FlightMotion(this)..addListener(_onMotion);
  LatLng? _guidedTarget;
  Alert? _local;
  bool _layersOpen = false;
  bool _fenceOpen = false;
  bool _draggingHandle = false;
  final _mapKey = GlobalKey();

  /// Keeps the live picture's element (and the map's, via [_mapKey]) when it
  /// moves between the main view and the floating window, so neither restarts.
  final _videoKey = GlobalKey();

  /// Image overlay whose corners are being dragged, and the corners so far.
  OverlayItem? _editing;
  List<LatLng>? _corners;

  void _report(CommandResult r) {
    if (r.accepted) return;
    setState(() => _local = Alert('cmd', AlertSeverity.warning, r.toString(), DateTime.now()));
  }

  void _say(String text, [AlertSeverity sev = AlertSeverity.info]) =>
      setState(() => _local = Alert('ui', sev, text, DateTime.now()));

  @override
  void initState() {
    super.initState();
    _motion.attach(ref.read(connectionProvider)?.session);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  /// Every frame the vehicle visibly moved: follow camera.
  void _onMotion() {
    if (!_motion.hasPosition) return;
    final here = LatLng(_motion.lat, _motion.lon);
    if (!_centred) {
      _centred = true;
      _map.move(here, 17);
    } else if (_follow) {
      _map.move(here, _map.camera.zoom);
    }
  }

  Future<void> _handleMapLocationAction(VehicleSession session, LatLng at) async {
    final s = session.telemetry.snapshot;
    final canFlyHere = s.customMode == 4 && s.armed && s.altRel >= 1;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.alloy.plate,
        title: Row(
          children: [
            const Icon(LucideIcons.mapPin, size: 18),
            const SizedBox(width: 8),
            Text(
              '${at.latitude.toStringAsFixed(5)}, ${at.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              leading: Icon(LucideIcons.send, color: canFlyHere ? context.alloy.accentInk : context.alloy.ink2),
              title: const Text('Fly here (Guided)'),
              subtitle: Text(
                canFlyHere ? 'Send vehicle directly to this position' : 'Requires armed & in-flight Guided mode',
              ),
              enabled: canFlyHere,
              onTap: () => Navigator.pop(context, 'fly'),
            ),
            const Divider(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(LucideIcons.house, color: Color(0xFF0B7C87)),
              title: const Text('Set Home Here'),
              subtitle: const Text('RTL and fail-safe return will fly to this location'),
              onTap: () => Navigator.pop(context, 'set_home_coord'),
            ),
            if (s.hasPosition)
              ListTile(
                dense: true,
                leading: Icon(LucideIcons.crosshair, color: context.alloy.ink),
                title: const Text('Set Home to Drone'),
                subtitle: Text('Set home to vehicle GPS (${s.lat.toStringAsFixed(5)}, ${s.lon.toStringAsFixed(5)})'),
                onTap: () => Navigator.pop(context, 'set_home_vehicle'),
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );

    if (action == null || !mounted) return;

    if (action == 'fly') {
      final alt = await _askAltitude(s.altRel.isNaN ? 10 : s.altRel);
      if (alt == null) return;
      await session.commands.guidedGoto(at.latitude, at.longitude, alt);
      setState(() => _guidedTarget = at);
    } else if (action == 'set_home_coord') {
      // A map point's ground height is unknown: keep home's altitude, not the drone's.
      await _setHomePosition(session, at.latitude, at.longitude, s.homeAltMsl);
    } else if (action == 'set_home_vehicle') {
      await _setHomeToVehicle(session);
    }
  }

  Future<void> _setHomePosition(VehicleSession session, double lat, double lon, [double? altMsl]) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.alloy.plate,
        title: const Text('Update Home Point?'),
        content: Text(
          'Set the vehicle home position to (${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)})?\n\n'
          'This updates the onboard RTL point. When Return-To-Launch triggers, the vehicle will return and land here.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update Home')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await session.commands.setHome(
        useCurrentPosition: false,
        lat: lat,
        lon: lon,
        altMsl: altMsl ?? double.nan,
      );
      // Move the marker only once the vehicle has taken it; HOME_POSITION confirms.
      if (res.accepted) session.telemetry.setManualHome(lat: lat, lon: lon, altMsl: altMsl);
      if (!mounted) return;
      if (res.accepted) {
        _say('Home position updated to selected coordinates');
        notify(context, 'Home position updated to ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}');
      } else {
        notify(context, 'Set home: ${res.message}');
      }
    } catch (e) {
      if (mounted) notify(context, 'Failed to update home: $e');
    }
  }

  Future<void> _setHomeToVehicle(VehicleSession session) async {
    final s = session.telemetry.snapshot;
    if (!s.hasPosition) {
      notify(context, 'No GPS position lock available');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.alloy.plate,
        title: const Text('Set Home to Drone Position?'),
        content: Text(
          'Set the onboard home position to current drone coordinates (${s.lat.toStringAsFixed(6)}, ${s.lon.toStringAsFixed(6)})?\n\n'
          'This updates the return target for RTL.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set Home')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // The point under the drone, at home's altitude: "use current position"
      // would put home in the air when pressed in flight.
      final (lat, lon) = (s.lat, s.lon);
      final res = await session.commands.setHome(useCurrentPosition: false, lat: lat, lon: lon, altMsl: s.homeAltMsl);
      if (res.accepted) session.telemetry.setManualHome(lat: lat, lon: lon, altMsl: s.homeAltMsl);
      if (!mounted) return;
      if (res.accepted) {
        _say('Home position set to drone location');
        notify(context, 'Home set to drone position (${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)})');
      } else {
        notify(context, 'Set home: ${res.message}');
      }
    } catch (e) {
      if (mounted) notify(context, 'Failed to set home: $e');
    }
  }

  Future<double?> _askAltitude(double current) {
    final c = TextEditingController(text: current.toStringAsFixed(0));
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.alloy.plate,
        title: const Text('Fly here'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Altitude above home (m)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(c.text)), child: const Text('Go')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This view rebuilds on connect/disconnect and its own state only; the
    // parts that follow telemetry rebuild themselves (see _onMotion and the
    // Consumers below), so the map isn't rebuilt at telemetry rate.
    ref.listen(connectionProvider, (_, c) {
      _motion.attach(c?.session);
      if (c == null) {
        ref.read(flightTrailProvider.notifier).clear();
        _centred = false;
        setState(() => _guidedTarget = null);
      }
    });
    final conn = ref.watch(connectionProvider);
    final session = conn?.session;

    final toolsTop = conn == null ? 16.0 : 132.0;
    final hudBottom = (conn != null && session?.state.value != SessionState.waiting) ? 180.0 : 16.0;
    final videoOn = ref.watch(videoSettingsProvider.select((s) => s.enabled));
    final layout = ref.watch(videoLayoutProvider);
    final videoMain = videoOn && layout.primary == FlyPrimary.video;
    final pip = videoOn && layout.pipVisible;
    final mapView = _mapLayer(session);
    // The main view's REC indicator lives with the status rail (visible in
    // every layout, never under the floating window).
    Widget videoView({required bool compact}) => KeyedSubtree(
      key: _videoKey,
      child: VideoSurface(compact: compact, recordingBadge: compact),
    );
    final layers = _layersOpen && (!videoMain || pip)
        ? LayersPanel(
            camera: () => _map.camera,
            onClose: () => setState(() => _layersOpen = false),
            onZoomTo: _zoomTo,
            onEditCorners: _startEditing,
          )
        : null;
    final fencePanel = _fenceOpen && (!videoMain || pip)
        ? GeofencePanel(onClose: () => setState(() => _fenceOpen = false))
        : null;
    // Map tools, layers, and geofence panels share the right edge with the action
    // panel, so they live in one column: the tools and panels above, the
    // action panel below.
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              ?layers,
              ?fencePanel,
              Flexible(
                child: SingleChildScrollView(
                  child: _flyTools(session, videoOn: videoOn),
                ),
              ),
            ],
          ),
        ),
        if (conn != null) ...[
          const SizedBox(height: 16),
          Consumer(
            builder: (context, ref, _) {
              ref.watch(frameTickProvider);
              return ActionStack(session: conn.session, onResult: _report);
            },
          ),
        ],
      ],
    );
    final layoutCtl = ref.read(videoLayoutProvider.notifier);
    return Stack(
      children: [
        // "Video only": the map stays mounted (hidden) so its camera, layers
        // and tile cache survive until it is shown again.
        if (videoMain && !pip) Positioned.fill(child: Visibility(visible: false, maintainState: true, child: mapView)),
        Positioned.fill(child: videoMain ? videoView(compact: false) : mapView),
        if (conn == null && videoOn)
          const Positioned(top: 16, left: 0, right: 0, child: Center(child: RecordingBadge())),
        if (conn == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: const Glass(padding: EdgeInsets.all(20), child: ConnectForm()),
              ),
            ),
          )
        else ...[
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              spacing: 10,
              children: [
                Center(
                  child: StatusRail(connection: conn, onResult: _report),
                ),
                NotificationCapsule(alerts: conn.alerts, local: _local),
                if (videoOn) const RecordingBadge(),
              ],
            ),
          ),
          // Instruments along the bottom left, clear of the right column.
          Positioned(
            left: 16,
            right: 16 + 300 + 16,
            bottom: 16,
            child: Consumer(
              builder: (context, ref, _) {
                ref.watch(frameTickProvider);
                final s = session!.telemetry.snapshot;
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    if (session.state.value != SessionState.waiting) CockpitCluster(s: s, motion: _motion),
                    if (s.customMode == 3 && s.missionTotal > 0) MissionProgress(s: s, mission: session.vehicleMission),
                  ],
                );
              },
            ),
          ),
        ],
        Positioned(top: toolsTop, right: 16, bottom: 16, child: right),
        // Geofence drawing/moving banner. The Positioned must stay the Stack's direct
        // child: a bare zero-size child would be non-positioned, and the Stack
        // would size itself to it (0×0) whenever the connect form isn't shown.
        Positioned(
          left: 16,
          right: 80,
          top: toolsTop,
          child: Consumer(
            builder: (context, ref, _) {
              final fence = ref.watch(fenceProvider);
              if (!fence.isDrawing && !fence.isMoving) return const SizedBox.shrink();
              return Center(
                child: Glass(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  radius: Alloy.radiusCapsule,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 10,
                    children: [
                      Icon(
                        fence.isMoving ? LucideIcons.move : LucideIcons.penTool,
                        size: 18,
                        color: const Color(0xFFFF9500),
                      ),
                      Flexible(
                        child: Text(
                          fence.isMoving
                              ? 'Moving Geofence: Drag the central move handle on the map to relocate.'
                              : (fence.points.isEmpty
                                    ? 'Tap map to place geofence boundary vertices.'
                                    : 'Drawing Geofence: ${fence.points.length} vertices. Tap to add, drag vertices or center.'),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (fence.isMoving)
                        AlloyButton(
                          label: 'Done',
                          icon: LucideIcons.check,
                          primary: true,
                          onPressed: () => ref.read(fenceProvider.notifier).finishMoving(),
                        )
                      else ...[
                        if (fence.points.isNotEmpty)
                          AlloyButton(
                            label: 'Undo',
                            icon: LucideIcons.undo,
                            onPressed: () => ref.read(fenceProvider.notifier).undoPoint(),
                          ),
                        AlloyButton(
                          label: 'Done',
                          icon: LucideIcons.check,
                          onPressed: fence.hasValidPolygon
                              ? () {
                                  ref.read(fenceProvider.notifier).finishDrawing();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Fence polygon defined (${fence.points.length} vertices)')),
                                  );
                                }
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Corner editing: under the status rail, where the bottom panels can't cover it.
        if (_editing != null)
          Positioned(
            left: 16,
            right: 80,
            top: toolsTop,
            child: Center(child: _editBar()),
          ),
        // The floating PiP window floats on top of the entire stack so it NEVER goes
        // behind the HUD (CockpitCluster), status rail, or any tool/action panels.
        if (pip)
          PipWindow(
            layout: layout,
            insets: EdgeInsets.fromLTRB(16, toolsTop, 16 + Alloy.touch + 12, hudBottom),
            label: videoMain ? 'Map' : 'Video',
            onSwap: layoutCtl.swap,
            onHide: () => layoutCtl.setPipVisible(false),
            onCorner: layoutCtl.setCorner,
            onWidth: layoutCtl.setWidth,
            onFullscreen: videoMain ? null : () => openVideoFullscreen(context),
            actions: [if (!videoMain) const _PipRecordButton()],
            // The map in the window is a view only: a tap swaps it back.
            child: videoMain ? IgnorePointer(child: mapView) : videoView(compact: true),
          ),
      ],
    );
  }

  Widget _flyTools(VehicleSession? session, {required bool videoOn}) {
    final p = context.alloy;
    final layout = ref.watch(videoLayoutProvider);
    final layoutCtl = ref.read(videoLayoutProvider.notifier);

    return Glass(
      padding: EdgeInsets.zero,
      radius: 14,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── View Switching Header (Consistent Fixed Positions at TOP) ──
          if (videoOn) ...[
            GlassIconButton(
              icon: LucideIcons.map,
              tooltip: 'Show the map',
              active: layout.mode == FlyLayoutMode.mapOnly,
              onPressed: () => layoutCtl.setMode(FlyLayoutMode.mapOnly),
            ),
            GlassIconButton(
              icon: LucideIcons.pictureInPicture,
              tooltip: layout.pipVisible
                  ? (layout.primary == FlyPrimary.map ? 'Map + Video (Tap to swap)' : 'Video + Map (Tap to swap)')
                  : 'Map + Video',
              active: layout.pipVisible,
              onPressed: () {
                if (!layout.pipVisible) {
                  layoutCtl.setMode(FlyLayoutMode.mapWithVideo);
                } else {
                  layoutCtl.swap();
                }
              },
            ),
            _VideoLayoutButton(active: layout.mode == FlyLayoutMode.videoOnly),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              height: 1,
              color: p.hairline,
            ),
          ],

          // ── Map Navigation Tools (Consistent Fixed Positions) ──
          GlassIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Zoom in',
            onPressed: () => _map.move(_map.camera.center, _map.camera.zoom + 1),
          ),
          GlassIconButton(
            icon: LucideIcons.minus,
            tooltip: 'Zoom out',
            onPressed: () => _map.move(_map.camera.center, _map.camera.zoom - 1),
          ),
          GlassIconButton(
            icon: LucideIcons.layers,
            tooltip: 'Map layers',
            active: _layersOpen,
            onPressed: () => setState(() {
              _layersOpen = !_layersOpen;
              if (_layersOpen) _fenceOpen = false;
            }),
          ),
          Consumer(
            builder: (context, ref, _) {
              final fence = ref.watch(fenceProvider);
              final breached = ref.watch(fenceBreachProvider) != null;
              return GlassIconButton(
                icon: breached
                    ? LucideIcons.triangleAlert
                    : fence.enabled
                    ? LucideIcons.shieldCheck
                    : LucideIcons.shieldAlert,
                tooltip: fence.enabled ? 'Safety Geofence (Active)' : 'Safety Geofence',
                active: _fenceOpen || fence.isDrawing,
                onPressed: () => setState(() {
                  _fenceOpen = !_fenceOpen;
                  if (_fenceOpen) _layersOpen = false;
                }),
              );
            },
          ),
          GlassIconButton(
            icon: LucideIcons.locateFixed,
            tooltip: _follow ? 'Following the vehicle' : 'Follow the vehicle',
            active: _follow,
            onPressed: () => setState(() => _follow = !_follow),
          ),
          if (session != null)
            GlassIconButton(
              icon: LucideIcons.house,
              tooltip: 'Set Home to drone position',
              onPressed: () => _setHomeToVehicle(session),
            ),

          // ── Video Controls (Consistent Fixed Positions at Bottom) ──
          if (videoOn) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              height: 1,
              color: p.hairline,
            ),
            Consumer(
              builder: (context, ref, _) {
                final s = ref.watch(videoManagerProvider);
                final mgr = ref.read(videoManagerProvider.notifier);
                final rec = s.isRecording;
                final canRec = rec || s.status == VideoStatus.playing;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: rec ? 'Stop recording' : (canRec ? 'Record' : 'Record (needs live video)'),
                      onPressed: canRec ? mgr.toggleRecording : null,
                      constraints: const BoxConstraints.tightFor(width: Alloy.touch, height: Alloy.touch),
                      icon: rec
                          ? const Icon(LucideIcons.squareStop, size: 19, color: Color(0xFFFF3B30))
                          : Icon(LucideIcons.circleDot, size: 19, color: canRec ? const Color(0xFFE5483E) : null),
                    ),
                    GlassIconButton(
                      icon: LucideIcons.camera,
                      tooltip: 'Snapshot',
                      onPressed: s.hasPicture ? mgr.takeSnapshot : null,
                    ),
                    GlassIconButton(
                      icon: LucideIcons.maximize,
                      tooltip: 'Full‑screen video',
                      onPressed: () => openVideoFullscreen(context),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _mapLayer(VehicleSession? session) {
    final p = context.alloy;
    return FlutterMap(
      key: _mapKey,
      mapController: _map,
      options: MapOptions(
        initialCenter: _savedView.$1,
        initialZoom: _savedView.$2,
        maxZoom: 22,
        backgroundColor: p.canvas,
        interactionOptions: InteractionOptions(
          flags: _draggingHandle ? InteractiveFlag.doubleTapZoom : InteractiveFlag.all,
        ),
        onTap: (_, at) {
          if (ref.read(fenceProvider).isDrawing) {
            ref.read(fenceProvider.notifier).addPoint(at);
          }
        },
        onLongPress: session == null ? null : (_, at) => _handleMapLocationAction(session, at),
        onSecondaryTap: session == null ? null : (_, at) => _handleMapLocationAction(session, at),
        onPositionChanged: (camera, gesture) {
          if (gesture && _follow) setState(() => _follow = false);
          _rememberView(camera);
        },
      ),
      children: [
        ...mapBaseLayers(ref),
        const _MissionRoute(),
        const _MissionArrows(),
        Consumer(
          builder: (context, ref, _) {
            final trail = ref.watch(flightTrailProvider).points;
            if (trail.length < 2) return const SizedBox.shrink();
            final trailSize = ref.watch(viewItemSettingsProvider).trailSize;
            return IgnorePointer(
              child: PolylineLayer(
                polylines: [
                  // High-contrast dark outline casing underneath
                  Polyline(
                    points: trail,
                    strokeWidth: trailSize + 2.2,
                    color: Colors.black.withValues(alpha: 0.65),
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  // Vivid, high-visibility neon electric cyan trail
                  Polyline(
                    points: trail,
                    strokeWidth: trailSize,
                    color: const Color(0xFF00E5FF),
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              ),
            );
          },
        ),
        const _MissionPins(),
        _GeofenceMapLayer(
          mapKey: _mapKey,
          map: _map,
          onDragStart: () => setState(() => _draggingHandle = true),
          onDragEnd: () => setState(() => _draggingHandle = false),
        ),
        if (_guidedTarget != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _guidedTarget!,
                width: 36,
                height: 36,
                child: const Icon(LucideIcons.crosshair, color: AlloyPalette.accent, size: 30),
              ),
            ],
          ),
        // The vehicle moves every frame on its own; nothing else rebuilds.
        if (session != null)
          Consumer(
            builder: (context, ref, _) {
              final viewSettings = ref.watch(viewItemSettingsProvider);
              final droneSize = viewSettings.droneIconSize;
              final vehicleType = session.telemetry.snapshot.vehicleType;
              return ListenableBuilder(
                listenable: _motion,
                builder: (context, _) => !_motion.hasPosition
                    ? const SizedBox.shrink()
                    : MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(_motion.lat, _motion.lon),
                            width: droneSize,
                            height: droneSize,
                            child: IgnorePointer(
                              child: VehicleGlyph(
                                arms: VehicleGlyph.armsOf(vehicleType),
                                headingDeg: _motion.heading,
                                size: droneSize,
                                vehicleType: vehicleType,
                                customIconPath: viewSettings.customVehicleIcons[vehicleType],
                              ),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
        if (_corners != null)
          OverlayEditLayer(
            corners: _corners!,
            mapKey: _mapKey,
            onChanged: (c) => setState(() => _corners = c),
            onDragStart: () => setState(() => _draggingHandle = true),
            onDragEnd: () => setState(() => _draggingHandle = false),
          ),
        mapAttribution(ref),
      ],
    );
  }

  /// Where the map was last left (the app reopens there), or a world view.
  late final (LatLng, double) _savedView = () {
    final v = ref.read(settingsStoreProvider).get<Map>('mapView');
    if (v == null) return (const LatLng(20, 0), 3.0);
    return (LatLng((v['lat'] as num).toDouble(), (v['lon'] as num).toDouble()), (v['zoom'] as num).toDouble());
  }();

  void _rememberView(MapCamera c) {
    if (c.zoom < 2) return; // not worth restoring
    ref.read(settingsStoreProvider).set('mapView', {
      'lat': double.parse(c.center.latitude.toStringAsFixed(6)),
      'lon': double.parse(c.center.longitude.toStringAsFixed(6)),
      'zoom': double.parse(c.zoom.toStringAsFixed(2)),
    });
  }

  void _zoomTo(GeoBounds b) {
    setState(() => _follow = false);
    _map.fitCamera(CameraFit.bounds(bounds: toLatLngBounds(b), padding: const EdgeInsets.all(60), maxZoom: 20));
  }

  void _startEditing(OverlayItem o) {
    final p = o.spec.placement;
    if (p == null) return;
    // Corners don't depend on pixel size for these placements; a world file
    // needs the real size, which the stored bounds stand in for.
    final corners = switch (p) {
      CornerPlacement(:final points) => points,
      CentrePlacement() => p.corners(1, 1),
      WorldFilePlacement() => [
        GeoPoint(o.spec.bounds!.north, o.spec.bounds!.west),
        GeoPoint(o.spec.bounds!.north, o.spec.bounds!.east),
        GeoPoint(o.spec.bounds!.south, o.spec.bounds!.east),
        GeoPoint(o.spec.bounds!.south, o.spec.bounds!.west),
      ],
    };
    setState(() {
      _layersOpen = false;
      _editing = o;
      _corners = [for (final c in corners) toLatLng(c)];
    });
    if (o.spec.bounds != null) _zoomTo(o.spec.bounds!);
  }

  Future<void> _finishEditing({required bool apply}) async {
    final o = _editing, c = _corners;
    setState(() {
      _editing = null;
      _corners = null;
    });
    if (!apply || o == null || c == null) return;
    try {
      await ref
          .read(overlaysProvider.notifier)
          .updatePlacement(o.spec.id, CornerPlacement([for (final p in c) toGeo(p)]));
    } catch (e) {
      if (mounted) notify(context, 'Could not place the image: $e');
    }
  }

  Widget _editBar() => Glass(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    radius: Alloy.radiusCapsule,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        Icon(LucideIcons.move, size: 18, color: context.alloy.ink2),
        Flexible(
          child: Text(
            'Fit "${_editing!.spec.name}": drag corners, sides, the centre to move, or the round grip to rotate.',
          ),
        ),
        AlloyButton(label: 'Cancel', onPressed: () => _finishEditing(apply: false)),
        AlloyButton(label: 'Apply', primary: true, onPressed: () => _finishEditing(apply: true)),
      ],
    ),
  );
}

/// What the mission layers draw from; compared by value so they rebuild
/// only when the mission, home or current item changes, not every tick.
final _missionViewProvider = Provider<(List<WireMissionItem>?, double?, double?, int)?>((ref) {
  final session = ref.watch(connectionProvider)?.session;
  if (session == null) return null;
  ref.watch(frameTickProvider);
  final s = session.telemetry.snapshot;
  return (
    session.vehicleMission,
    s.homeLat.isNaN ? null : s.homeLat,
    s.homeLon.isNaN ? null : s.homeLon,
    s.missionCurrent,
  );
});

(List<(int, double, double, int)>, LatLng?) _missionGeometry((List<WireMissionItem>?, double?, double?, int)? v) {
  if (v == null) return (const [], null);
  final (mission, hLat, hLon, _) = v;
  final home = hLat == null ? null : LatLng(hLat, hLon!);
  final pts = mission == null
      ? const <(int, double, double, int)>[]
      : missionPoints(mission, hLat ?? double.nan, hLon ?? double.nan);
  return (pts, home);
}

class _MissionRoute extends ConsumerWidget {
  const _MissionRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (pts, home) = _missionGeometry(ref.watch(_missionViewProvider));
    final route = [if (home != null && pts.isNotEmpty) home, for (final (_, la, lo, _) in pts) LatLng(la, lo)];
    if (route.length < 2) return const SizedBox.shrink();
    final pathSize = ref.watch(viewItemSettingsProvider).pathSize;
    final casingWidth = pathSize + 2.5;
    final glowWidth = pathSize * (11.0 / 4.5);
    return IgnorePointer(
      child: PolylineLayer(
        polylines: [
          // High-contrast dark casing underneath for unmistakable visibility on any terrain/satellite map
          Polyline(
            points: route,
            strokeWidth: casingWidth,
            color: Colors.black.withValues(alpha: 0.65),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
          // Soft outer glow in bright safety orange
          Polyline(
            points: route,
            strokeWidth: glowWidth,
            color: const Color(0xFFFF9500).withValues(alpha: 0.30),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
          // Vivid high-visibility safety orange core mission line
          Polyline(
            points: route,
            strokeWidth: pathSize,
            color: const Color(0xFFFF9500),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        ],
      ),
    );
  }
}

class _MissionArrows extends ConsumerWidget {
  const _MissionArrows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (pts, home) = _missionGeometry(ref.watch(_missionViewProvider));
    final route = [if (home != null && pts.isNotEmpty) home, for (final (_, la, lo, _) in pts) LatLng(la, lo)];
    if (route.length < 2) return const SizedBox.shrink();
    return IgnorePointer(
      child: FlightPathArrowsLayer(
        runs: [(route, const Color(0xFFFF9500))],
      ),
    );
  }
}

class _MissionPins extends ConsumerWidget {
  const _MissionPins();

  static Widget _pin(Widget child, {bool filled = false}) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? AlloyPalette.accent : Colors.white,
      border: Border.all(color: AlloyPalette.accent, width: 2.5),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(_missionViewProvider);
    final (pts, home) = _missionGeometry(v);
    final current = v?.$4;
    if (home == null && pts.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(
      markers: [
        if (home != null)
          Marker(
            point: home,
            width: 32,
            height: 32,
            child: Tooltip(
              message: 'Home Point: ${home.latitude.toStringAsFixed(6)}, ${home.longitude.toStringAsFixed(6)}',
              child: _pin(const Icon(LucideIcons.house, size: 16, color: Color(0xFF0B7C87))),
            ),
          ),
        for (final (seq, la, lo, cmd) in pts)
          if (cmd != MavCmd.navReturnToLaunch)
            Marker(
              point: LatLng(la, lo),
              width: 28,
              height: 28,
              child: _pin(
                Text(
                  '$seq',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: seq == current ? Colors.white : const Color(0xFF0B7C87),
                  ),
                ),
                filled: seq == current,
              ),
            ),
      ],
    );
  }
}

/// Renders the safety geofence highlighted polygon and draggable vertex handles.
class GeofenceMapLayer extends ConsumerStatefulWidget {
  const GeofenceMapLayer({
    super.key,
    required this.mapKey,
    required this.map,
    this.onDragStart,
    this.onDragEnd,
  });

  final GlobalKey mapKey;
  final MapController map;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  ConsumerState<GeofenceMapLayer> createState() => _GeofenceMapLayerState();
}

typedef _GeofenceMapLayer = GeofenceMapLayer;

class _GeofenceMapLayerState extends ConsumerState<GeofenceMapLayer> {
  int? _activePointer;
  int? _activeVertex;
  bool _isDraggingMove = false;
  Offset? _lastMovePos;

  @override
  void dispose() {
    if (_activePointer != null) {
      widget.onDragEnd?.call();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fence = ref.watch(fenceProvider);
    final breached = ref.watch(fenceBreachProvider) != null;
    if (fence.points.isEmpty) return const SizedBox.shrink();

    final hasPoly = fence.points.length >= 3;
    // Highlight color: Electric safety amber/orange or red warning if breached
    const fenceColor = Color(0xFFFF9500);
    const breachColor = Color(0xFFFF3B30);
    final activeColor = breached ? breachColor : fenceColor;

    return Stack(
      children: [
        if (hasPoly)
          IgnorePointer(
            child: PolygonLayer(
              polygons: [
                Polygon(
                  points: fence.points,
                  color: activeColor.withValues(alpha: breached ? 0.35 : 0.18),
                  borderColor: activeColor,
                  borderStrokeWidth: 3.0,
                  pattern: StrokePattern.dashed(segments: const [10, 6]),
                ),
              ],
            ),
          )
        else
          IgnorePointer(
            child: PolylineLayer(
              polylines: [
                Polyline(
                  points: fence.points,
                  color: activeColor,
                  strokeWidth: 3.0,
                  pattern: StrokePattern.dashed(segments: const [8, 5]),
                ),
              ],
            ),
          ),
        // Draw vertex markers when in drawing mode
        if (fence.isDrawing)
          MarkerLayer(
            markers: [
              for (final (i, pt) in fence.points.indexed)
                Marker(
                  key: ValueKey('fence_vertex_$i'),
                  point: pt,
                  width: 32,
                  height: 32,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        if (e.buttons != kPrimaryButton && e.buttons != 0) return;
                        if (_activePointer != null) return;
                        _activePointer = e.pointer;
                        _activeVertex = i;
                        widget.onDragStart?.call();
                      },
                      onPointerMove: (e) {
                        if (e.pointer != _activePointer || _activeVertex != i) return;
                        final box = widget.mapKey.currentContext?.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final newPt = widget.map.camera.screenOffsetToLatLng(box.globalToLocal(e.position));
                        ref.read(fenceProvider.notifier).updatePoint(i, newPt);
                      },
                      onPointerUp: (e) {
                        if (e.pointer == _activePointer || _activeVertex == i) {
                          _activePointer = null;
                          _activeVertex = null;
                          widget.onDragEnd?.call();
                        }
                      },
                      onPointerCancel: (e) {
                        if (e.pointer == _activePointer || _activeVertex == i) {
                          _activePointer = null;
                          _activeVertex = null;
                          widget.onDragEnd?.call();
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: activeColor,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [BoxShadow(color: Color(0x60000000), blurRadius: 4)],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        // Central Move Handle: allows dragging the entire fence across the map
        if (fence.center != null && (fence.isMoving || fence.isDrawing))
          MarkerLayer(
            markers: [
              Marker(
                key: const ValueKey('fence_move_handle'),
                point: fence.center!,
                width: 44,
                height: 44,
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      if (e.buttons != kPrimaryButton && e.buttons != 0) return;
                      if (_activePointer != null) return;
                      _activePointer = e.pointer;
                      _isDraggingMove = true;
                      _lastMovePos = e.position;
                      widget.onDragStart?.call();
                    },
                    onPointerMove: (e) {
                      if (e.pointer != _activePointer || !_isDraggingMove || _lastMovePos == null) return;
                      final box = widget.mapKey.currentContext?.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final local = box.globalToLocal(e.position);
                      final prevLocal = box.globalToLocal(_lastMovePos!);
                      final currentPt = widget.map.camera.screenOffsetToLatLng(local);
                      final prevPt = widget.map.camera.screenOffsetToLatLng(prevLocal);
                      final dLat = currentPt.latitude - prevPt.latitude;
                      final dLon = currentPt.longitude - prevPt.longitude;
                      _lastMovePos = e.position;
                      ref.read(fenceProvider.notifier).translate(dLat, dLon);
                    },
                    onPointerUp: (e) {
                      if (e.pointer == _activePointer || _isDraggingMove) {
                        _activePointer = null;
                        _isDraggingMove = false;
                        _lastMovePos = null;
                        widget.onDragEnd?.call();
                      }
                    },
                    onPointerCancel: (e) {
                      if (e.pointer == _activePointer || _isDraggingMove) {
                        _activePointer = null;
                        _isDraggingMove = false;
                        _lastMovePos = null;
                        widget.onDragEnd?.call();
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: activeColor, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x60000000), blurRadius: 6, offset: Offset(0, 2))],
                      ),
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.move, size: 22, color: activeColor),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Video menu in the map tools: choose map/video arrangement, full screen,
/// record. Shows a red dot while recording.
class _VideoLayoutButton extends ConsumerWidget {
  const _VideoLayoutButton({this.active});
  final bool? active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(videoLayoutProvider);
    final s = ref.watch(videoManagerProvider);
    final p = context.alloy;
    final isSelected = active ?? (layout.mode == FlyLayoutMode.videoOnly || layout.primary == FlyPrimary.video);
    return PopupMenuButton<Object>(
      tooltip: 'Video',
      color: p.plate,
      position: PopupMenuPosition.under,
      onSelected: (v) {
        final mgr = ref.read(videoManagerProvider.notifier);
        switch (v) {
          case FlyLayoutMode m:
            ref.read(videoLayoutProvider.notifier).setMode(m);
          case 'fullscreen':
            openVideoFullscreen(context);
          case 'record':
            mgr.toggleRecording();
          case 'snapshot':
            mgr.takeSnapshot();
          case 'start':
            mgr.connect();
          case 'stop':
            mgr.disconnect();
        }
      },
      itemBuilder: (_) => [
        for (final m in FlyLayoutMode.values)
          CheckedPopupMenuItem<Object>(value: m, checked: layout.mode == m, child: Text(m.label)),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: 'fullscreen',
          child: ListTile(dense: true, leading: Icon(LucideIcons.maximize, size: 18), title: Text('Full‑screen video')),
        ),
        PopupMenuItem<Object>(
          value: 'record',
          enabled: s.isRecording || s.status == VideoStatus.playing,
          child: ListTile(
            dense: true,
            leading: Icon(
              s.isRecording ? LucideIcons.squareStop : LucideIcons.circleDot,
              size: 18,
              color: const Color(0xFFE5483E),
            ),
            title: Text(s.isRecording ? 'Stop recording' : 'Record'),
          ),
        ),
        PopupMenuItem<Object>(
          value: 'snapshot',
          enabled: s.hasPicture,
          child: const ListTile(dense: true, leading: Icon(LucideIcons.camera, size: 18), title: Text('Snapshot')),
        ),
        if (s.isActive)
          const PopupMenuItem<Object>(
            value: 'stop',
            child: ListTile(dense: true, leading: Icon(LucideIcons.squareStop, size: 18), title: Text('Stop video')),
          )
        else if (s.status != VideoStatus.unavailable)
          const PopupMenuItem<Object>(
            value: 'start',
            child: ListTile(dense: true, leading: Icon(LucideIcons.play, size: 18), title: Text('Start video')),
          ),
      ],
      child: SizedBox(
        width: Alloy.touch,
        height: Alloy.touch,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(LucideIcons.video, size: 19, color: isSelected ? p.accentInk : p.ink),
            if (s.isRecording)
              Positioned(
                top: 9,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Record/stop in the video window's header.
class _PipRecordButton extends ConsumerWidget {
  const _PipRecordButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (rec, playing) = ref.watch(
      videoManagerProvider.select((s) => (s.isRecording, s.status == VideoStatus.playing)),
    );
    return IconButton(
      tooltip: rec ? 'Stop recording' : 'Record',
      onPressed: rec || playing ? ref.read(videoManagerProvider.notifier).toggleRecording : null,
      iconSize: 16,
      padding: EdgeInsets.zero,
      color: const Color(0xFFFF453A),
      disabledColor: Colors.white38,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: Icon(rec ? LucideIcons.squareStop : LucideIcons.circleDot),
    );
  }
}
