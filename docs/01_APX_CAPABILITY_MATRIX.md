# APX Firmware Capability Matrix

Source of truth for what APX Flight Manager may expose. Every row is backed by
firmware source (paths relative to `apx/`) and, where marked **[probed]**, by a
live MAVLink probe against the SITL build (`build/sitl/main/apx_flight_controller`,
firmware `VERSION` 0.1.0, commit `4fa6d34`).

Legend: **Yes** = implemented and observed working · **Stub** = accepted but does
nothing · **No** = not implemented (UNSUPPORTED or ignored) · **Dead code** =
module exists but is not linked into any running target.

---

## 1. Targets and transports

| Target | Entry point | MAVLink transport | State |
|---|---|---|---|
| SITL / Linux hosted | `main/apx_main.cpp` | UDP: binds `udp_port+1` (14551), streams to `127.0.0.1:udp_port` (14550), and also to any remote that sends to 14551. TCP servers on 5760–5763. | Fully functional (sensors simulated, modes fly) |
| Zephyr (Cube Orange+) | `platforms/zephyr/app/src/main.cpp` | USB CDC‑ACM serial only | Bring‑up: no sensors, no motors, arming refused with STATUSTEXT, notice every 60 s |
| STM32H7 bare metal (`apx_h743_v1`, `apx_h743_pro`, `custom_h7_fc`) | `platforms/stm32h7/boards/*/apx_main_stm32h7.cpp` | **None** (HAL backend empty; control math only) | No GCS link possible |

UART telemetry (`hwdef.dat`: USART2 @ 57600 "TELEM") is declared but not wired to
`MavlinkHandler` in any main. From the GCS side a UART radio and USB CDC are the
same thing — a serial port — so one Serial link covers both.

| Interface asked for | APX support | GCS decision |
|---|---|---|
| USB / Serial | Yes (Zephyr USB CDC) | Serial link (desktop + Android USB‑OTG) |
| UART radio (SiK/RFD) | Declared, not wired | Same Serial link; works once firmware wires it |
| UDP | Yes [probed] | UDP link: *listen* mode (local SITL) and *target* mode (remote vehicle: send to `host:14551` to register) |
| TCP | Yes [probed] | TCP client link (5760–5763) |
| Wi‑Fi | Not a firmware feature — it is UDP/TCP over IP | Covered by UDP/TCP links |
| Bluetooth | **No** | Not built. A classic‑BT SPP radio that shows up as an OS serial port works through the Serial link with no special code |
| MAVLink version | v2 out; parser accepts v1/v2 in [probed] | Speak v2 only; no signing (firmware has none) |

## 2. Identity

| Field | Value [probed] | Note |
|---|---|---|
| HEARTBEAT `autopilot` | `3` (APX_AUTOPILOT) | Dialect id — identifies autopilot dialect |
| HEARTBEAT `type` | 2/13/14 (quad/hex/octo) | from `--vehicle` |
| sysid / compid | 1 / 1 | `SYSID_THISMAV` param exists but is not applied |
| AUTOPILOT_VERSION | sent on TCP connect and on request; `flight_sw_version=0x00010000` (0.1.0), `vendor_id=0`, `product_id=0`, `capabilities=0xCB` (MISSION_FLOAT, PARAM_FLOAT, COMMAND_INT, SET_ATTITUDE_TARGET, SET_POSITION_TARGET_LOCAL_NED) | GCS identifies APX by version + parameter fingerprint (`WPNAV_BLEND`, `SPRAY_PUMP_RATE`) |

## 3. Telemetry streams (fixed rates, not configurable)

| Message | Rate [probed] | Content / caveat |
|---|---|---|
| HEARTBEAT | 1 Hz | mode, armed, system_status |
| SYS_STATUS | 2 Hz | sensor present/enabled/health bits; `load` fixed at 25 %; battery V/A/% |
| BATTERY_STATUS | 1 Hz | cell[0] = pack voltage; temperature fixed 25 °C; `current_consumed=-1` |
| ATTITUDE | 20 Hz | only when attitude estimate valid |
| GLOBAL_POSITION_INT | 10 Hz | only when position valid |
| VFR_HUD | 10 Hz | airspeed = groundspeed; **throttle always 0** (never set) |
| GPS_RAW_INT / GPS2_RAW | 5 Hz | receivers 1 and 2; fix, sats, eph/epv |
| HIGHRES_IMU | 10 Hz × lane | `id` = lane 0..3; accel/gyro/mag/baro/temp per redundant lane |
| SERVO_OUTPUT_RAW | 10 Hz | ch1–8 motors, ch9–16 aux (pump/spinner) |
| RC_CHANNELS | 10 Hz | **reconstructed from GCS overrides**, not a real receiver |
| WIND | 4 Hz | direction/speed/vertical |
| MISSION_CURRENT / MISSION_ITEM_REACHED | on change | progress while in AUTO |
| STATUSTEXT | event | mission upload, sprayer state, crash, arming refusal |
| COMMAND_ACK, PARAM_VALUE, MISSION_* | reply | |

