# APX Flight Manager — UI Concept: "Alloy"

Status: **proposal, awaiting approval**. A visual mock‑up accompanies this document.

## 1. Intent

A ground station that feels like a precision instrument rather than a dashboard of
widgets. The map is the canvas; instruments float above it as machined, frosted
aluminium panels. Calm by default, loud only when something needs the pilot.

Deliberately different from existing stations:

| Common GCS pattern | Alloy instead |
|---|---|
| Tab bar of screens with a fixed instrument panel | Map‑first canvas; panels float and collapse; one sidebar for the five spaces |
| Full PFD clone | Compact **Cockpit Cluster**: attitude sphere ringed by heading, slim speed and altitude tapes |
| Mode dropdown | **Mode Ring**: radial picker grouped Manual / Assisted / Autonomous |
| Click‑to‑confirm critical actions | **Slide‑to‑confirm** for arm, takeoff, land, RTL and force disarm |
| Message list in a corner | **Notification Capsule** that drops from the Status Rail, with an alert history |
| Waypoint table | **Mission Timeline**: item chips under a live altitude profile, synchronised with the map |

## 2. Design language

**Materials**: two surface types only.
- *Glass*: 72 % tint with 24 px backdrop blur, 1 px top highlight and a soft long
  shadow. Used for anything floating over the map.
- *Plate*: opaque brushed‑silver gradient for full‑screen workspaces (Vehicle, Logs,
  Settings).

**Themes** (both silver/grey):
- *Alloy Silver* (default, daylight): silver canvas `#E6E8EB`, plates `#F4F5F7`, graphite
  ink `#1D1F23`, secondary ink `#5E636B`, hairlines `#C9CDD3`.
- *Alloy Graphite* (night): canvas `#16181B`, plates `#1E2125`, hairlines `#33373D`,
  ink `#ECEEF1`, secondary `#A3A9B1`.

**Colour discipline**:
- One accent, *Signal Teal*: `#0E9AA7` for fills (selection, focus, your own route)
  and `#0B7C87` for teal text (4.9:1 on white).
- Status colours are reserved for status: OK `#2FA36B`, Caution `#D99A1E`, Warning
  `#E0622B`, Critical `#D93A3A`. They never decorate.

**Typography**:
- *Inter* for UI text, sizes 11 / 13 / 15 / 20 / 28 / 40.
- *JetBrains Mono* with tabular figures for every live number, so digits don't jitter.
- Both fonts are bundled for offline field use.

**Geometry**:
- 4‑pt spacing grid.
- Radii: 8 for controls, 14 for panels, 22 for capsules.
- 44 px minimum touch target; 56 px in *Field mode* (gloves, tablets in sun).

**Icons**:
- Lucide line icons at 1.75 px stroke.
- A custom aviation set drawn to match: quad/hex/octo vehicle glyphs, takeoff, land,
  RTL, waypoint, condition, sprayer, home.

**Motion**:
- 180 ms for state changes and 280 ms for panels, both with an emphasised‑decelerate
  curve.
- The vehicle glyph and instruments interpolate between telemetry samples so 10–20 Hz
  data looks continuous.
- Reduced‑motion setting respected.

## 3. Shell

```
┌────┬──────────────────────────────────────────────────────────────┐
│ ◉  │            ┌────────── Status Rail ──────────┐               │
│Fly │            │ LOITER ▾ │ ARMED │ ▂▄▆ │ 18 sat │ 12.4V 78% │  │
│Plan│            └─────────────────────────────────┘               │
│Veh │                                                              │
│Logs│                         MAP CANVAS                           │
│    │                                                              │
│ ⚙  │ ┌──Cockpit Cluster──┐                          ┌─Action──┐   │
│ ●  │ │ spd │ (◐ADI) │ alt │                          │ ▶ slide │   │
│link│ └───────────────────┘                          └─────────┘   │
└────┴──────────────────────────────────────────────────────────────┘
```

- **Sidebar dock**: Fly, Plan, Vehicle, Logs and Settings; the link indicator sits at
  the foot. Collapses to 64 px.
