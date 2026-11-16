// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:async';
import 'dart:io';

import 'package:apx_vehicle/apx_vehicle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'connection.dart';
import 'storage.dart';

/// Configuration for voice notifications and speech annunciations.
final class AudioSettings {
  const AudioSettings({
    this.enabled = true,
    this.volume = 1.0,
    this.speechRate = 0.5,
    this.announceModes = true,
    this.announceArming = true,
    this.announceBattery = true,
    this.announceMission = true,
    this.announceLink = true,
  });

  final bool enabled;
  final double volume; // 0.0 .. 1.0
  final double speechRate; // 0.0 .. 1.0 (0.5 is normal speed)
  final bool announceModes;
  final bool announceArming;
  final bool announceBattery;
  final bool announceMission;
  final bool announceLink;

  AudioSettings copyWith({
    bool? enabled,
    double? volume,
    double? speechRate,
    bool? announceModes,
    bool? announceArming,
    bool? announceBattery,
    bool? announceMission,
    bool? announceLink,
  }) => AudioSettings(
    enabled: enabled ?? this.enabled,
    volume: volume ?? this.volume,
    speechRate: speechRate ?? this.speechRate,
    announceModes: announceModes ?? this.announceModes,
    announceArming: announceArming ?? this.announceArming,
    announceBattery: announceBattery ?? this.announceBattery,
    announceMission: announceMission ?? this.announceMission,
    announceLink: announceLink ?? this.announceLink,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'volume': volume,
    'speechRate': speechRate,
    'announceModes': announceModes,
    'announceArming': announceArming,
    'announceBattery': announceBattery,
    'announceMission': announceMission,
    'announceLink': announceLink,
  };

  factory AudioSettings.fromJson(Map<String, Object?> json) => AudioSettings(
    enabled: json['enabled'] as bool? ?? true,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.5,
    announceModes: json['announceModes'] as bool? ?? true,
    announceArming: json['announceArming'] as bool? ?? true,
    announceBattery: json['announceBattery'] as bool? ?? true,
    announceMission: json['announceMission'] as bool? ?? true,
    announceLink: json['announceLink'] as bool? ?? true,
  );
}

/// Controller managing persistent speech settings.
final class AudioSettingsController extends Notifier<AudioSettings> {
  static const _key = 'audio_settings';

  @override
  AudioSettings build() {
    final raw = ref.read(settingsStoreProvider).get<Map<String, Object?>>(_key);
    if (raw == null) return const AudioSettings();
    try {
      return AudioSettings.fromJson(raw);
    } catch (_) {
      return const AudioSettings();
    }
  }

  void update(AudioSettings Function(AudioSettings current) fn) {
    state = fn(state);
    ref.read(settingsStoreProvider).set(_key, state.toJson());
  }

  void setEnabled(bool enabled) => update((s) => s.copyWith(enabled: enabled));
  void setVolume(double volume) => update((s) => s.copyWith(volume: volume.clamp(0.0, 1.0)));
  void setSpeechRate(double rate) => update((s) => s.copyWith(speechRate: rate.clamp(0.1, 1.0)));
  void toggleModes(bool v) => update((s) => s.copyWith(announceModes: v));
  void toggleArming(bool v) => update((s) => s.copyWith(announceArming: v));
  void toggleBattery(bool v) => update((s) => s.copyWith(announceBattery: v));
  void toggleMission(bool v) => update((s) => s.copyWith(announceMission: v));
  void toggleLink(bool v) => update((s) => s.copyWith(announceLink: v));
}

final audioSettingsProvider = NotifierProvider<AudioSettingsController, AudioSettings>(AudioSettingsController.new);

typedef CommandRunner = Future<ProcessResult> Function(String executable, List<String> arguments);

/// Injectable process runner for desktop speech utilities, allowing tests to mock execution.
final audioProcessRunnerProvider = Provider<CommandRunner>((ref) => Process.run);

/// Speech annunciator service that watches vehicle alerts and produces voice output.
///
/// On Linux desktop, speech is synthesized via native desktop Speech Dispatcher (`spd-say`)
/// or `espeak-ng`, ensuring reliable audio output on Linux without plugin dependencies.
/// On Windows, macOS, and mobile, it utilizes FlutterTts.
final class AudioAnnouncer {
  AudioAnnouncer(this._ref) {
    _initTts();
    _listenToConnection();
  }

  final Ref _ref;
  FlutterTts? _tts;
  bool _ready = false;
  bool _useLinuxNative = false;
  StreamSubscription<Alert>? _alertSub;

  CommandRunner get _runner => _ref.read(audioProcessRunnerProvider);