Not sent: EXTENDED_SYS_STATE, EKF_STATUS_REPORT, VIBRATION,
RADIO_STATUS, SYSTEM_TIME, TIMESYNC. `SET_MESSAGE_INTERVAL` and
`REQUEST_DATA_STREAM` are not supported, so the GCS cannot change rates.

## 4. Commands (COMMAND_LONG and COMMAND_INT)

| Command | ID | Result [probed] | Behaviour / GCS rule |
|---|---|---|---|
| COMPONENT_ARM_DISARM | 400 | Yes | Refused if build blocks arming or mode `can_arm()` false. In‑air disarm refused unless p2 = 21196 (force) |
| DO_SET_MODE | 176 | Yes | p2 = custom mode. No GPS/EKF gating yet |
| SET_MODE (message) | 11 | Yes | no ACK |
| NAV_TAKEOFF | 22 | Yes | Requires armed; forces GUIDED; p7 = rel. alt (default 2 m) |
| NAV_LAND | 21 | Yes | Switches to LAND |
| DO_REPOSITION | 192 | Yes (GUIDED only) | p7 treated as **AMSL**; via COMMAND_INT lat/lon pass through float32 (~1 m loss) → GCS uses SET_POSITION_TARGET_GLOBAL_INT instead |
| MISSION_START | 300 | Yes | Requires armed; switches to AUTO; always starts at item 0 |
| DO_CHANGE_SPEED | 178 | Yes, types 0/1 only | Command: climb/descent types return UNSUPPORTED. Only effective in AUTO |
| DO_SET_SERVO | 183 | Yes | ch 9–16 drive aux outputs; ch 1–8 are overwritten by the mixer → GCS blocks 1–8 |
| DO_SPRAYER | 216 | Yes | DENIED when `SPRAY_ENABLE=0` |
| REQUEST_MESSAGE | 512 | AUTOPILOT_VERSION only | everything else UNSUPPORTED |
| REQUEST_AUTOPILOT_CAPABILITIES | 520 | Yes | |
| PREFLIGHT_CALIBRATION | 241 | **Stub** — ACK ACCEPTED, does nothing | calibration modules are dead code |
| DO_PARACHUTE | 208 | **Stub** — ACK ACCEPTED, does nothing | |
| NAV_RETURN_TO_LAUNCH | 20 | No | GCS triggers RTL via mode 6 |
| PREFLIGHT_STORAGE, PREFLIGHT_REBOOT_SHUTDOWN, DO_SET_HOME, DO_MOTOR_TEST, SET_MESSAGE_INTERVAL, DO_SET_MISSION_CURRENT | — | No (UNSUPPORTED) | not exposed |

## 5. Guided and manual control

| Input | Support | Notes |
|---|---|---|
| SET_POSITION_TARGET_GLOBAL_INT | Yes (GUIDED) | position only; frame RELATIVE_ALT or AMSL; precise (double) |
| SET_POSITION_TARGET_LOCAL_NED | Yes (GUIDED) | LOCAL_NED absolute position only |
| Velocity / acceleration setpoints | No | STATUSTEXT warning |
| MANUAL_CONTROL | Yes | x/y/z/r → sticks; **1 s timeout** → neutral |
| RC_CHANNELS_OVERRIDE | Yes | ch1–4 only |

## 6. Flight modes (custom_mode numbers)

| # | Mode | Firmware reality |
|---|---|---|
| 0 | STABILIZE | Yes |
| 2 | ALT_HOLD | Yes |
| 3 | AUTO | Yes — runs uploaded mission from item 0 |
| 4 | GUIDED | Yes |
| 5 | LOITER | Yes |
| 6 | RTL | Yes |
| 9 | LAND | Yes (forward braking + pilot reposition) |
| 16 | POS_HOLD | Instantiates **ModeLoiter** (alias) |
| 17 | BRAKE | Yes |
| 100 | AGRI_SPRAY | **Placeholder** — holds position only |
| 101 | AGRI_ZIGZAG | **Placeholder** — holds position only |

## 7. Mission protocol

