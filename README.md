# APX Flight Manager

Ground control station for the APX flight controller (Flutter/Dart).
Design and scope: [`docs/`](docs/) — capability matrix, architecture, UI concept.

## Layout

| Path | What |
|---|---|
| `apps/flight_manager` | The Flutter application (Windows, Linux, Android, iOS, macOS) |
| `packages/apx_mavlink` | MAVLink v2 codec (generated messages, framing, parser) |
| `packages/apx_link` | UDP, TCP and serial transports |
| `packages/apx_vehicle` | Vehicle session, telemetry, commands, parameters, mission transfer, firmware profile |
| `packages/apx_mission` | Mission planning: APX command catalogue, payloads, survey/corridor/orbit patterns, compiler, validator, plan files, resume |
| `packages/apx_geo` | Geodesy, map providers, tile cache and local tile server, Shapefile / GeoJSON / GeoTIFF / image overlays |
| `tool/mavlink_gen` | Generates `apx_mavlink` from the MAVLink XML in `tool/mavlink_gen/definitions` |
| `tool/param_meta_gen` | Generates parameter metadata (range, default, description) from APX's `param_manager.cpp` |
| `tool/fixtures` | Test fixture generators (pymavlink frames; GeoTIFF/Shapefile/image fixtures via pyproj, pyshp, Pillow) |

The repository is a Dart pub workspace: one `flutter pub get` at the root resolves
the app and every package.

## Platform status

| Platform | Status |
|---|---|
| Linux (x64) | Primary development platform; release build verified (Ubuntu 22.04, Flutter 3.47.9) |
| Windows 10/11 (x64) | Primary target; project configured, build on a Windows PC |
| Android (tablet) | Target; project configured, needs the Android SDK |
| iOS (iPad/iPhone) | Target; project configured (`ios/`), needs a Mac with Xcode |
| macOS | Optional; project configured, untested (no test hardware) |

