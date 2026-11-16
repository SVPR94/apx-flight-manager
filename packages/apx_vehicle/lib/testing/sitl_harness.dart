// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

/// Runs the real APX SITL (flight controller + built‑in physics) on free
/// ports so integration tests talk to actual firmware.
///
/// Firmware location: `$APX_ROOT` (default: `../apx` next to this repository),
/// binaries from `$APX_ROOT/build/sitl` (`cmake --preset sitl && cmake --build build/sitl`).
final class ApxSitl {
  ApxSitl._(this.tcpPort, this._fc, this._physics, this.log);

  final int tcpPort;
  final Process _fc;
  final Process _physics;
  final StringBuffer log;

  static String get apxRoot {
    final env = Platform.environment['APX_ROOT'];
    if (env != null && env.isNotEmpty) return env;
    // Tests run from packages/<name> or apps/<name>: two levels below the
    // repository, whose sibling is the apx/ firmware checkout.
    return Directory.current.uri.resolve('../../../apx').toFilePath();
  }

  static File get flightController => File('$apxRoot/build/sitl/main/apx_flight_controller');
  static File get physicsRunner => File('$apxRoot/build/sitl/sitl/apx_sim_physics_runner');

  /// Null when SITL hasn't been built (tests then skip).
  static String? get unavailableReason =>
      flightController.existsSync() && physicsRunner.existsSync() ? null : 'APX SITL not built at $apxRoot/build/sitl';

  static Future<ApxSitl> start({String vehicle = 'quad_x'}) async {
    final tcp = await _freeTcpPort();
    final gcsUdp = await _freeUdpPort();
    final simPort = await _freeUdpPort();
    final listenPort = await _freeUdpPort();
    final log = StringBuffer();

    final fc = await Process.start(flightController.path, [
      '--vehicle=$vehicle',
      '--sitl-port=$simPort',
      '--gcs-udp=$gcsUdp',
      '--tcp-ports=$tcp',
    ]);
    fc.stdout.transform(const SystemEncoding().decoder).listen(log.write);
    fc.stderr.transform(const SystemEncoding().decoder).listen(log.write);
    await _waitFor(log, 'System ready', const Duration(seconds: 10));

    final physics = await Process.start(physicsRunner.path, [
      '--port=$simPort',
      '--listen-port=$listenPort',
      '--vehicle=$vehicle',
    ]);
    physics.stdout.drain<void>();
    physics.stderr.drain<void>();
    return ApxSitl._(tcp, fc, physics, log);
  }

  Future<void> stop() async {
    _physics.kill();
    _fc.kill();
    await _fc.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _fc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  static Future<void> _waitFor(StringBuffer log, String text, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (!log.toString().contains(text)) {
      if (DateTime.now().isAfter(end)) throw StateError('SITL did not print "$text":\n$log');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  static Future<int> _freeTcpPort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  static Future<int> _freeUdpPort() async {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final p = s.port;
    s.close();
    return p;
  }
}
