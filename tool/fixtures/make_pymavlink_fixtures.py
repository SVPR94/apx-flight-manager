# SPDX-License-Identifier: CC-BY-NC-4.0
# Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
# Author: Savita Pawar (SVPR94)
# Created: 2026
"""Writes MAVLink golden frames produced by pymavlink, for apx_mavlink tests.

Run from the repository root:
    python3 tool/fixtures/make_pymavlink_fixtures.py

Output: packages/apx_mavlink/test/fixtures/pymavlink_frames.json
"""
import json
import os

from pymavlink.dialects.v20 import apxmega as m

mav = m.MAVLink(None, srcSystem=1, srcComponent=1)
mav.robust_parsing = True

cases = [
    m.MAVLink_heartbeat_message(2, 3, 0x81, 3, 4, 3),
    m.MAVLink_sys_status_message(0x1003F, 0x1003F, 0x1003F, 250, 12600, 250, 95, 0, 0, 0, 0, 0, 0),
    m.MAVLink_attitude_message(123456, 0.1, -0.2, 2.35, 0.01, -0.02, 0.03),
    m.MAVLink_global_position_int_message(1000, 185204000, 738567000, 540000, 15000, 120, -40, 5, 13500),
    m.MAVLink_gps_raw_int_message(7002590, 3, 185203948, 738567131, 540784, 70, 97, 5, 65535, 18),
    m.MAVLink_vfr_hud_message(4.8, 4.8, 135, 0, 555.0, 0.2),
    m.MAVLink_param_value_message(b"WPNAV_SPEED", 500.0, 9, 153, 17),
    m.MAVLink_param_set_message(1, 1, b"RTL_ALT", 2000.0, 9),
    m.MAVLink_command_long_message(1, 1, 400, 0, 1, 21196, 0, 0, 0, 0, 0),
    m.MAVLink_command_ack_message(400, 0),
    m.MAVLink_mission_count_message(1, 1, 5, 0),
    m.MAVLink_mission_item_int_message(1, 1, 2, 6, 16, 0, 1, 0, 2.0, 0, 0, 185207000, 738567000, 10.0, 0),
    m.MAVLink_mission_request_int_message(255, 190, 3, 0),
    m.MAVLink_mission_ack_message(255, 190, 0, 0),
    m.MAVLink_highres_imu_message(7149824, -0.0335, 0.0766, -9.8195, -0.0021, 0.0011, -0.0032,
                                  0.3582, 0.0050, 0.1974, 950.0148, 0.0, 540.2872, 35.0, 7167, 3),
    m.MAVLink_wind_message(270.0, 3.1, 0.0),
    m.MAVLink_statustext_message(5, b"Mission upload complete"),
    m.MAVLink_set_position_target_global_int_message(1000, 1, 1, 6, 0x0FF8, 185210000, 738570000,
                                                    20.0, 0, 0, 0, 0, 0, 0, 0, 0),
    m.MAVLink_manual_control_message(1, 100, -200, 500, 0, 0),
]

frames = []
for seq, msg in enumerate(cases):
    mav.seq = seq
    raw = msg.pack(mav)
    frames.append({"name": msg.get_type(), "id": msg.get_msgId(), "seq": seq, "hex": raw.hex(),
                   "fields": {k: (v.decode() if isinstance(v, bytes) else v)
                              for k, v in msg.to_dict().items() if k != "mavpackettype"}})

out = "packages/apx_mavlink/test/fixtures/pymavlink_frames.json"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    json.dump(frames, f, indent=1)
print(f"wrote {len(frames)} frames to {out}")
