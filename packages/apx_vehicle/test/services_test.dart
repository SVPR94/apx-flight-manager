// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_mavlink/apx_mavlink.dart';
import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:test/test.dart';

import 'fake_vehicle.dart';

const _fast = Duration(milliseconds: 150);

void main() {
  group('parameters', () {
    test('download fills gaps by index', () async {
      final v = FakeApx()..dropOnList = {3, 17, 41};
      final s = ParameterService(v, listTimeout: _fast, gapTimeout: _fast, setTimeout: _fast);
      final result = await s.refresh();
      expect(result.state, ParamLoadState.complete);
      expect(s.all, hasLength(v.params.length));
      expect(v.sent.whereType<ParamRequestRead>().map((r) => r.paramIndex), containsAll([3, 17, 41]));
      await s.dispose();
    });

    test('set reports APX clamping and silence for unknown names', () async {
      final v = FakeApx();
      final s = ParameterService(v, setTimeout: _fast);
      await s.refresh();

      final ok = await s.set('WPNAV_SPEED', 650);
      expect(ok.outcome, ParamSetOutcome.applied);
      expect(s['WPNAV_SPEED']!.value, 650);

      final clamped = await s.set('WPNAV_SPEED', 99999);
      expect(clamped.outcome, ParamSetOutcome.clamped);
      expect(clamped.stored, 2000);

      final unknown = await s.set('NOT_A_PARAM', 1);
      expect(unknown.outcome, ParamSetOutcome.noReply);
      expect(v.sent.whereType<ParamSet>().where((p) => p.paramId == 'NOT_A_PARAM'), hasLength(3));
      await s.dispose();
    });

    test('profile diff and re‑apply (APX forgets parameters on reboot)', () async {
      final v = FakeApx();
      final s = ParameterService(v, setTimeout: _fast);
      await s.refresh();
      final profile = ParameterProfile.parse('field', 'WPNAV_SPEED,700\n# comment\nSPRAY_PUMP_RATE 12\nTEST_P1,1');
      expect(profile.diff(s.all).keys, {'WPNAV_SPEED', 'SPRAY_PUMP_RATE'});
      final results = await profile.applyTo(s);
      expect(results.map((r) => r.outcome), everyElement(ParamSetOutcome.applied));
      expect(profile.diff(s.all), isEmpty);
      expect(ParameterProfile.parse('x', profile.toText()).values, profile.values);
      await s.dispose();
    });
  });

  group('mission transfer', () {
    List<WireMissionItem> plan() => [
      const WireMissionItem(seq: 0, command: MavCmd.navWaypoint, frame: MavFrame.globalInt, x: 185204000, y: 738567000),
      const WireMissionItem(seq: 1, command: MavCmd.navTakeoff, z: 10),
      const WireMissionItem(seq: 2, command: MavCmd.navWaypoint, x: 185207000, y: 738567000, z: 10, param2: 2),
      const WireMissionItem(seq: 3, command: MavCmd.doSprayer, param1: 1),
      const WireMissionItem(seq: 4, command: MavCmd.navReturnToLaunch),
    ];

    test('upload survives lost requests the way APX recovers', () async {
      final v = FakeApx()..dropUploadRequest = {0, 3};
      final t = MissionTransfer(v, ackTimeout: _fast, itemTimeout: _fast);
      await t.upload(plan());
      expect(v.mission.map((i) => i.command), plan().map((i) => i.command));
      expect(t.progress.value.state, TransferState.done);
      expect(v.sent.whereType<MissionCount>(), hasLength(2)); // re‑announced once
    });

    test('download retries lost items and acknowledges', () async {
      final v = FakeApx()
        ..mission.addAll(plan())
        ..dropDownloadItem = {2};
      final t = MissionTransfer(v, ackTimeout: _fast, itemTimeout: _fast);
      final items = await t.download();
      expect(items.map((i) => i.seq), [0, 1, 2, 3, 4]);
      expect(items[2].param2, 2);
      expect(v.sent.last, isA<MissionAck>());
      expect(v.sent.whereType<MissionRequestList>().single.missionType, MavMissionType.mission);
    });

    test('never touches fence or rally', () async {
      final v = FakeApx();
      final t = MissionTransfer(v, ackTimeout: _fast, itemTimeout: _fast);
      await t.upload(plan());
      await t.download();
      await t.clear();
      final types = [
        ...v.sent.whereType<MissionCount>().map((m) => m.missionType),
        ...v.sent.whereType<MissionRequestList>().map((m) => m.missionType),
        ...v.sent.whereType<MissionClearAll>().map((m) => m.missionType),
        ...v.sent.whereType<MissionItemInt>().map((m) => m.missionType),
      ];
      expect(types, everyElement(MavMissionType.mission));
    });

    test('fails clearly when the vehicle goes silent', () async {
      final t = MissionTransfer(_Silent(FakeApx()), ackTimeout: const Duration(milliseconds: 40), maxRetries: 2);
      await expectLater(t.upload(plan()), throwsA(isA<TransferException>()));
      expect(t.progress.value.state, TransferState.failed);
      expect(t.progress.value.message, contains('stopped responding'));
    });
  });

  group('commands', () {
    test('retries until acknowledged', () async {
      final v = FakeApx()..dropAcks = 2;
      final c = CommandService(v, apx01Profile, timeout: _fast);
      final r = await c.arm();
      expect(r.accepted, isTrue);
      expect(r.attempts, 3);
      expect(v.sent.whereType<CommandLong>().map((m) => m.confirmation), [0, 1, 2]);
    });

    test('refuses what the profile says the firmware cannot do', () async {
      final v = FakeApx();
      final c = CommandService(v, apx01Profile, timeout: _fast);
      final r = await c.long(MavCmd.preflightCalibration, p1: 1);
      expect(r.result, MavResult.unsupported);
      expect(v.sent, isEmpty);
      expect(() => c.setAuxServo(3, 1500), throwsRangeError);
    });

    test('set home sends a map point as exact COMMAND_INT, "here" as COMMAND_LONG', () async {
      final v = FakeApx();
      final c = CommandService(v, apx01Profile, timeout: _fast);
      expect((await c.setHome(useCurrentPosition: false, lat: 18.5204123, lon: 73.8571234)).accepted, isTrue);
      final i = v.sent.whereType<CommandInt>().single;
      expect(i.command, MavCmd.doSetHome);
      expect(i.frame, MavFrame.global);
      expect((i.x, i.y), (185204123, 738571234));
      expect(i.z.isNaN, isTrue); // unknown altitude: the vehicle keeps its home altitude

      expect((await c.setHome(useCurrentPosition: true)).accepted, isTrue);
      final l = v.sent.whereType<CommandLong>().single;
      expect((l.command, l.param1), (MavCmd.doSetHome, 1));
    });
  });

  test('profile recognises APX by its parameters', () {
    expect(
      resolveProfile(
        autopilot: MavAutopilot.apxmega,
        parameterNames: {'WPNAV_BLEND', 'SPRAY_PUMP_RATE', 'RTL_ALT'},
      ),
      same(apx01Profile),
    );
    expect(resolveProfile(autopilot: MavAutopilot.apxmega, parameterNames: {'RTL_ALT'}), same(apx01Profile));
    expect(apx01Profile.selectableModes.map((m) => m.name), isNot(contains('AGRI_SPRAY')));
    expect(FirmwareVersion.fromFlightSw(0x00010000).toString(), '0.1.0');
  });
}

/// Swallows everything: a vehicle that stopped talking.
final class _Silent implements VehicleChannel {
  _Silent(this._inner);
  final VehicleChannel _inner;
  @override
  int get targetSystem => _inner.targetSystem;
  @override
  int get targetComponent => _inner.targetComponent;
  @override
  Stream<MavMessage> get messages => const Stream.empty();
  @override
  Future<void> send(MavMessage message) async {}
}