- **Status Rail**: a glass capsule, top centre. Holds Mode (opens the Mode Ring), arm
  state, link quality, GPS, battery and flight timer. Each pill opens a detail
  popover: GPS opens both receivers, battery opens V/A/%/thresholds.
- **Notification Capsule**: grows out of the rail for STATUSTEXT and alerts, tinted
  by severity. Critical alerts stay until acknowledged. History lives in a sheet.

## 4. Fly

- **Cockpit Cluster** (bottom‑left glass):
  - An attitude sphere with a heading ring around its rim.
  - Ground‑speed tape on the left, relative‑altitude tape on the right, vertical speed
    as a bar inside the altitude tape.
  - Wind arrow on the heading ring.
  - Can be collapsed to a single "numbers" row.
- **Map**:
  - Vehicle glyph matching the frame (quad/hex/octo) with heading, and a fading trail.
  - The home marker follows the vehicle's HOME_POSITION; *Set home* (map long‑press or the drone's position) moves the point RTL returns to.
  - Mission path coloured by altitude; current item haloed.
  - Long‑press the map for *Fly here* in GUIDED; a target ring and an altitude chip
    appear.
- **Action Stack** (bottom‑right):
  - Contextual: Arm when disarmed; Takeoff (altitude dial) in GUIDED on the ground;
    Start Mission when a valid mission is on the vehicle; Brake, Land and RTL in the
    air.
  - Sprayer toggle when `SPRAY_ENABLE` = 1.
  - Every action is slide‑to‑confirm.
- **Mode Ring**: shows only the modes the firmware profile marks as real. POS_HOLD
  carries an "alias of LOITER" caption. The APX 0.1 placeholder modes are hidden.
- **Telemetry Drawer** (right edge): a customisable grid of tiles (any snapshot field,
  units, thresholds) and a mini sensor‑lane strip.

## 5. Plan

- Map with drawing tools: add waypoint, polygon (for Spray Survey), measure.
- **Mission Timeline** (bottom glass):
  - An altitude profile across the top: AGL line, vehicle `RTL_ALT` reference, terrain
    left out (APX has no terrain frame).
  - Item chips underneath, coloured by kind: nav, condition, action.
  - Drag a chip to reorder; selecting a chip selects it on the map, and vice versa.
- **Inspector** (right sheet) for the selected item:
  - Only the parameters APX reads, with units and a one‑line "vehicle will…"
    explanation.
  - Validation messages inline; errors block upload.
- **Sync chip** (top): *On vehicle ✓ / Differs / Not uploaded*, with Upload and
  Download. A banner explains that a running AUTO isn't changed by an upload.
- **Spray Survey sheet**: spacing, angle (with an on‑map angle handle), overshoot,
  start corner, speed, altitude. Shows a live swath preview with area, distance, time
  and the number of sprayer toggles.

## 6. Vehicle

The plate surface, with a secondary rail for Summary, Parameters, Setup, Diagnostics
and Inspector.
- **Parameters**: a dense, keyboard‑friendly table with inline edit, a range bar and a
  default marker. The "clamped by vehicle" and "not persisted on APX 0.1" banners come
  from the profile.
- **Diagnostics → Sensor Lanes**: four columns (IMU 0–3) of accel/gyro/mag/baro
  sparklines plus a spread meter, showing APX's 4‑way redundancy directly.

## 7. Logs

- **Library**: cards with a track thumbnail, date, duration, max altitude and alerts.
- **Analysis**:
  - Timeline scrubber at the bottom, a map track in sync, and stacked plots with a
    shared cursor.
  - Event pins for mode changes, arming and STATUSTEXT.
  - Any analysis can be replayed into the Fly view.

## 8. Accessibility and field use

- Contrast ≥ 4.5:1 for text in both themes.
- Status is never colour‑only: every status has an icon and a word.
- Field mode: larger targets, no hover‑only affordances, sunlight‑boosted contrast on
  the Silver theme.
- Spoken alerts (optional) for critical events.
