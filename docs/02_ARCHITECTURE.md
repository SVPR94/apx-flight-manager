# APX Flight Manager — Architecture

Status: **approved 2026‑11‑03**, with these decisions:
- Platforms: **Windows and Linux first, then Android**; macOS optional (untested). Development on Ubuntu.
- Maps: multiple providers, **OSM by default**, per‑provider API keys in Settings (Google, Baidu, …), and a **local tile server** in the app (APX Flight Manager‑style) that serves cached, offline and imported imagery.
- Firmware: the bugs in §13 are being fixed in APX by the firmware owner. The GCS works around each one meanwhile, marked `TODO(APX-FW-n)` (n = §13 item) so it can be removed later. Companion documents:
[01_APX_CAPABILITY_MATRIX.md](01_APX_CAPABILITY_MATRIX.md) (what the firmware can do) and
[03_UI_CONCEPT.md](03_UI_CONCEPT.md) (how it looks and behaves).

## 1. Principles

1. **Firmware is the contract.** Every feature traces to a row in the capability
   matrix. The app carries an explicit `FirmwareProfile` per APX version; the UI asks
   the profile, never assumes. When firmware grows (e.g. param persistence), only the
   profile changes.
2. **Protocol core is pure Dart.** Codec, links, vehicle services, mission logic,
   geo and logs run under `dart test` with no Flutter, and are integration‑tested
   against the real APX SITL binary.
3. **UI is a thin composition layer.** Widgets read immutable snapshots and call
   services. No protocol logic in widgets.
4. **One map renderer, many tile sources.** Overlays and mission editing are written
   once and behave identically over Google, OSM or offline tiles.
5. **No dead UI.** Anything the firmware cannot do is absent, not disabled‑with‑a‑tooltip.
   Where the firmware has a known gap that the GCS can work around honestly (e.g. no
   param persistence → GCS re‑applies a saved profile), the workaround is labelled.
6. **No code from Standard GCS (GPLv3) or APX Flight Manager.** Both were studied for
   behaviour only; all code here is written fresh. MAVLink message definitions (MIT)
   are the only external protocol input.

