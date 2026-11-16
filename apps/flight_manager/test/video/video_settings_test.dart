// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'package:apx_flight_manager/state/storage.dart';
import 'package:apx_flight_manager/video/media_kit_backend.dart';
import 'package:apx_flight_manager/video/video_layout.dart';
import 'package:apx_flight_manager/video/video_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  group('validation', () {
    VideoSettings rtsp(String url) => VideoSettings(source: VideoSourceKind.rtsp, rtspUrl: url);

    test('accepts typical camera URLs', () {
      for (final u in [
        'rtsp://192.168.144.25:8554/main.264',
        'rtsp://admin:pass@10.0.0.5:554/Streaming/Channels/101',
        'rtsps://cam.local/live',
        'rtsp://192.168.43.1:8554/fpv_stream',
      ]) {
        expect(validateVideoSettings(rtsp(u)), isEmpty, reason: u);
      }
    });

    test('rejects empty, wrong scheme, missing host, spaces', () {
      expect(validateVideoSettings(rtsp(''))['rtspUrl'], contains('Enter'));
      expect(validateVideoSettings(rtsp('http://1.2.3.4/x'))['rtspUrl'], contains('rtsp://'));
      expect(validateVideoSettings(rtsp('rtsp://'))['rtspUrl'], contains('host'));
      expect(validateVideoSettings(rtsp('rtsp://1.2.3.4/a b'))['rtspUrl'], contains('spaces'));
      expect(validateVideoSettings(rtsp('192.168.1.1:554'))['rtspUrl'], isNotNull);
    });

    test('UDP address must be IPv4 or empty; TCP needs a port', () {
      const udp = VideoSettings(source: VideoSourceKind.udpH264, udpPort: 5600);
      expect(validateVideoSettings(udp), isEmpty);
      expect(validateVideoSettings(udp.copyWith(udpAddress: '239.1.1.1')), isEmpty);
      expect(validateVideoSettings(udp.copyWith(udpAddress: '300.1.1.1')), contains('udpAddress'));
      expect(validateVideoSettings(udp.copyWith(udpAddress: 'cam')), contains('udpAddress'));
      expect(validateVideoSettings(udp.copyWith(udpPort: 0)), contains('udpPort'));
      const tcp = VideoSettings(source: VideoSourceKind.tcpMpegTs, tcpUrl: 'tcp://10.0.0.2');
      expect(validateVideoSettings(tcp)['tcpUrl'], contains('port'));
      expect(validateVideoSettings(tcp.copyWith(tcpUrl: 'tcp://10.0.0.2:5600')), isEmpty);
    });

    test('custom URL schemes', () {
      const c = VideoSettings(source: VideoSourceKind.customUrl);
      expect(validateVideoSettings(c.copyWith(customUrl: 'https://x.org/live.m3u8')), isEmpty);
      expect(validateVideoSettings(c.copyWith(customUrl: 'srt://10.0.0.2:9000')), isEmpty);
      expect(validateVideoSettings(c.copyWith(customUrl: 'ftp://x/y')), contains('customUrl'));
    });
  });

  group('endpoint', () {
    test('RTSP carries the transport', () {
      final e = VideoEndpoint.of(const VideoSettings(rtspUrl: ' rtsp://1.2.3.4/x ', rtspTransport: RtspTransport.udp));
      expect(e.url, 'rtsp://1.2.3.4/x');
      expect(e.options['rtsp-transport'], 'udp');
      expect(
        VideoEndpoint.of(const VideoSettings(rtspUrl: 'rtsp://h/x', rtspTransport: RtspTransport.auto))
            .options['rtsp-transport'],
        'lavf',
      );
    });

    test('raw RTP becomes an SDP with the codec and port', () {
      final e = VideoEndpoint.of(const VideoSettings(source: VideoSourceKind.udpH265, udpPort: 5602));
      expect(e.sdp, contains('m=video 5602 RTP/AVP 96'));
      expect(e.sdp, contains('a=rtpmap:96 H265/90000'));
      expect(e.sdp, contains('c=IN IP4 0.0.0.0'));
      expect(e.options['demuxer-lavf-format'], 'sdp');
      final m = VideoEndpoint.of(
        const VideoSettings(source: VideoSourceKind.udpH264, udpPort: 5600, udpAddress: '239.0.0.9'),
      );
      expect(m.sdp, contains('a=rtpmap:96 H264/90000'));
      expect(m.sdp, contains('c=IN IP4 239.0.0.9/32'));
    });

    test('MPEG-TS over UDP tolerates overruns', () {
      final e = VideoEndpoint.of(const VideoSettings(source: VideoSourceKind.udpMpegTs, udpPort: 5601));
      expect(e.url, startsWith('udp://0.0.0.0:5601?'));
      expect(e.url, contains('overrun_nonfatal=1'));
    });

    test('stream key changes with the source, not with display options', () {
      const a = VideoSettings(rtspUrl: 'rtsp://h/a');
      expect(a.streamKey, equals(a.copyWith(fit: VideoFit.fill, storageLimitMb: 100).streamKey));
      expect(a.streamKey, isNot(equals(a.copyWith(rtspUrl: 'rtsp://h/b').streamKey)));
      expect(a.backendKey, isNot(equals(a.copyWith(hardwareAcceleration: false).backendKey)));
      expect(a.copyWith(hardwareAcceleration: false).hwdec, 'no');
    });
  });

  test('JSON round trip and bad stored values fall back to defaults', () {
    final s = const VideoSettings().copyWith(
      enabled: true,
      source: VideoSourceKind.udpH265,
      udpPort: 5700,
      lowLatency: false,
      fit: VideoFit.stretch,
      aspect: VideoAspect.r4x3,
      recordingDir: () => '/data/rec',
      recordingFormat: RecordingFormat.mp4,
      storageLimitMb: 2048,
      maxReconnectAttempts: 5,
    );
    final back = VideoSettings.fromJson(s.toJson(), const VideoSettings());
    expect(back.toJson(), s.toJson());

    final bad = VideoSettings.fromJson({
      'source': 'nonsense',
      'udpPort': 99999,
      'timeoutSec': 0,
      'decoder': 'quantum',
      'recordingDir': '  ',
      'enabled': 'yes',
    }, const VideoSettings());
    expect(bad.source, VideoSourceKind.rtsp);
    expect(bad.udpPort, 5600);
    expect(bad.timeoutSec, 10);
    expect(bad.decoder, 'auto');
    expect(bad.recordingDir, isNull);
    expect(bad.enabled, isFalse);
  });

  test('settings and layout persist across restarts', () {
    final dir = tempDataDir();
    var c = ProviderContainer(overrides: [dataDirProvider.overrideWithValue(dir)]);
    c.read(videoSettingsProvider.notifier).update((s) => s.copyWith(enabled: true, rtspUrl: 'rtsp://10.1.1.1/v'));
    c.read(videoLayoutProvider.notifier).setMode(FlyLayoutMode.videoWithMap);
    c.read(videoLayoutProvider.notifier).setCorner(PipCorner.bottomRight);
    c.read(videoLayoutProvider.notifier).setWidth(5000); // clamped
    c.read(settingsStoreProvider).flush();
    c.dispose();

    c = ProviderContainer(overrides: [dataDirProvider.overrideWithValue(dir)]);
    addTearDown(c.dispose);
    final s = c.read(videoSettingsProvider);
    expect(s.enabled, isTrue);
    expect(s.rtspUrl, 'rtsp://10.1.1.1/v');
    final l = c.read(videoLayoutProvider);
    expect(l.mode, FlyLayoutMode.videoWithMap);
    expect(l.corner, PipCorner.bottomRight);
    expect(l.pipWidth, VideoLayout.maxWidth);
  });

  test('libmpv errors become actionable messages', () {
    expect(
      describeVideoError(['tcp: Connection to tcp://1.2.3.4:554 failed: Connection refused']),
      contains('refused'),
    );
    expect(describeVideoError(['method DESCRIBE failed: 401 Unauthorized']), contains('login'));
    expect(describeVideoError(['method DESCRIBE failed: 404 Not Found']), contains('404'));
    expect(describeVideoError(['method SETUP failed: 461 Unsupported transport']), contains('transport'));
    expect(describeVideoError(['bind failed: Address already in use']), contains('UDP port'));
    expect(describeVideoError(['Failed to recognize file format.']), contains('recognised format'));
    expect(describeVideoError([], playing: true), contains('stopped'));
  });
}
