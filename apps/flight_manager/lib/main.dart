// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/tokens.dart';
import 'shell/shell.dart';
import 'state/appearance.dart';
import 'state/audio.dart';
import 'state/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dataDir = await resolveDataDir();
  // Bundled fonts are OFL; list them with the other licences.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/fonts/JetBrainsMono-OFL.txt'));
  });
  runApp(ProviderScope(overrides: [dataDirProvider.overrideWithValue(dataDir)], child: const FlightManagerApp()));
}

class FlightManagerApp extends ConsumerWidget {
  const FlightManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly instantiate voice announcer so it begins listening to vehicle connection events.
    ref.read(audioAnnouncerProvider);

    return MaterialApp(
      title: 'APX Flight Manager',
      debugShowCheckedModeBanner: false,
      theme: alloyTheme(ref.watch(appearanceProvider)),
      home: const AppShell(),
    );
  }
}