## 2. Layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│  apps/flight_manager  (Flutter)                                          │
│  ├─ design/      Alloy design system: tokens, glass surfaces, controls   │
│  ├─ features/    fly · plan · vehicle · logs · settings                  │
│  ├─ map/         map engine, base‑map providers, overlay layers          │
│  └─ platform/    serial adapters, file access, TTS, window               │
├──────────────────────────────────────────────────────────────────────────┤
│  packages/  (pure Dart, no Flutter)                                      │
│  apx_mission   APX command catalog · plan model · validator · patterns   │
│                · .apxplan / .plan / .waypoints I/O                        │
│  apx_vehicle   session · telemetry store · commands · params · mission   │
│                transfer · firmware profile · alerts engine               │
│  apx_link      Link API · UDP · TCP · Serial (via adapter) · Replay       │
│                · LinkManager · link statistics                           │
│  apx_mavlink   generated messages · frame codec · CRC · parser           │
│  apx_geo       geodesy · projections · Shapefile · GeoTIFF · image        │
│                placement · raster→tile pyramid                           │
│  apx_logs      tlog writer/reader/index · series extraction · CSV        │
├──────────────────────────────────────────────────────────────────────────┤
│  tool/   mavlink_gen (XML → Dart)  ·  param_meta_gen (APX C++ → JSON)    │
└──────────────────────────────────────────────────────────────────────────┘
```

Dependency direction is strictly downward. `apx_mission` depends on `apx_vehicle`
(parameter metadata for vehicle facts), `apx_geo` and `apx_mavlink`; `apx_vehicle`
depends on `apx_link` and `apx_mavlink`; nothing in `packages/` imports Flutter.

## 3. Repository layout

```
APX_Flight_Manager/
├─ pubspec.yaml                 Dart pub workspace root
├─ apps/flight_manager/         Flutter application
├─ packages/apx_mavlink/
├─ packages/apx_link/
├─ packages/apx_vehicle/
├─ packages/apx_mission/
├─ packages/apx_geo/           geodesy, providers, tile cache + server, overlays
├─ packages/apx_logs/
├─ tool/mavlink_gen/            reads common.xml, emits only the messages APX uses
├─ tool/param_meta_gen/         parses apx/modules/params/param_manager.cpp
├─ test_sitl/                   SITL harness: spawns apx_flight_controller + physics
└─ docs/
```

## 4. Communication stack

### 4.1 apx_mavlink
- Code generated from MAVLink `common.xml` (local copy in `apx/modules/mavlink`)
  for the ~40 messages APX sends or accepts (§3–5 of the matrix) plus MANUAL_CONTROL.
  Unknown message IDs are kept as raw frames so the inspector can still show them.
- MAVLink v2 framing, CRC‑16/MCRF4XX with CRC_EXTRA, zero‑trailing truncation and
  extension fields. No signing (APX has none).
- **One parser state per link** (the firmware had a real bug from sharing parser
  state across links; we don't repeat it).
- Golden tests: byte‑for‑byte agreement with pymavlink for every generated message.

### 4.2 apx_link
```dart
abstract interface class Link {
  LinkDescriptor get descriptor;          // kind, address, label
  Stream<Uint8List> get incoming;
  Future<void> send(Uint8List frame);
  ValueStream<LinkState> get state;       // idle, connecting, up, lost, closed
  LinkStatistics get stats;               // bytes/s, frames/s, seq‑gap loss, CRC errors
  Future<void> open();  Future<void> close();
}
```

| Link | Implementation | APX use |
|---|---|---|
| `UdpLink.listen(port)` | `RawDatagramSocket`; learns peer from first datagram | Local SITL (APX streams to 127.0.0.1:14550) |
| `UdpLink.target(host, port)` | sends heartbeats to `host:14551` so APX registers us | Remote SITL / companion over Wi‑Fi |
| `TcpLink(host, port)` | `Socket`, reconnect with backoff | APX TCP 5760–5763 |
| `SerialLink(port, baud)` | `SerialAdapter` interface; desktop → `flutter_libserialport`, Android → `usb_serial` | Zephyr USB CDC; future UART radio |
| `ReplayLink(tlog)` | paced from tlog timestamps, 0.25×–16×, seek | Log replay through the same UI |

`LinkManager` owns links, auto‑connect profiles (UDP 14550 listen on by default;
"SITL" quick connect = TCP 127.0.0.1:5760), serial hot‑plug scanning (probe for a
valid MAVLink frame at the remembered baud, then 115200, 57600), and link‑loss
detection (no HEARTBEAT from the vehicle for 3.5 s). iOS gets UDP/TCP only (no
serial access); web is not a target (no raw sockets).

### 4.3 apx_vehicle
- **VehicleSession** per (sysid, compid). Starts on the first HEARTBEAT, requests
  AUTOPILOT_VERSION, downloads parameters, resolves the **FirmwareProfile**
  (version + parameter fingerprint `WPNAV_BLEND`, `SPRAY_PUMP_RATE`), then downloads
  the mission. Sends GCS HEARTBEAT at 1 Hz.
- **TelemetryStore**: reducers fold each message into an immutable `VehicleSnapshot`
  (attitude, position, GPS×2, battery, wind, outputs, IMU lanes, health bits, mode,
  mission progress). The UI samples it at display rate (≤ 30 Hz), not per message —
  APX emits ~140 msg/s.
- **CommandService**: COMMAND_LONG/INT → await matching COMMAND_ACK; 1.5 s timeout,
  3 attempts (confirmation field incremented); result mapped to plain language.
  Commands are checked against the profile before sending. Guided "fly here" uses
  SET_POSITION_TARGET_GLOBAL_INT (full precision) rather than DO_REPOSITION.
- **ParameterService**: PARAM_REQUEST_LIST, gap fill by index after 3 s silence
  (≤ 5 tries), keyed by **name** (APX index order is unstable across reboots).
  PARAM_SET waits for the echo (1 s × 3), then compares requested vs echoed value and
  reports APX's silent clamping. Unknown‑name sets time out with a clear message.
  Metadata (type, default, min, max, description) comes from `param_meta_gen`, plus a
  hand‑written overlay for units/enums/groups. Because APX 0.1.x doesn't persist
  parameters, the service supports **parameter profiles**: save a set, and re‑apply it
  on reconnect after showing a diff for confirmation.
- **MissionTransfer**: upload and download state machines for mission_type 0 only.
  Upload: COUNT → answer REQUEST and REQUEST_INT by seq → ACK; 1.5 s ack timeout, COUNT
  re‑sent up to 5×. Download: REQUEST_LIST → COUNT → REQUEST_INT per seq; 250 ms
  item retry × 5; final ACK. Progress events drive the UI.
- **AlertsEngine**: declarative rules over snapshots and events — link lost/regained,
  battery vs the vehicle's own `BATT_LOW_VOLT`/`BATT_CRT_VOLT`, GPS fix/sats/HDOP,
  sensor‑health bit drops, IMU lane disagreement, mode/arm changes, mission item
  reached/complete, STATUSTEXT by severity, crash. Repeat suppression, acknowledgement,
  history, optional speech.

### 4.4 FirmwareProfile (APX 0.1.x)

```dart
const apx010 = FirmwareProfile(
  modes: { stabilize, altHold, auto, guided, loiter, rtl, land, posHold(aliasOf: loiter), brake },
  hiddenModes: { agriSpray, agriZigzag },              // placeholders in firmware
  missionCatalog: ApxMissionCatalog.v010,             // 10 commands, exact params
  commands: { arm, disarm, forceDisarm, setMode, takeoff, land, missionStart,
              changeSpeedHorizontal, setServoAux9to16, sprayer, guidedGoto },
  params: ParamCaps(persistent: false, clampsSilently: true, encoding: floatCast),
  missionTypes: { mission },                          // never fence/rally
  homePosition: HomeSource.reported,                  // HOME_POSITION at 1 Hz
  calibration: false, logDownload: false, motorTest: false, reboot: false,
);
```

## 5. Mission planning (built in stage 7, package `apx_mission`)

- **Catalogue** (`ApxCatalog`): the ten commands `mode_auto.cpp` executes, each with
  exactly the parameters it reads, units, ranges and a note on what APX does differently.
- **Elements** (`MissionPlan` = settings + elements + payloads): waypoint (speed,
  acceptance radius, optional heading, payload actions on arrival), action/command,
  payload action, land (at a point or home), **survey** (polygon, spacing, pass
  direction, run‑in/out, start side), **corridor** (path, width, lane spacing),
  **orbit** (centre, radius, start bearing, angle 1–3600°, CW/CCW, leg angle 1–90°,
  heading: travel / centre / outward / fixed). Mission settings: take‑off altitude,
  default altitude and speed, finish (RTL / land at end / hover).
- **Payloads** (Vehicle → Payloads, copied into each plan): sprayer (DO_SPRAYER),
  spreader/seeder (spinner output via DO_SET_SERVO), servo/relay (on/off PWM), gimbal
  (tilt → PWM). Every pattern can switch a payload on along its passes only or for the
  whole pattern; waypoints can set any payload state.
- **Compiler** (`MissionCompiler`) turns elements into the exact items APX runs, using
  the connected vehicle's parameters (`VehicleFacts`: WP_YAW_BEHAVIOR, SPRAY_*, WPNAV_*,
  RTL_ALT): seq 0 home placeholder, GLOBAL_RELATIVE_ALT_INT, DO_CHANGE_SPEED only where
  the speed changes, payload DO items around each pass, CONDITION_YAW before each orbit
  leg when the heading must be held (it stops the vehicle to turn, then locks heading for
  the rest of the mission, so "face travel" after a lock is emulated per leg).
- **Validator** (`validatePlan`): errors block upload (empty mission, altitude ≤ 0,
  speed > 20 m/s, self‑crossing polygon, orbit too small, > 2000 survey passes or
  items, unknown payload); warnings for things APX will silently ignore (servo outputs
  other than the sprayer pump/spinner inside missions, SPRAY_ENABLE = 0, items after a
  landing, > 120 m) and notes for heading‑hold stops.
- **Editing**: draw on the map, drag corners/path points/centre/radius, + handles insert
  corners, long‑press removes one; every element has its own editor; **Convert to
  waypoints** replaces a pattern with its individual items (compiles to the identical
  mission, tested). Undo/redo; the working plan autosaves to `plans/current.apxplan`.
- **Transfer**: upload then read back and compare; download into editable elements.
  **Resume from item N** builds a new mission (take‑off if landed, speed, heading lock,
  payload state, the start of the interrupted leg, then the rest), because APX always
  restarts AUTO at item 0 (TODO(APX-FW-11)).
- **Files**: `.apxplan` (lossless), GCS `.plan` import/export (surveys/corridors imported
  as patterns), Standard GCS `.waypoints` import/export; dropped items are listed.
- **Estimates**: distance, time (climb/descent, legs at the current speed, yaw stops,
  landing), payload‑on distance, area, item count.
- Exit test (SITL): a planned survey with the sprayer and a centre‑facing orbit is
  uploaded, read back identical, flown in AUTO (pump PWM rises on the passes, each orbit
  leg starts facing the centre within 10°) and returns home.

## 6. Map system (built in stage 6, package `apx_geo`)

```
MapCanvas (flutter_map) ── one URL scheme: http://127.0.0.1:<port>/tiles/<source>/{z}/{x}/{y}
 ├─ base map + raster overlays ──► TileServer (dart:io, loopback; optional LAN)
 │                                    └─ TileService
 │                                        ├─ TileCache (SQLite, LRU, pinned areas/overlays)   ← hit
 │                                        ├─ online providers, keys added server‑side          ← miss
 │                                        │    └─ GCJ‑02 / BD‑09 / Baidu grid → reprojected to
 │                                        │       WGS‑84 Web Mercator on a background isolate
 │                                        ├─ local sources: MBTiles · XYZ folder
 │                                        └─ overlay pyramids (rendered into the cache)
 ├─ vector overlays (Shapefile) ── PolygonLayer / PolylineLayer / CircleLayer, tap → attributes
 ├─ MissionLayer (stage 7)
 └─ VehicleLayer: glyph, trail, home, guided target