  Future<void> _initTts() async {
    if (kIsWeb) return;

    if (Platform.isLinux) {
      // flutter_tts does not have a Linux desktop implementation.
      // Use Linux native desktop speech dispatcher (spd-say) or espeak.
      _useLinuxNative = true;
      _ready = true;
      return;
    }

    try {
      final tts = FlutterTts();
      _tts = tts;
      await tts.setLanguage('en-US');
      final s = _ref.read(audioSettingsProvider);
      await tts.setVolume(s.volume);
      await tts.setSpeechRate(s.speechRate);
      _ready = true;
    } catch (e) {
      debugPrint('AudioAnnouncer: TTS unavailable ($e)');
      _ready = false;
    }
  }

  void _listenToConnection() {
    _ref.listen<Connection?>(connectionProvider, (prev, next) {
      _alertSub?.cancel();
      _alertSub = null;
      if (next != null) {
        _alertSub = next.alerts.alerts.listen(_handleAlert);
      }
    });

    // Also update volume/rate when settings change.
    _ref.listen<AudioSettings>(audioSettingsProvider, (prev, next) {
      if (_ready && _tts != null && !_useLinuxNative) {
        _tts!.setVolume(next.volume).catchError((_) => null);
        _tts!.setSpeechRate(next.speechRate).catchError((_) => null);
      }
    });
  }

  void _handleAlert(Alert alert) {
    final s = _ref.read(audioSettingsProvider);
    if (!s.enabled) return;

    final phrase = _formatAlertPhrase(alert, s);
    if (phrase != null && phrase.isNotEmpty) {
      // For critical alerts, optionally sound an alert tone first
      if (alert.severity == AlertSeverity.critical && _useLinuxNative) {
        _playChime('/usr/share/sounds/freedesktop/stereo/bell.oga');
      } else if (alert.key == 'mission' && alert.text.contains('complete') && _useLinuxNative) {
        _playChime('/usr/share/sounds/freedesktop/stereo/complete.oga');
      }
      speak(phrase);
    }
  }

  void _playChime(String soundPath) {
    if (!Platform.isLinux) return;
    final file = File(soundPath);
    if (file.existsSync()) {
      _runner('paplay', [soundPath]).catchError((_) => ProcessResult(0, 0, '', ''));
    }
  }

  String? _formatAlertPhrase(Alert alert, AudioSettings s) {
    final k = alert.key;
    if (k == 'arm') {
      if (!s.announceArming) return null;
      return alert.text.toLowerCase().contains('disarm') ? 'Vehicle disarmed' : 'Vehicle armed';
    }
    if (k == 'mode') {
      if (!s.announceModes) return null;
      return alert.text; // "Mode LOITER", "Mode RTL", etc.
    }
    if (k.startsWith('battery')) {
      if (!s.announceBattery) return null;
      return alert.text; // "Battery low: 14.2 V", "Battery critical: 13.5 V — land now"
    }
    if (k.startsWith('mission')) {
      if (!s.announceMission) return null;
      return alert.text; // "Mission complete", "Item 3 reached"
    }
    if (k == 'link') {
      if (!s.announceLink) return null;
      return alert.text; // "Link lost", "Link restored"
    }
    return null;
  }

  Future<void> speak(String phrase) async {
    final s = _ref.read(audioSettingsProvider);
    if (!s.enabled) return;

    if (_useLinuxNative) {
      final volInt = ((s.volume * 200) - 100).round().clamp(-100, 100);
      final rateInt = (((s.speechRate - 0.5) * 200)).round().clamp(-100, 100);
      try {
        await _runner('spd-say', ['-i', '$volInt', '-r', '$rateInt', '-P', 'important', phrase]);
        return;
      } catch (e) {
        // Fallback to espeak if spd-say is unavailable
        try {
          await _runner('espeak', [phrase]);
          return;
        } catch (_) {}
      }
    }

    if (!_ready || _tts == null) {
      debugPrint('[Announcer] $phrase');
      return;
    }

    try {
      await _tts!.stop();
      await _tts!.speak(phrase);
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  Future<void> testVoice() async {
    if (_useLinuxNative) {
      _playChime('/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga');
    }
    await speak('APX voice annunciator active. Audio system nominal.');
  }

  void dispose() {
    _alertSub?.cancel();
    _alertSub = null;
    _tts?.stop();
  }
}

final audioAnnouncerProvider = Provider<AudioAnnouncer>((ref) {
  final announcer = AudioAnnouncer(ref);
  ref.onDispose(announcer.dispose);
  return announcer;
});