| Aspect | Behaviour |
|---|---|
| Upload | MISSION_COUNT → firmware requests each item with MISSION_REQUEST_INT → MISSION_ACK + STATUSTEXT "Mission upload complete" [probed]. Out‑of‑order item → re‑requests expected seq. No firmware‑side timeout |
| Download | MISSION_REQUEST_LIST → MISSION_COUNT → MISSION_REQUEST_INT per item [probed] |
| Clear | MISSION_CLEAR_ALL → ACK |
| Item 0 | Skipped if NAV_WAYPOINT (treated as home marker). GCS always sends a home placeholder at seq 0 |
| Frames | GLOBAL_RELATIVE_ALT(_INT) = relative; GLOBAL(_INT) = AMSL; **anything else treated as AMSL** (no terrain frame) |
| Fence / rally | **Not supported, and buggy**: a request for mission_type 1/2 returns the *mission* count tagged type 0 [probed]; a fence upload would overwrite the mission. GCS never sends mission_type ≠ 0 |
| Set current item | No (no "jump to WP") |
| Persistence | RAM only — lost on reboot |
| Live update | Upload while in AUTO does **not** affect the running mission until AUTO is re‑entered |
| Resume | Re‑entering AUTO restarts from item 0 |

## 8. Mission commands APX executes

Only these ten commands do anything in `modules/modes/mode_auto.cpp`; any other
command is silently skipped at runtime. The planner exposes exactly these, with
exactly the parameters the firmware reads.

| Command | ID | Kind | Params the firmware reads | Notes |
|---|---|---|---|---|
| NAV_WAYPOINT | 16 | nav | p2 acceptance radius m (0 → `WPNAV_RADIUS`); lat/lon/alt | **p1 hold, p3 pass radius, p4 yaw ignored** (README is wrong). Fly‑through corner blending when next nav item is also a waypoint |
| NAV_TAKEOFF | 22 | nav | alt | Vertical climb at current position; lat/lon ignored |
| NAV_LAND | 21 | nav | lat/lon | Flies level to point, then descends; **lat/lon 0 → lands at HOME**. Disarms on touchdown |
| NAV_RETURN_TO_LAUNCH | 20 | nav | — | Climb to max(current, `RTL_ALT`), fly home, land |
| CONDITION_CHANGE_ALT | 113 | blocking | p1 rate m/s (0 → WPNAV_SPEED_UP/DN); alt | Holds horizontal position until within 0.5 m |
| CONDITION_YAW | 115 | blocking | p1 angle deg, p2 rate deg/s (0 → 30), p3 dir −1/0/1, p4 relative 0/1 | Holds position; **locks heading for later legs** |
| DO_CHANGE_SPEED | 178 | instant | p1 type 0/1 horizontal, 2 climb, 3 descent; p2 m/s (−2 = reset); max 20 m/s | |
| DO_SET_SERVO | 183 | instant | p1 channel, p2 PWM 800–2200 | **Only the sprayer pump/spinner channels have an effect in a mission** |
| DO_CHANGE_ALTITUDE | 186 | instant | p1 alt (or z) | |
| DO_SPRAYER | 216 | instant | p1 0/1 | Speed‑proportional pump scheduler |

## 9. Parameters

| Aspect | Behaviour [probed] |
|---|---|
| Count | 153 (84 INT32 type 6, 69 REAL32 type 9) |
| Encoding | Float‑cast (PARAM_FLOAT capability), **not** byte‑wise |
| Order | `unordered_map` iteration — stable within a session only; key by name, never by index |
| Unknown name in PARAM_SET | Silence (no PARAM_VALUE) → GCS times out and reports |
| Out of range | Silently **clamped** to min/max, echo shows clamped value → GCS must compare and warn |
| Metadata | name, type, default, min, max, description in `modules/params/param_manager.cpp` → GCS generates its metadata table from this file |
| Persistence | **None** — `save_to_storage()` / `load_from_storage()` are stubs; values reset on reboot |
| Wired but unused | `FS_THR_ENABLE`, `FS_GCS_ENABLE`, `ARMING_CHECK`, `RCMAP_*`, `BATT_*`, `SYSID_THISMAV` are registered but no running code enforces them |

## 10. Not available (do not build UI for these)

Onboard log download (no LOG_* / FTP), sensor calibration, motor test, reboot,
geofence, rally points, camera / gimbal / ADS‑B,
terrain following, MAVLink signing, real RC receiver calibration (RC_CHANNELS
only echoes GCS overrides).

## 11. README vs. code discrepancies

| README claim | Code reality |
|---|---|
| Parameters stored in non‑volatile flash | Storage functions are stubs |
| NAV_WAYPOINT p1 hold / p3 / p4 yaw | Only p2 is read |
| DJI‑style guided calibration via MAV_CMD_PREFLIGHT_CALIBRATION | Command is an ACK‑only stub; `modules/calibration` is not linked |
| AGRI_SPRAY / AGRI_ZIGZAG modes | Hold position only |
| Failsafes (RC, GCS, battery) | `modules/safety` not linked |
| UART telemetry on hardware | Only Zephyr USB CDC runs MAVLink |
| `tools/apx_param.py export` | Writes fixed mock names, not the vehicle's parameters |
| SYS_STATUS reports battery | Bit 4 set is DIFFERENTIAL_PRESSURE; battery bit (25) not set |