```

- **Everything on the map is WGS‑84.** Providers drawn in a Chinese datum are
  reprojected per pixel by the tile server (source tiles fetched in the provider's own
  grid, warped, re‑encoded), so vehicle, mission and overlays never need converting.
  The GCJ‑02 offset uses the conventional coarse China box; western India, Nepal and
  Mongolia fall inside it, so Chinese providers are only meaningful inside China.
- `MapProvider { id, name, group, attribution, url(z,x,y,auth), labels?, maxZoom, datum,
  grid, key, googleSession, imagery, allowsBulkDownload }`. Keys are stored per service
  (one Google key serves all Google map types) and are added by the server: they never
  appear in URLs the map widget or a LAN client sees.
- **Providers** (every URL probed against the live service): OSM (default), OpenTopoMap,
  Esri World Imagery / Topographic, Google Map Tiles API (roadmap, satellite, hybrid,
  terrain; session tokens created and renewed automatically), Azure Maps (imagery, road),
  Mapbox Satellite, MapTiler Satellite, Tianditu (imagery/vector + labels, key), Gaode
  road / satellite + labels (GCJ‑02), Baidu road / satellite (BD‑09, Baidu MC grid with
  the polynomial taken from Baidu's own JS API), custom XYZ (`{z} {x} {y} {-y} {s} {q}`)
  and WMS (EPSG:3857), MBTiles files, XYZ tile folders.
  Bing Maps was dropped: Microsoft stopped issuing Bing Maps keys in 2025 (Azure Maps
  replaces it). Baidu and Gaode need no key for tiles.
- **Cache**: SQLite `tiles.db` in the app data folder; browsing tiles refresh after 30
  days and are LRU‑evicted above the user's limit; downloaded areas and overlays are
  pinned. Offline mode serves only the cache. Stale tiles are served when a provider is
  unreachable. Composed tiles missing a source tile are shown but not cached.
- **Area download** is offered only for providers whose terms allow it and for custom
  sources; OSM, Google, Esri, Mapbox, etc. are browse‑cache only. MBTiles is the
  supported way to carry planned offline imagery.
- **Provider health** (last error, key rejected) is shown in the Layers panel and next to
  the key in Settings.

### Overlays
| Format | Approach |
|---|---|
| Shapefile (.shp/.dbf/.prj/.cpg/.shx, or zipped) | Own reader: Point/MultiPoint/PolyLine/Polygon (+Z/M), holes matched to their outer ring, DBF attributes with `.cpg` encoding, `.prj` WKT (OGC or ESRI) via `Crs.parse` (UTM/4326/3857 built in, others through proj4dart). Drawn as vectors; tap shows attributes. Files are copied into the app data folder. |
| GeoTIFF | Own IFD/GeoKey reader (tiepoint + scale, ModelTransformation incl. rotation, PixelIsArea/Point, EPSG 4326/3857/WGS 84 UTM, GDAL nodata, user‑defined CRS via citation); pixels via `image` (none/LZW/Deflate/PackBits/JPEG). 16‑bit and float rasters (DEMs) are stretched 2–98 %. Not supported: BigTIFF (>4 GB); whole image is decoded in memory. |
| PNG / JPG | Four corners (true homography), centre + size + rotation, or world file (+ `.prj`) found next to the image. Corners can be dragged on the map afterwards. |

Raster overlays are reprojected **per pixel** (exact mapping on a 16‑px grid, bilinear in
between) into a Web‑Mercator pyramid on a background isolate: the deepest level matches
the source resolution, coarser levels are box‑filtered from their children. Tiles go into
the cache, pinned. Exit criterion met: fixture markers (UTM, geographic PixelIsPoint,
rotated Mercator, four‑corner perspective image, world file in UTM) land within ±1 px at
zoom 19 against pyproj/numpy references.

## 7. Logs and analysis (apx_logs)

- **TlogRecorder**: every session is recorded as standard `.tlog` (8‑byte big‑endian
  µs timestamp + raw frame), so files also open in other tools.
- **LogLibrary**: index with summary — duration, distance, max altitude/speed, battery
  used, modes, alerts.
- **Replay**: a `ReplayLink`, so Fly view, alerts and diagnostics work unchanged during
  replay (speed, pause, scrub).
- **Analysis**: pick any message field → time series (min/max decimation per pixel for
  long logs), synced map track and timeline cursor, event markers (mode, arm,
  STATUSTEXT), CSV export. Also imports APX SITL `--sensor-log` CSV for sensor‑lane
  studies.

Onboard log download is absent because APX has no log transfer protocol.

## 8. Vehicle workspace

- **Parameters**: searchable table grouped by prefix; value, default, range, units,
  description; modified‑only filter; diff against file/profile; import/export
  (`.apxparams`, plus APX‑style `NAME,VALUE` text for convenience); clamp and
  non‑persistence banners from the profile.
- **Setup pages** (parameter‑driven, APX‑specific): Flight modes (FLTMODE1–6),
  Navigation (WPNAV/RTL/LAND shown in m and m/s, written in cm), Attitude & rate tuning
  with a live response graph, Sprayer, Battery thresholds, RC mapping, Servo functions.
  Parameters that are registered but not enforced by 0.1.x (FS_*, ARMING_CHECK,
  RCMAP_*) carry a "not enforced by this firmware" tag.
- **Diagnostics**: sensor lanes (four IMU/baro/mag lanes side by side, with spread),
  GPS 1/2, SYS_STATUS health matrix, servo/motor outputs, link statistics, MAVLink
  inspector (rates, fields, sparkline per field), STATUSTEXT console.
- **Manual control** (later stage): gamepad → MANUAL_CONTROL at 25 Hz with deadman;
  APX neutralises sticks after 1 s without input.

## 9. State management and app shell

- Riverpod 3 for dependency injection and state; services are plain Dart classes
  exposed through providers. go_router for navigation. Settings (including map API
  keys) in `settings.json`; plans, overlays, logs and the tile cache (`tiles.db`) in
  the app data directory, which is made owner‑only on Linux/macOS.
- Targets: **Windows and Linux** desktop (primary, field laptops), then **Android**
  tablets (USB‑OTG serial). macOS builds are kept compiling but are untested; iOS is
  out of scope.

## 10. Selected packages (all permissive licences)

| Need | Package |
|---|---|
| Map rendering | `flutter_map` 8.x, `latlong2` |
| Serial | `flutter_libserialport` (desktop), `usb_serial` (Android) |
| State / routing | `flutter_riverpod` 3.x, `go_router` |
| Projections | `proj4dart` |
| Raster decode / zip / HTTP | `image`, `archive`, `http` |
| File picking | `file_selector` |
| Storage | `sqlite3`, `path_provider` (settings are a JSON file written atomically) |
| Speech | `flutter_tts` |
| Gamepad | `gamepads` |
| Icons | `lucide_icons_flutter` + custom aviation glyphs |
| Fonts | Inter + JetBrains Mono, bundled (OFL) — no runtime font fetching in the field |

Written in‑house on purpose: MAVLink codec (`dart_mavlink` is pinned below Dart 3),
tile cache (`flutter_map_tile_caching` is GPL), Shapefile/GeoTIFF readers, charts
(performance on long logs).

## 11. Testing

| Level | What |
|---|---|
| Unit (`dart test`) | codec golden bytes vs pymavlink; parser fuzz; CRC_EXTRA table; command/param/mission state machines with a scripted fake vehicle (timeouts, drops, duplicates, out‑of‑order); validator rules; geodesy; Shapefile/GeoTIFF fixtures (UTM and geographic); homography |
| SITL integration | `test_sitl/` spawns the real `apx_flight_controller` + physics on free ports: connect, 153 params, clamp detection, mission round trip, arm → AUTO → MISSION_CURRENT progression, guided go‑to, sprayer |
| Widget / golden | Alloy components, instruments at fixed telemetry values, both themes |
| Manual | Zephyr USB‑CDC board when available (arming refusal path, no‑sensor reporting) |

Each stage closes only when its tests pass.

## 12. Delivery stages

| Stage | Output | Exit criteria |
|---|---|---|
| 1–3 | This analysis, matrix, architecture, UI concept | Approved |
| 4 ✓ | Workspace, `apx_mavlink` + generator, `apx_link`, `apx_vehicle` (session, telemetry, commands, params, mission transfer), SITL harness | Integration suite green against SITL |
| 5 ✓ | Alloy design system, app shell, Fly view (cockpit, status rail, action stack, mode ring, alerts) | Fly a SITL mission from the app |
| 6 ✓ | Map engine, providers, tile cache, Shapefile / GeoTIFF / image overlays | Overlay fixtures align to ±1 px at zoom 19 |
| 7 ✓ | Plan view, APX catalog, patterns (survey, corridor, orbit), payloads, validator, upload/download, resume, file I/O; Vehicle setup pages | Plan → upload → fly → progress in SITL |
| 8 | Parameters, setup pages, diagnostics, logs/replay/analysis, alerts and speech, gamepad | Feature tests + SITL replay |
| 9 | Performance pass, packaging (Windows, Linux, Android; macOS best effort), user docs | Release builds |

## 13. Firmware findings worth fixing upstream

The firmware owner is fixing these in APX. Each GCS workaround is tagged
`TODO(APX-FW-n)` with the item number below, so `grep -rn "TODO(APX-FW-"` lists
everything to remove once a fix lands.

1. A MISSION_REQUEST_LIST / MISSION_COUNT for mission_type 1/2 is answered with the mission (and a fence upload would overwrite it). It should be NACKed with `MAV_MISSION_UNSUPPORTED`.
   *Partly fixed (fence, 2026-11):* builds with `FENCE_ENABLE` accept a fence upload (MISSION_COUNT type 1) into the onboard polygon, so the GCS uploads fences only to those builds. Still open: fence download and rally (MISSION_REQUEST_LIST ignores mission_type), and the item requests during a fence upload carry mission_type 0 instead of 1.
2. PREFLIGHT_CALIBRATION and DO_PARACHUTE ACK `ACCEPTED` without acting — should be `UNSUPPORTED` until wired.
3. Parameter persistence stubs (`save_to_storage` / `load_from_storage`).
4. ~~No HOME_POSITION message; home is the boot position.~~ *Fixed (2026-11):* HOME_POSITION streams at 1 Hz, and MAV_CMD_DO_SET_HOME (COMMAND_LONG or COMMAND_INT, NaN altitude keeps home's altitude) moves the point RTL returns to, also in flight; a home set by the GCS survives arming and landing. Mission seq 0 is still ignored.
5. NAV_WAYPOINT hold time (p1) is not implemented although documented.
6. VFR_HUD throttle is always 0; SYS_STATUS sets DIFFERENTIAL_PRESSURE instead of BATTERY.
7. AUTOPILOT_VERSION has no APX identifier (vendor/product 0, autopilot = APX).
8. `tools/apx_param.py export` writes mock values.
9. CONDITION_YAW locks the heading for the rest of the mission with no way back to
   WP_YAW_BEHAVIOR, and turning always stops the vehicle; a "face the centre" orbit has to
   stop at every vertex. Per‑waypoint yaw (NAV_WAYPOINT p4) or a ROI command would fix both.
10. Inside a mission, DO_SET_SERVO only drives the sprayer pump (output 9 / SPRAY_PUMP_CH)
    and spinner (10 / SPRAY_SPIN_CH); any other output is ignored, so gimbals and other
    servo payloads can't be switched by a mission (they work as direct commands).
11. AUTO always restarts at item 0 and DO_SET_MISSION_CURRENT is unsupported, so resuming
    a mission means uploading a new one.
