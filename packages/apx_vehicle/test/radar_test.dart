// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:math' as math;

import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:test/test.dart';

void main() {
  group('UART Radar Driver', () {
    test('parses standard 9-byte packet correctly', () {
      final parser = UartRadarParser();
      double? receivedDist;
      int? receivedQuality;
      bool? receivedValid;

      // 150 cm = 1.50m, strength = 850 (quality = 85%), tempRaw = 2248 (~25°C)
      final packet = UartRadarParser.encodePacket(
        distCm: 150,
        strength: 850,
        tempRaw: 2248,
      );

      parser.parseBytes(packet, (dist, quality, valid) {
        receivedDist = dist;
        receivedQuality = quality;
        receivedValid = valid;
      });

      expect(receivedDist, closeTo(1.50, 1e-3));
      expect(receivedQuality, equals(85));
      expect(receivedValid, isTrue);
    });

    test('calculates signal quality and clamps between 0 and 100', () {
      final parser = UartRadarParser();
      int? quality;

      // Strength 50 -> quality 5
      parser.parseBytes(
        UartRadarParser.encodePacket(distCm: 100, strength: 50),
        (dist, q, valid) => quality = q,
      );
      expect(quality, equals(5));

      // Strength 1500 -> quality 100 (clamped)
      parser.parseBytes(
        UartRadarParser.encodePacket(distCm: 100, strength: 1500),
        (dist, q, valid) => quality = q,
      );
      expect(quality, equals(100));
    });

    test('flags low strength or zero distance as invalid', () {
      final parser = UartRadarParser();
      bool? valid;

      // Distance 0 -> invalid
      parser.parseBytes(
        UartRadarParser.encodePacket(distCm: 0, strength: 500),
        (dist, q, v) => valid = v,
      );
      expect(valid, isFalse);

      // Strength <= 100 -> invalid
      parser.parseBytes(
        UartRadarParser.encodePacket(distCm: 100, strength: 90),
        (dist, q, v) => valid = v,
      );
      expect(valid, isFalse);
    });

    test('rejects packet with corrupt checksum', () {
      final parser = UartRadarParser();
      var called = false;

      final packet = UartRadarParser.encodePacket(distCm: 200, strength: 600);
      // Invalidate checksum byte (last byte)
      packet[8] = (packet[8] + 1) & 0xFF;

      parser.parseBytes(packet, (dist, q, v) {
        called = true;
      });

      expect(called, isFalse);
    });

    test('rejects packet with corrupt payload byte', () {
      final parser = UartRadarParser();
      var called = false;

      final packet = UartRadarParser.encodePacket(distCm: 200, strength: 600);
      // Corrupt distance byte without updating checksum
      packet[2] = (packet[2] ^ 0xFF) & 0xFF;

      parser.parseBytes(packet, (dist, q, v) {
        called = true;
      });

      expect(called, isFalse);
    });

    test('handles streaming byte-by-byte fragmentation', () {
      final parser = UartRadarParser();
      final readings = <double>[];

      final packet = UartRadarParser.encodePacket(distCm: 320, strength: 700);

      // Feed 1 byte at a time
      for (final byte in packet) {
        parser.parseBytes([byte], (dist, q, v) {
          readings.add(dist);
        });
      }

      expect(readings.length, equals(1));
      expect(readings.first, closeTo(3.20, 1e-3));
    });

    test('recovers from noisy byte stream and garbage prefixes', () {
      final parser = UartRadarParser();
      final distances = <double>[];

      final noisyBytes = [
        0x00, 0xFF, 0x59, 0x12, 0x34, // Garbage with false single header
        0x59, 0x00, // another false header
        ...UartRadarParser.encodePacket(distCm: 120, strength: 500), // Valid packet 1
        0xAA, 0xBB, // Noise between packets
        ...UartRadarParser.encodePacket(distCm: 240, strength: 600), // Valid packet 2
      ];

      parser.parseBytes(noisyBytes, (dist, q, v) {
        distances.add(dist);
      });

      expect(distances.length, equals(2));
      expect(distances[0], closeTo(1.20, 1e-3));
      expect(distances[1], closeTo(2.40, 1e-3));
    });

    test('emits decoded packets over readings broadcast stream', () async {
      final parser = UartRadarParser();
      final packetList = <UartRadarPacket>[];
      final sub = parser.readings.listen(packetList.add);

      final packetBytes = UartRadarParser.encodePacket(
        distCm: 215,
        strength: 950,
        tempRaw: 2248,
      );

      parser.parseBytes(packetBytes, (_, __, ___) {});
      await Future<void>.delayed(Duration.zero);

      expect(packetList.length, equals(1));
      expect(packetList.first.distanceM, closeTo(2.15, 1e-3));
      expect(packetList.first.strength, equals(950));
      expect(packetList.first.signalQuality, equals(95));
      expect(packetList.first.valid, isTrue);

      await sub.cancel();
      await parser.dispose();
    });
  });

  group('CAN Radar Driver', () {
    test('parses valid CAN frame for sector 0 through 9', () {
      final parser = CanRadarParser(baseCanId: 0x200);

      for (var sector = 0; sector < 10; sector++) {
        var parsed = false;
        final frame = CanRadarParser.encodeFrame(
          baseCanId: 0x200,
          sector: sector,
          distCm: 100 + sector * 10,
          angleDeg: sector * 36,
          quality: 90,
        );

        final accepted = parser.parseFrame(frame, (sec, dist, angle, quality) {
          parsed = true;
          expect(sec, equals(sector));
          expect(dist, closeTo((100 + sector * 10) * 0.01, 1e-3));
          expect(angle, equals(sector * 36));
          expect(quality, equals(90));
        });

        expect(accepted, isTrue);
        expect(parsed, isTrue);
      }
    });

    test('rejects CAN frame with ID outside range', () {
      final parser = CanRadarParser(baseCanId: 0x200);
      var called = false;

      // ID 0x1FF (one below base)
      final acceptedLow = parser.parseFrame(
        const CanRadarFrame(0x1FF, [0x00, 0x01, 0x00, 0x00], 4),
        (_, __, ___, ____) => called = true,
      );
      expect(acceptedLow, isFalse);
      expect(called, isFalse);

      // ID 0x20A (one above sector 9)
      final acceptedHigh = parser.parseFrame(
        const CanRadarFrame(0x20A, [0x00, 0x01, 0x00, 0x00], 4),
        (_, __, ___, ____) => called = true,
      );
      expect(acceptedHigh, isFalse);
      expect(called, isFalse);
    });

    test('rejects CAN frame with DLC < 4', () {
      final parser = CanRadarParser(baseCanId: 0x200);
      var called = false;

      final accepted = parser.parseFrame(
        const CanRadarFrame(0x200, [0x50, 0x00, 0x00], 3),
        (_, __, ___, ____) => called = true,
      );

      expect(accepted, isFalse);
      expect(called, isFalse);
    });

    test('defaults quality to 100 when DLC == 4', () {
      final parser = CanRadarParser(baseCanId: 0x200);
      int? quality;

      final accepted = parser.parseFrame(
        const CanRadarFrame(0x200, [150, 0, 45, 0], 4),
        (sec, dist, angle, q) => quality = q,
      );

      expect(accepted, isTrue);
      expect(quality, equals(100));
    });

    test('emits decoded CAN readings over stream', () async {
      final parser = CanRadarParser();
      final readings = <CanRadarReading>[];
      final sub = parser.readings.listen(readings.add);

      final frame = CanRadarParser.encodeFrame(
        sector: 3,
        distCm: 450,
        angleDeg: 90,
        quality: 80,
      );

      parser.parseFrame(frame, (_, __, ___, ____) {});
      await Future<void>.delayed(Duration.zero);

      expect(readings.length, equals(1));
      expect(readings.first.sector, equals(3));
      expect(readings.first.distanceM, closeTo(4.50, 1e-3));
      expect(readings.first.angleDeg, equals(90));
      expect(readings.first.signalQuality, equals(80));
      expect(readings.first.valid, isTrue);

      await sub.cancel();
      await parser.dispose();
    });
  });

  group('Multi-Instance Radar Concurrency', () {
    test('initializes exactly 10 independent channels (>= 9 required)', () {
      final radar = RadarState();
      expect(RadarState.channelCount, equals(10));
      expect(radar.channels.length, equals(10));

      // Channel 0: Downward (rotPitch270 = 25)
      expect(radar.downward.channel, equals(0));
      expect(radar.downward.orientation, equals(MavSensorOrientation.mavSensorRotationPitch270));

      // Channels 1..8: 360° horizontal ring at 45° azimuth steps
      for (var i = 0; i < 8; i++) {
        final ch = radar.channels[i + 1];
        expect(ch.channel, equals(i + 1));
        expect(ch.angleDeg, equals(i * 45));
      }

      // Channel 9: Top (rotPitch90 = 24)
      expect(radar.top.channel, equals(9));
      expect(radar.top.orientation, equals(MavSensorOrientation.mavSensorRotationPitch90));
    });

    test('all 10 instances update concurrently without crosstalk', () {
      final radar = RadarState();
      final now = DateTime.now();

      for (var ch = 0; ch < 10; ch++) {
        radar.updateSensor(
          ch,
          distanceM: 1.0 + ch * 0.5,
          quality: 50 + ch * 5,
          valid: true,
          healthy: true,
          timestamp: now.add(Duration(milliseconds: ch)),
        );
      }

      expect(radar.activeSensorCount, equals(10));

      for (var ch = 0; ch < 10; ch++) {
        final sensor = radar.channels[ch];
        expect(sensor.distanceM, closeTo(1.0 + ch * 0.5, 1e-3));
        expect(sensor.signalQuality, equals(50 + ch * 5));
        expect(sensor.healthy, isTrue);
        expect(sensor.valid, isTrue);
        expect(sensor.isExpired(now.add(const Duration(milliseconds: 100))), isFalse);
      }
    });

    test('detects channel measurement expiration on timeout', () {
      final radar = RadarState();
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

      radar.updateSensor(
        RadarState.channelFront,
        distanceM: 5.0,
        quality: 80,
        valid: true,
        healthy: true,
        timestamp: t0,
      );

      final sensor = radar.forward;
      expect(sensor.isExpired(t0.add(const Duration(milliseconds: 200))), isFalse);
      expect(sensor.isExpired(t0.add(const Duration(milliseconds: 600))), isTrue);
    });
  });

  group('Downward Terrain Follow & Tilt Compensation', () {
    test('level flight (roll=0, pitch=0) gives vz=1.0 and exact ground clearance', () {
      final follower = TerrainFollower(maxTiltDeg: 35.0, targetClearanceM: 2.0);

      final vz = TerrainFollower.computeVz(0.0, 0.0);
      final tilt = TerrainFollower.computeTiltDeg(vz);

      expect(vz, closeTo(1.0, 1e-6));
      expect(tilt, closeTo(0.0, 1e-6));

      // Current vehicle altitude 100m MSL, downward distance 5m
      final targetAlt = follower.adjustAltitude(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 5.0,
        isHealthy: true,
      );

      // Raw terrain MSL = 100 - 5 = 95m. Target clearance 2m -> targetAlt = 97m.
      expect(follower.lastGroundClearanceM, closeTo(5.0, 1e-3));
      expect(follower.terrainElevationMsl, closeTo(95.0, 1e-3));
      expect(targetAlt, closeTo(97.0, 1e-3));
      expect(follower.tiltGated, isFalse);
    });

    test('pitch 30 deg projects vertical clearance correctly', () {
      final follower = TerrainFollower(maxTiltDeg: 35.0, targetClearanceM: 3.0);
      final pitch30Rad = 30.0 * math.pi / 180.0;

      final vz = TerrainFollower.computeVz(0.0, pitch30Rad);
      final expectedVz = math.cos(pitch30Rad); // ~0.866025
      expect(vz, closeTo(expectedVz, 1e-4));

      final tiltDeg = TerrainFollower.computeTiltDeg(vz);
      expect(tiltDeg, closeTo(30.0, 1e-3));
      expect(tiltDeg <= 35.0, isTrue);

      follower.adjustAltitude(
        currentAltMsl: 50.0,
        rollRad: 0.0,
        pitchRad: pitch30Rad,
        rawDistanceM: 10.0,
        isHealthy: true,
      );

      // Slant distance 10m -> vertical AGL = 10 * cos(30°) = 8.66m
      expect(follower.lastGroundClearanceM, closeTo(10.0 * expectedVz, 1e-3));
      // Terrain MSL = 50 - 8.66 = 41.34m
      expect(follower.terrainElevationMsl, closeTo(50.0 - (10.0 * expectedVz), 1e-3));
      expect(follower.tiltGated, isFalse);
    });

    test('combined roll and pitch under 35 deg maintains active tracking', () {
      final follower = TerrainFollower(maxTiltDeg: 35.0);
      final roll20 = 20.0 * math.pi / 180.0;
      final pitch20 = 20.0 * math.pi / 180.0;

      final vz = TerrainFollower.computeVz(roll20, pitch20);
      final tilt = TerrainFollower.computeTiltDeg(vz);

      // vz = cos(20°)*cos(20°) ≈ 0.88302
      // acos(0.88302) ≈ 27.99°
      expect(tilt, closeTo(27.99, 0.1));
      expect(tilt < 35.0, isTrue);

      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: roll20,
        pitchRad: pitch20,
        rawDistanceM: 10.0,
        isHealthy: true,
      );

      expect(follower.tiltGated, isFalse);
      expect(follower.isInitialized, isTrue);
    });

    test('tilt gating activates above 35 deg and freezes terrain elevation updates', () {
      final follower = TerrainFollower(maxTiltDeg: 35.0, targetClearanceM: 2.0);

      // Initial sample in level flight: Alt MSL 100, Dist 5 -> Ground MSL 95
      follower.adjustAltitude(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 5.0,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, closeTo(95.0, 1e-3));
      expect(follower.tiltGated, isFalse);

      // Bank to 40 deg (> 35 deg max tilt)
      final roll40 = 40.0 * math.pi / 180.0;
      final targetAltGated = follower.adjustAltitude(
        currentAltMsl: 100.0,
        rollRad: roll40,
        pitchRad: 0.0,
        rawDistanceM: 8.0, // slanted distance increased
        isHealthy: true,
      );

      expect(follower.tiltGated, isTrue);
      // Terrain elevation MUST be frozen at 95.0
      expect(follower.terrainElevationMsl, closeTo(95.0, 1e-3));
      // Target altitude based on frozen ground: 95.0 + 2.0 = 97.0
      expect(targetAltGated, closeTo(97.0, 1e-3));

      // Level out: tilt drops below 35 deg, updates resume
      follower.adjustAltitude(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 6.0,
        isHealthy: true,
      );
      expect(follower.tiltGated, isFalse);
    });

    test('terrain smoothing filters noisy elevation changes smoothly', () {
      final follower = TerrainFollower(
        maxTiltDeg: 35.0,
        targetClearanceM: 2.0,
        smoothingAlpha: 0.2,
      );

      // First sample at 100m MSL, 10m AGL -> ground at 90m
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 10.0,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, closeTo(90.0, 1e-3));

      // Step change in ground: AGL drops to 5m (ground rose to 95m)
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 5.0,
        isHealthy: true,
      );

      // Filter: 90.0 + 0.2 * (95.0 - 90.0) = 91.0m
      expect(follower.terrainElevationMsl, closeTo(91.0, 1e-3));

      // Second step: 91.0 + 0.2 * (95.0 - 91.0) = 91.8m
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 5.0,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, closeTo(91.8, 1e-3));
    });

    test('rejects infinite distance and altitude without corrupting terrain elevation', () {
      final follower = TerrainFollower();
      // Initialize with a valid sample at 100m MSL, 10m AGL -> ground at 90m
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 10.0,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, equals(90.0));
      expect(follower.isInitialized, isTrue);

      // Rejection of rawDistanceM = double.infinity
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: double.infinity,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, equals(90.0));
      expect(follower.terrainElevationMsl.isFinite, isTrue);
      expect(follower.terrainElevationMsl.isInfinite, isFalse);

      // Rejection of rawDistanceM = double.negativeInfinity
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: double.negativeInfinity,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, equals(90.0));

      // Rejection of currentAltMsl = double.infinity
      follower.updateTerrain(
        currentAltMsl: double.infinity,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 10.0,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, equals(90.0));
      expect(follower.terrainElevationMsl.isFinite, isTrue);

      // Rejection of currentAltMsl = double.negativeInfinity
      follower.updateTerrain(
        currentAltMsl: double.negativeInfinity,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 10.0,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, equals(90.0));

      // Verification that subsequent updates after invalid/infinite inputs operate normally and never produce NaN or Infinity
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 15.0,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl.isFinite, isTrue);
      expect(follower.terrainElevationMsl.isNaN, isFalse);
      expect(follower.terrainElevationMsl.isInfinite, isFalse);
      // Filter: 90.0 + 0.2 * (85.0 - 90.0) = 89.0
      expect(follower.terrainElevationMsl, closeTo(89.0, 1e-3));

      final adjustedAlt = follower.adjustAltitude(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 15.0,
        isHealthy: true,
      );
      expect(adjustedAlt.isFinite, isTrue);
      expect(adjustedAlt.isNaN, isFalse);
      expect(adjustedAlt.isInfinite, isFalse);
    });

    test('rejects NaN and non-finite attitude with tilt gating (lastTiltDeg is 90.0, tiltGated is true)', () {
      final follower = TerrainFollower();
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 10.0,
        isHealthy: true,
      );
      expect(follower.terrainElevationMsl, equals(90.0));
      expect(follower.tiltGated, isFalse);
      expect(follower.lastTiltDeg, equals(0.0));

      // Test rollRad = double.nan attitude rejection / tilt gating
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: double.nan,
        pitchRad: 0.0,
        rawDistanceM: 10.0,
        isHealthy: true,
      );
      expect(follower.tiltGated, isTrue);
      expect(follower.lastTiltDeg, equals(90.0));
      expect(follower.terrainElevationMsl, equals(90.0));

      // Test pitchRad = double.nan attitude rejection / tilt gating
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: double.nan,
        rawDistanceM: 10.0,
        isHealthy: true,
      );
      expect(follower.tiltGated, isTrue);
      expect(follower.lastTiltDeg, equals(90.0));
      expect(follower.terrainElevationMsl, equals(90.0));

      // Test computeVz and computeTiltDeg directly on NaN / non-finite inputs
      expect(TerrainFollower.computeVz(double.nan, 0.0), equals(0.0));
      expect(TerrainFollower.computeVz(0.0, double.nan), equals(0.0));
      expect(TerrainFollower.computeVz(double.infinity, 0.0), equals(0.0));
      expect(TerrainFollower.computeVz(0.0, double.infinity), equals(0.0));

      expect(TerrainFollower.computeTiltDeg(0.0), equals(90.0));
      expect(TerrainFollower.computeTiltDeg(double.nan), equals(90.0));
      expect(TerrainFollower.computeTiltDeg(double.infinity), equals(90.0));

      // Subsequent valid update after NaN attitude recovers and operates normally
      follower.updateTerrain(
        currentAltMsl: 100.0,
        rollRad: 0.0,
        pitchRad: 0.0,
        rawDistanceM: 10.0,
        isHealthy: true,
      );
      expect(follower.tiltGated, isFalse);
      expect(follower.lastTiltDeg, equals(0.0));
      expect(follower.terrainElevationMsl, equals(90.0));
      expect(follower.terrainElevationMsl.isFinite, isTrue);
      expect(follower.terrainElevationMsl.isNaN, isFalse);
    });

    test('RadarSensorData invalidates non-finite and infinite distance measurements', () {
      final sensor = RadarSensorData(channel: 0);

      sensor.update(distance: double.infinity, quality: 90);
      expect(sensor.valid, isFalse);

      sensor.update(distance: double.negativeInfinity, quality: 90);
      expect(sensor.valid, isFalse);

      sensor.update(distance: double.nan, quality: 90);
      expect(sensor.valid, isFalse);

      sensor.update(distance: 0.0, quality: 90);
      expect(sensor.valid, isFalse);

      sensor.update(distance: -1.0, quality: 90);
      expect(sensor.valid, isFalse);

      sensor.update(distance: 5.5, quality: 90);
      expect(sensor.valid, isTrue);
      expect(sensor.distanceM, equals(5.5));
    });
  });

  group('TelemetryStore Radar Integration', () {
    test('ingests MAVLink DistanceSensor into VehicleSnapshot.radar', () {
      final store = TelemetryStore();
      final now = DateTime.utc(2026, 11, 15, 12, 0, 0);

      // Send attitude and altitude first so terrain follow has vehicle state
      store.apply(
        const Attitude(
          timeBootMs: 1000,
          roll: 0.0,
          pitch: 0.0,
          yaw: 0.0,
          rollspeed: 0.0,
          pitchspeed: 0.0,
          yawspeed: 0.0,
        ),
        now: now,
      );

      store.apply(
        const GlobalPositionInt(
          timeBootMs: 1000,
          lat: 377749000,
          lon: -1224194000,
          alt: 150000, // 150m MSL
          relativeAlt: 20000, // 20m AGL
          vx: 0,
          vy: 0,
          vz: 0,
          hdg: 0,
        ),
        now: now,
      );

      // Ingest Downward radar (instanceId = 0, orientation = rotPitch270 = 25)
      // currentDistance = 1500 cm = 15.0m
      final distMsg = DistanceSensor(
        timeBootMs: 1000,
        minDistance: 50,
        maxDistance: 5000,
        currentDistance: 1500,
        type: MavDistanceSensor.radar,
        instanceId: 0,
        orientation: MavSensorOrientation.mavSensorRotationPitch270,
        covariance: 0,
        signalQuality: 90,
      );

      store.apply(distMsg, now: now);

      final snapshot = store.snapshot;
      final downRadar = snapshot.radar.downward;

      expect(downRadar.healthy, isTrue);
      expect(downRadar.valid, isTrue);
      expect(downRadar.distanceM, closeTo(15.0, 1e-3));
      expect(downRadar.signalQuality, equals(90));

      // Downward terrain follow should be active
      expect(snapshot.radar.isTerrainActive, isTrue);
      expect(snapshot.radar.downwardTerrainClearanceM, closeTo(15.0, 1e-3));
      // Ground MSL = 150.0 - 15.0 = 135.0m
      expect(snapshot.radar.terrainElevationMsl, closeTo(135.0, 1e-3));
    });

    test('routes MAVLink DistanceSensor across multiple radar channels', () {
      final store = TelemetryStore();
      final now = DateTime.utc(2026, 11, 15, 12, 0, 0);

      // Channel 1: Front (rotNone = 0)
      store.apply(
        const DistanceSensor(
          instanceId: 1,
          orientation: MavSensorOrientation.mavSensorRotationNone,
          currentDistance: 800, // 8.0m
          minDistance: 20,
          maxDistance: 4000,
          signalQuality: 95,
        ),
        now: now,
      );

      // Channel 9: Top (rotPitch90 = 24)
      store.apply(
        const DistanceSensor(
          instanceId: 9,
          orientation: MavSensorOrientation.mavSensorRotationPitch90,
          currentDistance: 350, // 3.5m
          minDistance: 20,
          maxDistance: 2000,
          signalQuality: 80,
        ),
        now: now,
      );

      final snapshot = store.snapshot;
      expect(snapshot.radar.forward.distanceM, closeTo(8.0, 1e-3));
      expect(snapshot.radar.forward.signalQuality, equals(95));
      expect(snapshot.radar.top.distanceM, closeTo(3.5, 1e-3));
      expect(snapshot.radar.top.signalQuality, equals(80));
    });
  });
}