Video streaming has its own per-platform status in [§11.9](#119-what-has-been-verified).

---

## 1. Common setup (all platforms)

1. Install **Flutter 3.47 stable** (includes Dart 3.13):
   https://docs.flutter.dev/get-started/install — or on Linux:
   ```bash
   mkdir -p ~/development && cd ~/development
   curl -fLO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz
   tar -xf flutter_linux_3.47.9-stable.tar.xz
   export PATH=$HOME/development/flutter/bin:$PATH   # add to ~/.bashrc
   ```
2. Get the code's dependencies from the repository root:
   ```bash
   cd APX_Flight_Manager
   flutter pub get
   ```
3. Check what your machine can build:
   ```bash
   flutter doctor
   ```

All app commands below run from `apps/flight_manager`.

---

## 2. Linux (Ubuntu 22.04 or newer)

**Prerequisites**
```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev \
                 libmpv-dev libepoxy-dev
```
`libmpv-dev` is the video engine (§11); without it the Linux build fails at CMake. Users of the
release bundle need the runtime library only (`libmpv1` on Ubuntu 22.04, `libmpv2` on 24.04).
The first build also downloads mimalloc (media_kit's allocator) from GitHub, so it needs internet.

**Run (debug, hot reload)**
```bash
cd apps/flight_manager
flutter run -d linux
```

**Build a release**
```bash
flutter build linux --release
```
Output: `apps/flight_manager/build/linux/x64/release/bundle/`. Ship the whole
`bundle` folder; start it with `./apx_flight_manager`.

**Serial / USB access** (for USB‑connected flight controllers and telemetry radios,
once the serial connection lands in the app): add your user to the `dialout` group,
then log out and back in.
```bash
sudo usermod -aG dialout $USER
```

---

## 3. Windows 10 / 11 (x64)

**Prerequisites**
- Flutter SDK (unzip the Windows release, add `flutter\bin` to `PATH`).
- **Visual Studio 2022** (Community is fine) with the **"Desktop development with C++"**
  workload. Visual Studio Code is not enough.
- Git for Windows.
- Turn on **Developer Mode** (Settings → System → For developers). Flutter plugins
  need symlink support.

**Run**
```powershell
cd apps\flight_manager
flutter run -d windows
```

**Build a release**
```powershell
flutter build windows --release
```
Output: `apps\flight_manager\build\windows\x64\runner\Release\`. Ship the whole
`Release` folder; start `apx_flight_manager.exe`.

**Firewall**: on the first UDP connection Windows asks whether to allow network
access. Allow it on private networks, or the app won't receive telemetry on UDP 14550
(or video on UDP 5600).

**Video**: the first build downloads the libmpv/FFmpeg DLLs (`mpv-dev-x86_64-20230924`) and
ANGLE from GitHub (~35 MB, cached in the build folder), so it needs internet. They are copied
into `Release\` automatically — ship the whole folder.

---

## 4. Android (tablets)

**Prerequisites**
- Android Studio (or the Android command‑line tools) with an Android SDK platform and
  build tools installed.
- `ANDROID_HOME` pointing at the SDK, and the licences accepted:
  ```bash
  flutter doctor --android-licenses
  ```
- A tablet with **USB debugging** on (Settings → About → tap *Build number* 7 times →
  Developer options → USB debugging), or an emulator.

**Run**
```bash
cd apps/flight_manager
flutter devices                 # find the device id
flutter run -d <device-id>
```

**Build**
```bash
flutter build apk --release            # single APK, side‑loadable
flutter build appbundle --release      # for Google Play
```
Output: `build/app/outputs/flutter-apk/app-release.apk` (APK) and
`build/app/outputs/bundle/release/app-release.aab` (bundle).

> Release builds are currently signed with the debug key (Flutter's default). Set up a
> release keystore before distributing: https://docs.flutter.dev/deployment/android#sign-the-app

The app requests the `INTERNET` permission for UDP/TCP vehicle links and video. USB‑OTG serial
support for Android comes with the serial connection work.

**Video**: the build downloads libmpv for each ABI (`libmpv-android-video-build` v1.1.7) from
GitHub on the first build; each ABI adds roughly 25–30 MB to a universal APK — use
`flutter build apk --split-per-abi` (or an app bundle) to ship one ABI per device.
`WRITE_EXTERNAL_STORAGE` (max SDK 29) is declared only for copying recordings to the gallery
on Android 9/10; Android 11+ needs no storage permission.

---

## 5. macOS (optional, untested)

**Prerequisites**: Xcode (with command‑line tools) and CocoaPods
(`sudo gem install cocoapods` or `brew install cocoapods`).

```bash
cd apps/flight_manager
flutter run -d macos
flutter build macos --release
```
Output: `build/macos/Build/Products/Release/APX Flight Manager.app`. Network client
and server entitlements are already set so vehicle links work inside the macOS sandbox;
`files.user-selected.read-write` lets you pick a video recording folder.

---

## 6. iOS / iPadOS (needs a Mac)

**Prerequisites**: macOS with Xcode 16+ and CocoaPods, an Apple developer account for
signing, iOS/iPadOS 15 or newer on the device.

```bash
cd apps/flight_manager
flutter pub get
cd ios && pod install && cd ..        # first time; Flutter also runs it on build
open ios/Runner.xcworkspace           # set your Team under Signing & Capabilities once
flutter run -d <device-id>
flutter build ipa --release           # App Store / TestFlight
```

The `ios/` project was generated with `flutter create --platforms=ios` (bundle id
`com.apx.apxFlightManager` — change it to yours). `Info.plist` already contains:

| Key | Why |
|---|---|
| `NSLocalNetworkUsageDescription` | iOS 14+ asks before the app may talk to the vehicle/camera on the LAN (MAVLink, RTSP/UDP video) |
| `NSPhotoLibraryAddUsageDescription` | "Copy to gallery" for recordings and snapshots (add-only access) |
| `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` | Recordings appear in the Files app (On My iPad → APX Flight Manager → Video) |

Multicast UDP video on iOS additionally needs Apple's
`com.apple.developer.networking.multicast` entitlement (request it from Apple); unicast UDP
and RTSP need nothing extra.

---

## 7. Connecting to a vehicle

The app opens on the **Fly** view. With no vehicle connected it shows the connect
form over the map; once connected you get the status rail, alerts, cockpit
instruments and the action stack (slide to arm / take off / return home).
Long‑press the map in Guided to fly to a point. **Link** shows transport statistics
and what the connected firmware supports; **Plan** and **Vehicle** are described below;
**Settings** holds app options (Silver/Graphite theme, units, audio, maps and offline, video, about).

**APX SITL on the same machine** (from the `apx` firmware repository):
```bash
python3 sitl/sim_vehicle.py --vehicle quad_x --sim builtin
```
Then in the app, either:
- **TCP** → host `127.0.0.1`, port `5760` (recommended), or
- **UDP listen** → port `14550`. Only one program can listen on 14550, so close
  Standard GCS first.

**APX on another machine** (companion computer, Wi‑Fi): TCP to that machine's IP,
port `5760`.

---

## 8. Planning a mission (Plan)

The tools on the right of the Plan map add elements; the panel on the left lists them in
flight order (drag to reorder) and edits the selected one. When a vehicle is connected
it is drawn on the map, the map centres on it once (for an empty plan), and the
locate button centres on it again.

- **Waypoint**: tap the map. Per waypoint: altitude, speed, corner radius, optional
  heading, and payload actions on arrival (e.g. sprayer on, gimbal −45°).
- **Survey**: tap the corners of the field, then *Finish*. Set pass spacing (or use
  *Spacing from swath width*), pass direction (*Along longest edge* is the default),
  run‑in/run‑out, start side, and the payload (on along the passes only, or for the
  whole survey).
- **Corridor**: tap points along a road/canal/line; set width and lane spacing. Lanes
  round the outside of sharp corners and are trimmed on the inside, so they never loop
  back; where a hairpin is narrower than the corridor, the inner lanes skip that stretch.
- **Orbit**: tap the centre, then set radius, angle to fly (360° = one turn), CW/CCW,
  *leg angle* (the circle is flown as straight legs of this many degrees) and heading:
  along travel, at the centre, outward or fixed. APX turns by stopping, so "centre" and
  "outward" stop once per leg; a larger leg angle means fewer stops.
- **Action / Payload / Land** buttons add a speed change, a turn, a payload switch or a
  landing after the selected element.
- Drag waypoints, corners, path points and the orbit's radius handle on the map; tap a
  **+** between corners to add one. To delete a corner or path point, double‑click it,
  or right‑click it (long‑press on touch screens) and choose *Delete point*.
- Move a whole survey, corridor or orbit: drag its centre handle (four arrows), or drag
  its icon when it isn't selected.
- The bin button deletes every waypoint, or every item, in one step (*Undo* restores).
- **Convert to waypoints** turns a pattern into its individual items so each can be edited.
- Warnings and errors are listed under the summary; errors block *Upload*. The planner
  warns when APX 0.1 would ignore something (e.g. a servo payload other than the sprayer
  pump/spinner inside a mission).
- **Upload** sends the mission and reads it back to confirm; **Download** reads the
  vehicle's mission into the editor. **Resume…** (after a mission was interrupted)
  uploads a mission that continues from a chosen item.
- File menu (…): new, open/save `.apxplan`, open/export APX Flight Manager `.plan` and
  Standard GCS `.waypoints`. The working plan is also saved automatically.

## 9. Vehicle setup (Vehicle)

- **Payloads**: the devices on the drone (sprayer, spreader/seeder, servo or relay,
  gimbal) with their outputs and PWM values, plus test buttons when connected. Plans
  offer these on every waypoint and pattern.
- **Sprayer, Mission & navigation, Landing & return, Battery & safety, Frame & motors,
  Tuning, Flight modes**: the APX parameters in plain units (m/s, m, °) with the
  firmware's own ranges and descriptions; a reset button appears on changed values.
- Parameters are read on connect; a progress capsule shows the count on every page and
  offers *Retry* if some could not be read.
- **All parameters**: search, *changed only*, save to file / apply a file.
- APX 0.1 does not store parameters across reboots: save a file and apply it after
  power‑up.

## 10. Maps and overlays

Open **Map layers** (the layers button on the right of the Fly view).

- **Base maps**: OpenStreetMap (default), OpenTopoMap, Esri imagery/topographic, Google
  (roadmap, satellite, hybrid, terrain), Azure Maps, Mapbox, MapTiler, Tianditu, Gaode and
  Baidu. Maps marked *needs key* work once you paste a key in **Settings → Maps**; keys stay
  on this computer and are only sent to their own service. Gaode and Baidu draw in China's
  offset datums; the app reprojects them so they line up with GPS (inside China).
- **Offline**: every tile you view is cached (`tiles.db` in the app data folder; the limit
  is in Settings). *Offline mode* uses only cached tiles. *Download visible area* works for
  custom sources (OSM, Google, Esri and the other public services don't permit bulk
  download). For planned offline work, add an **MBTiles** file or a **tile folder** in
  Settings → Maps → Offline map files.
- **Custom sources**: Settings → Maps → *Add XYZ or WMS source* (`{z} {x} {y}`, `{-y}` for
  TMS, `{s}` for a/b/c subdomains, `{q}` for quadkeys; WMS is requested in EPSG:3857).
- **Share tiles on the local network** lets a tablet use this computer's cache at the
  address shown in Settings.
- **Overlays** (*Add overlay…*):
  - **GeoTIFF**: EPSG 4326, 3857 or WGS 84 / UTM; 8‑bit colour or 16‑bit/float elevation.
    Not yet: BigTIFF (files over 4 GB).
  - **Image (PNG/JPG)**: uses the georeference next to the image when there is one — a
    GDAL/QGIS `.aux.xml` (as written by "Save as PNG") or a world file
    (`.pgw`/`.jgw`/`.wld`, plus `.prj` if projected); otherwise you place it by centre + size + rotation or by four
    corner coordinates, then fine‑tune with *Adjust corners* by dragging on the map.
  - **Shapefile**: pick the `.shp` (its `.dbf`, `.prj`, `.cpg` are picked up from the same
    folder) or a `.zip`. On Android pick all the parts together or use a zip. Tap a
    feature to see its attributes.
  - **GeoJSON** (`.geojson`, `.json`): FeatureCollection, a single Feature or a bare geometry;
    points, lines and polygons (with holes), their Multi‑ forms and GeometryCollections. Coordinates
    are WGS 84 longitude/latitude as the standard requires; older files that name a CRS
    (`"crs": … "EPSG:32643"`, as GDAL/QGIS write) are reprojected when it is EPSG 4326, 3857 or
    WGS 84 / UTM. Features without a usable geometry are skipped. Tap a feature to see its
    properties (nested values are shown as JSON).

  Raster overlays are rendered into map tiles in the background (progress shows in the
  list), so large images stay smooth to pan.

## 11. Video (camera streaming, recording)

Live camera video in the Fly view, modelled on APX Flight Manager: a floating video window over
the map, map/video swap, full screen, recording and snapshots. APX does not implement the
MAVLink camera protocol (`VIDEO_STREAM_INFORMATION`), so the stream is configured in
**Settings → Video**, like standard GCS manual RTSP/UDP sources.

### 11.1 Using it

- **Turn it on**: Settings → Video → *Video streaming*, choose the source, enter the URL/port,
  press **Test connection**. With *Connect automatically* on (default) the stream starts with
  the app and restarts when the source settings change.
- **Fly view layouts** — the video button in the map tools (right column) opens the menu:
  *Map only*, *Map + video window* (default), *Video + map window*, *Video only*,
  *Full‑screen video*, *Record*, *Snapshot*, *Start/Stop video*.
- **Video window (picture‑in‑picture)**: tap/click it to swap map and video. Drag it anywhere —
  it settles into the nearest corner. Resize with the grip (bottom‑right) or with two fingers.
  Its header (hover with a mouse; always shown on touch screens) has *Record*, *Swap*,
  *Full screen* and *Hide*. The window floats above the map but below the status rail,
  instruments and action panel, so flight controls are never covered. Position, size and
  layout are remembered.
- **When video fills the view** the right column shows the video tools: back to the map,
  record, snapshot, pause/resume, stop/start, full screen. Instruments and the status rail stay.
- **Full screen**: the OS window goes full screen on desktop (if it isn't already) and the
  system bars hide on phones/tablets; rotation stays free. Controls fade after 3 s — move the
  mouse or tap to show them. Keys: **Esc**/**F** exit, **Space** pause, **R** record,
  **S** snapshot; double‑tap/double‑click exits; Android back exits.
- **Map ↔ video switching never restarts the stream**: one player feeds every view, and the map
  stays mounted (hidden) in *Video only*, so its camera and layers are kept.
- **Status** is drawn on the picture: *Connecting…*, *Reconnecting in N s · attempt n* (with
  *Retry now*), *No video* + reason (with *Retry*), *Paused*, *Video stopped* (with *Start*).
  A red **REC mm:ss** sits under the status rail while recording, in every layout.

### 11.2 Video engine: choice and versions

| Candidate | Why not / why |
|---|---|
| **media_kit (libmpv + FFmpeg)** — *selected* | One engine, same behaviour on Android, iOS, Windows, macOS and Linux. RTSP (TCP/UDP), raw RTP via SDP, MPEG‑TS/UDP, HLS, RTMP, SRT; H.264/H.265 hardware decoding per platform; `stream-record` saves the received stream **without re‑encoding**; Flutter texture output. media_kit is MIT; the prebuilt libmpv/FFmpeg binaries carry their own (L)GPL licences — review the `media-kit/libmpv-*-build` licences before distributing |
| GStreamer (standard video engine) | No maintained Flutter plugin; would need a native texture plugin per platform plus GStreamer SDKs for Android/iOS/Windows — far more build and maintenance work |
| FFmpeg directly | Possible, but decoding, A/V sync, hardware decode and GPU texture upload would all be ours to write per platform; libmpv already does this on top of FFmpeg |
| Qt Multimedia | Not applicable — APX FM is Flutter, not Qt |
| `video_player` (ExoPlayer/AVPlayer) | No Windows/Linux, no RTSP or raw RTP on iOS, no recording |
| fvp / libmdk | Capable, but libmdk is closed source with its own licence terms for commercial use |
| flutter_vlc_player | Android/iOS only |

| Package | Version | What |
|---|---|---|
| `media_kit` | 1.2.6 | Player (libmpv via FFI) |
| `media_kit_video` | 2.0.1 | `Video` widget / texture, native full screen helper |
| `media_kit_libs_video` | 1.0.7 | Per-platform libmpv: Android 1.3.8 (libmpv-android-video-build v1.1.7), iOS/macOS 1.1.4 (libmpv-darwin-build v0.6.0), Windows 1.0.11 (mpv-dev 2023‑09‑24 + ANGLE), Linux 1.2.1 (system `libmpv`) |
| `gal` | 2.3.3 | Copy recordings/snapshots to the Android gallery / iOS Photos |
| `ffi` | 2.x | Free-space check (statvfs / GetDiskFreeSpaceExW) |

Code: `apps/flight_manager/lib/video/` — `video_settings.dart` (settings, validation,
stream endpoints), `video_backend.dart` (engine interface), `media_kit_backend.dart`
(libmpv implementation), `video_manager.dart` (stream state machine, reconnects, recording,
snapshots, test connection, app lifecycle), `video_storage.dart` (folders, free space,
storage limit), `video_layout.dart`, `video_pip.dart`, `video_widgets.dart`,
`video_fullscreen.dart`; the settings page is `lib/shell/video_settings_section.dart`.

### 11.3 Platform setup and permissions

| Platform | Extra setup | Permissions |
|---|---|---|
| Linux | `sudo apt install libmpv-dev` (build), `libmpv1`/`libmpv2` (run) | none |
| Windows | none — libmpv DLLs are downloaded at build time and bundled | firewall prompt for UDP video |
| Android | none — libmpv `.so` per ABI bundled | `INTERNET`; `WRITE_EXTERNAL_STORAGE` ≤ API 29 for gallery copy (asked when first copying) |
| iOS | `pod install` (frameworks downloaded by CocoaPods) | Local Network (asked on first connection), Photos add-only (asked when first copying) |
| macOS | as iOS | sandbox: network client/server, user-selected folders |

If libmpv can't be loaded (e.g. Linux without `libmpv`), the app still runs; the video panel
shows *Video engine unavailable* with the reason.

### 11.4 Sources, protocols and codecs

| Source (Settings → Video) | URL / port | Notes |
|---|---|---|
| RTSP stream | `rtsp://[user:pass@]host[:port]/path`, `rtsps://` | Transport TCP (default, robust over Wi‑Fi/NAT), UDP (lowest latency) or Automatic |
| UDP · RTP H.264 | port (default 5600), optional multicast group | standard "UDP h.264": raw RTP, payload type 96; parameter sets must be sent in-band |
| UDP · RTP H.265 | port | as above, H.265 |
| UDP · MPEG‑TS | port, optional multicast group | e.g. from ffmpeg/encoders sending TS over UDP |
| TCP · MPEG‑TS | `tcp://host:port` | |
| Other URL | `http(s)://…` (HLS, MJPEG), `rtmp(s)://`, `srt://`, `udp://`, `rtp://`, `file://` | anything FFmpeg opens |

Codecs: H.264 and H.265/HEVC (plus MJPEG, MPEG‑2/4, VP8/VP9, AV1 in software).

| Platform | Hardware decoding (Decoder setting) |
|---|---|
| Android | MediaCodec (default), MediaCodec copy-back; H.265 if the SoC supports it |
| iOS / macOS | VideoToolbox (H.264, H.265 on A9+/2017+ Macs) |
| Windows | D3D11VA (default via *Automatic*), DXVA2, NVDEC |
| Linux | VA-API (Intel/AMD), NVDEC, VDPAU — *Automatic* picks one that works (Ubuntu test machine: `vaapi-copy`) |

*Automatic* falls back to software when no hardware decoder accepts the stream; the live
status (Settings → Video, full‑screen top bar) shows which decoder is in use. *Hardware
acceleration* off forces software decoding **and** rendering — use it if the picture is
green/black/corrupt on a particular GPU driver.

### 11.5 Configuring a stream

**RTSP camera** (SIYI, Herelink, IP cameras, companion computers):
1. Source *RTSP stream*, URL e.g. `rtsp://192.168.144.25:8554/main.264`.
2. Transport *TCP* unless the camera only offers UDP.
3. *Test connection* → "Video received in 1.2 s — H264 · 1280×720 · 30 fps · HW decode".

**UDP RTP from a companion computer** (the standard GCS setup), on the companion:
```bash
gst-launch-1.0 v4l2src ! videoconvert ! x264enc tune=zerolatency bitrate=2000 key-int-max=30 \
  ! rtph264pay config-interval=1 pt=96 ! udpsink host=<GCS IP> port=5600
# or with ffmpeg:
ffmpeg -f v4l2 -i /dev/video0 -c:v libx264 -tune zerolatency -g 30 -x264-params repeat-headers=1 \
  -f rtp rtp://<GCS IP>:5600
```
In APX FM: Source *UDP · RTP H.264*, port `5600`. `config-interval=1` / `repeat-headers=1`
(SPS/PPS in every keyframe) is required — the receiver has no SDP from the sender.

**MPEG‑TS over UDP**: `ffmpeg … -f mpegts udp://<GCS IP>:5600?pkt_size=1316`, Source *UDP · MPEG‑TS*.

Other settings:

| Setting | Default | Meaning |
|---|---|---|
| Connect automatically | on | start with the app / after settings changes |
| Reconnect when lost | on | delay (default 2 s) doubles per attempt up to 30 s; *Max attempts* 0 = forever |
| Stream timeout | 10 s | no first frame / no new frame for this long = lost (triggers reconnect) |
| Low latency | on | no buffering, frames shown as decoded (`untimed`, `nobuffer`); off = ~1 s buffer, smoother on bad links |
| Decoder, Hardware acceleration | Automatic, on | see §11.4 |
| Fit | Fit (letterbox) | never distorts; *Fill* crops, *Stretch* distorts |
| Aspect ratio | From stream | override for anamorphic cameras (16:9, 4:3, 21:9, 1:1) |
| Play audio | off | most drone cameras have no audio; off saves decoding |

Settings are saved immediately (`settings.json` in the app data folder, keys `video` and
`videoLayout`) and restored on start. Invalid values are shown next to the field and the
stream is not started until they are fixed.

### 11.6 Recording and snapshots

- **Record** (red dot) is available while video is playing; stop with the same button. The
  received stream is written as is (mpv `stream-record`): no re‑encoding, no quality loss,
  almost no CPU, and resolution/bitrate are whatever the camera sends. (Hence there are no
  resolution/quality settings for recordings — change those on the camera/encoder.)
- **Formats**: MKV (default; survives a crash or power loss), MP4 (default on iOS; needed for
  iOS Photos), MOV. MP4/MOV are finalised when recording stops — the app stops recording
  cleanly on *Exit* and when the desktop window is closed.
- If the stream drops while recording, the file is closed and recording continues in
  `…_part2.mkv` when the stream returns (*REC · waiting for video* meanwhile).
- **Snapshot** (camera icon) saves the current frame as JPEG next to the recordings.
- **Where files go** (Settings → Video → Recording shows the folder, free space and recent files,
  with open/delete; desktop: *Choose folder…*):

  | Platform | Default folder | Access |
  |---|---|---|
  | Windows | `%USERPROFILE%\Videos\APX Flight Manager` | Explorer (*Open folder*) |
  | Linux | XDG videos folder (`~/Videos`)`/APX Flight Manager` | file manager |
  | Android | app's Movies folder (`Android/data/com.apx.apx_flight_manager/files/Movies`) | *Copy to gallery* (default on) → Gallery/Photos, album "APX Flight Manager"; or USB |
  | iOS | app Documents `/Video` | Files app; *Copy to gallery* (default on, MP4/MOV only) → Photos |
  | macOS | app Documents `/Video` (sandbox) | Finder, or choose a folder |

- **Storage**: recording needs 500 MB free to start and stops by itself below 150 MB, with a
  message. *Storage limit* (MB, 0 = none) deletes the oldest `APX_*` recordings in the folder
  before a new one starts. A warning appears if the file stops growing (disk removed/full).
- Names: `APX_2026-11-07_14-03-22.mkv`, `…_part2.mkv`, `…_snapshot.jpg`.

### 11.7 Behaviour details

- **Reconnects**: connect timeout, stall (no frames), stream end and errors all lead to
  *Reconnecting* with back‑off; *Stop* is respected (no reconnect until *Start*).
- **Errors are explained**: refused connection, unknown host, unreachable network, timeout,
  wrong RTSP path (server answers but no video), 401 login, 404 path, unsupported RTSP
  transport, UDP port in use, unrecognised data.
- **Pause** freezes the picture; resuming within 2 s continues, later it rejoins the live edge
  (a paused live stream falls behind). Pausing is disabled while recording.
- **Phones/tablets in the background**: the stream stops (saves battery and data) unless it is
  recording, and restarts when the app returns.
- **Changing settings** restarts only when needed: source/latency/audio/timeout reconnect;
  decoder/hardware acceleration recreate the player (an active recording is stopped first);
  fit/aspect/recording options apply live.
- The screen is kept awake while video is shown.

### 11.8 Troubleshooting and known limitations

| Symptom | Try |
|---|---|
| *No video received within N s* on UDP | Is the sender pointed at this device's IP and port? Firewall (Windows prompt, `ufw`)? Only one program can bind a UDP port — close APX Flight Manager/VLC |
| Grey/green blocks for a second after connecting | Normal until the next keyframe; use a keyframe interval ≤ 1 s on the encoder |
| RTSP works in VLC but not here | Try Transport *UDP* or *Automatic*; check credentials in the URL |
| Green/black picture, or crash on one GPU | Decoder *Software*, or turn *Hardware acceleration* off |
| High latency | Low latency on; RTSP *UDP*; encoder `tune=zerolatency`, no B‑frames |
| Linux: *Video engine unavailable* | `sudo apt install libmpv1` (22.04) / `libmpv2` (24.04) |

Known limitations:
- **Native OS picture‑in‑picture** (Android PiP mode, iOS `AVPictureInPictureController`) is not
  used: media_kit renders into a Flutter texture, which the OS PiP APIs cannot take. The in‑app
  floating window is used on every platform; video stops when the app is backgrounded on
  mobile (unless recording).
- Recording copies the stream: no transcoding, overlays/OSD or resolution change; MP4/MOV
  written during a crash are unreadable (use MKV for safety).
- On iOS, *Copy to gallery* accepts MP4/MOV only (Photos rejects MKV).
- Android/iOS: the recording folder can't be changed (the app's own storage is used).
- Free-space checks use `statvfs` on 64-bit Linux/Android/iOS/macOS and `GetDiskFreeSpaceExW`
  on Windows; on 32-bit Android (armeabi-v7a) only the growth check runs.
- No MAVLink camera control or stream discovery (APX doesn't implement the camera protocol).
- One stream at a time.
- CPU (measured, Linux, Ubuntu 22.04, 12-thread laptop, Intel VA-API): a 720p30 7.6 Mbit/s
  H.264 stream adds about 0.65 of one core (~6 % of the machine), mostly media_kit's per-frame
  texture rendering; it is similar with software decoding. Stopping the video releases it.

### 11.9 What has been verified

| Platform | Build | Video tested |
|---|---|---|
| Linux x64 (Ubuntu 22.04, Flutter 3.47.9) | ✅ release build | ✅ in the app: RTP H.264 over UDP with VA‑API decode, PiP, swap, layouts, full screen (Esc), recording MKV/MP4 (validated with ffprobe), exit while recording (MP4 finalised), Settings page + Test connection, sender loss → reconnect. ✅ automated against the real engine: RTP H.264/H.265, MPEG‑TS/UDP, RTSP (VLC server, UDP transport), refused RTSP, silent UDP timeout, MKV/MP4 recording |
| Windows | ❌ not built (no Windows machine in this environment) | ❌ |
| Android | ❌ not built (no Android SDK in this environment) | ❌ |
| iOS | ❌ not built (needs macOS/Xcode) | ❌ |
| macOS | ❌ not built | ❌ |

Dart code is shared and analyzer-clean for all platforms; the platform-specific parts are the
media_kit native libraries (maintained upstream for each platform), permissions/manifest
entries (§11.3) and `Platform.is…` branches for storage, decoders and full screen. Build and
smoke‑test on each target before release: connect a stream, swap, full screen, record, stop,
play the file, background/foreground (mobile), and check the decoder shown in the status.

## 12. Tests

```bash
cd packages/apx_mavlink && dart test     # codec: firmware CRC table + pymavlink byte‑exact
cd packages/apx_link    && dart test     # transports
cd packages/apx_vehicle && dart test     # services + real APX SITL (tag: sitl)
cd packages/apx_geo     && dart test     # projections, China datums, overlays (±1 px at z19), tile cache/server
cd packages/apx_mission && dart test     # patterns, compiler, validator, files, resume + a mission flown in SITL (tag: sitl)
cd apps/flight_manager  && flutter test  # widgets, maps/overlays, Plan and Vehicle flows, video, Fly view against real SITL (tag: sitl)
```

The video tests in `apps/flight_manager/test/video/` run anywhere except those tagged `media`,
which stream through the real libmpv/FFmpeg engine with `ffmpeg` as the camera (RTP H.264/H.265,
MPEG‑TS, reconnect, refused RTSP, recording checked with `ffprobe`). They skip when libmpv or
ffmpeg is missing:
```bash
flutter test --tags media test/video/                       # needs libmpv + ffmpeg (libx264/libx265)
VIDEO_TEST_RTSP_URL=rtsp://127.0.0.1:8554/live \
  flutter test --tags media test/video/ --plain-name 'RTSP server'   # optional: against a live RTSP server
```

The `sitl` tests start `apx_flight_controller` and the physics runner from
`$APX_ROOT/build/sitl` (default `../apx`) on free ports, and skip if SITL isn't built.
To build SITL in the firmware repository: `cmake --preset sitl && cmake --build build/sitl -j$(nproc)`.

## 13. Regenerating generated code and fixtures

```bash
dart run tool/mavlink_gen/bin/generate.dart
dart format -l 120 packages/apx_mavlink/lib/src/generated
python3 tool/fixtures/make_pymavlink_fixtures.py   # needs pymavlink
python3 tool/fixtures/make_geo_fixtures.py         # needs pyproj pyshp Pillow numpy eviltransform
dart run tool/param_meta_gen/bin/generate.dart     # after APX changes its parameter table (APX_ROOT or ../apx)
```

## 14. Firmware workarounds

GCS workarounds for known APX firmware gaps are tagged `TODO(APX-FW-n)`, where `n`
is the item in `docs/02_ARCHITECTURE.md` §13:

```bash
grep -rn "TODO(APX-FW-" packages apps
```
