// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_flight_manager/state/connection.dart';
import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_link/apx_link.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('Connection Interfaces and Error Handling', () {
    test('SerialConfig creates valid descriptor and title', () {
      const serial = SerialConfig('/dev/ttyACM0', baudRate: 115200);
      expect(serial.port, '/dev/ttyACM0');
      expect(serial.baudRate, 115200);
      expect(serial.title, contains('Serial /dev/ttyACM0 @ 115200'));

      final link = serial.build();
      expect(link.descriptor.kind, LinkKind.serial);
      expect(link.descriptor.address, 'serial:/dev/ttyACM0@115200');
    });

    test('PosixSerialPortEnumerator runs without throwing', () async {
      const enumerator = PosixSerialPortEnumerator();
      final ports = await enumerator.list();
      expect(ports, isA<List<SerialPortInfo>>());
    });

    test('Connecting to unreachable TCP fails gracefully without throwing', () async {
      final container = ProviderContainer(overrides: testOverrides(tempDataDir()));
      addTearDown(container.dispose);

      // Connect to a port where nothing is listening (e.g. 59999)
      final ctrl = container.read(connectionProvider.notifier);
      final err = await ctrl.connect(const TcpConfig('127.0.0.1', 59999));

      // Returns a descriptive error message and connection remains null
      expect(err, isNotNull);
      expect(err, contains('Failed to connect'));
      expect(container.read(connectionProvider), isNull);
    });

    test('Settings store persists and remembers last selected interface values', () {
      final container = ProviderContainer(overrides: testOverrides(tempDataDir()));
      addTearDown(container.dispose);

      final store = container.read(settingsStoreProvider);
      store.set('conn_last_kind', 'serial');
      store.set('conn_serial_port', '/dev/ttyUSB0');
      store.set('conn_serial_baud', 57600);
      store.flush();

      expect(store.get<String>('conn_last_kind'), 'serial');
      expect(store.get<String>('conn_serial_port'), '/dev/ttyUSB0');
      expect(store.get<int>('conn_serial_baud'), 57600);
    });
  });
}

