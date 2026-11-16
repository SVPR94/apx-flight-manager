// SPDX-License-Identifier: CC-BY-NC-4.0
// Copyright (c) 2026 Savita Pawar <savitapawar0402@gmail.com>
// Author: Savita Pawar (SVPR94)
// Created: 2026
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/storage.dart';

/// Where the video comes from. APX does not implement the MAVLink camera
/// protocol (VIDEO_STREAM_INFORMATION), so — like standard GCS manual
/// sources — the stream is described here rather than discovered.
enum VideoSourceKind {
  rtsp('RTSP stream'),
  udpH264('UDP · RTP H.264'),
  udpH265('UDP · RTP H.265'),
  udpMpegTs('UDP · MPEG-TS'),
  tcpMpegTs('TCP · MPEG-TS'),
  customUrl('Other URL (HTTP, HLS, RTMP, SRT, file)');

  const VideoSourceKind(this.label);
  final String label;

  bool get isUdp => this == udpH264 || this == udpH265 || this == udpMpegTs;
}

/// RTSP's media transport. TCP (interleaved) survives NAT and lossy Wi-Fi;
/// UDP has slightly less latency; auto lets FFmpeg try UDP then TCP.
enum RtspTransport {
  tcp('TCP'),
  udp('UDP'),
  auto('Automatic');

  const RtspTransport(this.label);
  final String label;
}

/// How the picture fills its frame. [fit] never crops or distorts.
enum VideoFit {
  fit('Fit (letterbox)'),
  fill('Fill (crop edges)'),
  stretch('Stretch');

  const VideoFit(this.label);
  final String label;
}

/// Display aspect ratio. [auto] uses the stream's own (square pixels as sent).
enum VideoAspect {
  auto('From stream', null),
  r16x9('16:9', 16 / 9),
  r4x3('4:3', 4 / 3),
  r21x9('21:9', 21 / 9),
  r1x1('1:1', 1.0);

  const VideoAspect(this.label, this.ratio);
  final String label;
  final double? ratio;
}

enum RecordingFormat {
  mkv('Matroska (.mkv) — survives power loss'),
  mp4('MP4 (.mp4) — plays everywhere, photo library'),
  mov('QuickTime (.mov)');

  const RecordingFormat(this.label);
  final String label;
  String get extension => name;
}

/// A decoder choice: [hwdec] is the libmpv `hwdec` value (`null` keeps the
/// platform default chosen by media_kit).
typedef DecoderOption = ({String id, String label, String? hwdec});

/// Decoders offered on this platform. "auto" picks a hardware decoder when one
/// works and falls back to software; the explicit ones force a single API.
List<DecoderOption> decoderOptions() => [
  (id: 'auto', label: 'Automatic (hardware when available)', hwdec: Platform.isAndroid ? null : 'auto-safe'),
  (id: 'software', label: 'Software (FFmpeg, CPU)', hwdec: 'no'),
  if (Platform.isWindows) ...[
    (id: 'd3d11va', label: 'Direct3D 11 (D3D11VA)', hwdec: 'd3d11va'),
    (id: 'dxva2', label: 'DirectX VA 2 (DXVA2)', hwdec: 'dxva2'),
    (id: 'nvdec', label: 'NVIDIA (NVDEC)', hwdec: 'nvdec'),
  ],
  if (Platform.isLinux) ...[
    (id: 'vaapi', label: 'VA-API (Intel / AMD)', hwdec: 'vaapi'),
    (id: 'nvdec', label: 'NVIDIA (NVDEC)', hwdec: 'nvdec'),
    (id: 'vdpau', label: 'VDPAU', hwdec: 'vdpau'),
  ],
  if (Platform.isAndroid) ...[
    (id: 'mediacodec', label: 'MediaCodec (direct)', hwdec: 'mediacodec'),
    (id: 'mediacodec-copy', label: 'MediaCodec (copy-back)', hwdec: 'mediacodec-copy'),
  ],
  if (Platform.isIOS || Platform.isMacOS) (id: 'videotoolbox', label: 'VideoToolbox', hwdec: 'videotoolbox'),
];

DecoderOption decoderById(String id) =>
    decoderOptions().firstWhere((d) => d.id == id, orElse: () => decoderOptions().first);

/// Everything the user can set about video. Persisted under `video` in
/// settings.json; unknown or invalid stored values fall back to defaults.
final class VideoSettings {
  const VideoSettings({
    this.enabled = false,
    this.source = VideoSourceKind.rtsp,
    this.rtspUrl = '',
    this.rtspTransport = RtspTransport.tcp,
    this.udpPort = 5600,
    this.udpAddress = '',
    this.tcpUrl = '',
    this.customUrl = '',
    this.lowLatency = true,
    this.hardwareAcceleration = true,
    this.decoder = 'auto',
    this.fit = VideoFit.fit,
    this.aspect = VideoAspect.auto,
    this.audio = false,
    this.autoConnect = true,
    this.autoReconnect = true,
    this.reconnectDelaySec = 2,
    this.maxReconnectAttempts = 0,
    this.timeoutSec = 10,
    this.recordingDir,
    RecordingFormat? recordingFormat,
    this.storageLimitMb = 0,
    bool? saveToGallery,
  }) : recordingFormat = recordingFormat ?? RecordingFormat.mkv,
       saveToGallery = saveToGallery ?? false;

  /// Defaults that differ by platform: iOS's photo library only takes MP4/MOV,
  /// and on phones/tablets recordings are only easy to find in the gallery.
  factory VideoSettings.platformDefaults() => VideoSettings(
    recordingFormat: Platform.isIOS ? RecordingFormat.mp4 : RecordingFormat.mkv,
    saveToGallery: Platform.isAndroid || Platform.isIOS,
  );

  final bool enabled;
  final VideoSourceKind source;
  final String rtspUrl;
  final RtspTransport rtspTransport;
  final int udpPort;

  /// Address to listen on: empty for any interface, or a multicast group.
  final String udpAddress;
  final String tcpUrl;
  final String customUrl;

  /// Display frames as soon as they are decoded, with no buffering.
  final bool lowLatency;

  /// GPU rendering and hardware decoding. Off forces software for both.
  final bool hardwareAcceleration;
  final String decoder;
  final VideoFit fit;
  final VideoAspect aspect;
  final bool audio;
  final bool autoConnect;
  final bool autoReconnect;
  final int reconnectDelaySec;

  /// 0 = keep trying.
  final int maxReconnectAttempts;

  /// Seconds without a first frame (connecting) or a new frame (playing)
  /// before the stream counts as lost.
  final int timeoutSec;

  /// Null = the platform default (see video_storage.dart).
  final String? recordingDir;
  final RecordingFormat recordingFormat;

  /// Oldest recordings are deleted to keep the folder under this; 0 = no limit.
  final int storageLimitMb;

  /// Android/iOS: copy finished recordings and snapshots to the gallery.
  final bool saveToGallery;

  /// The libmpv `hwdec` value to use.
  String? get hwdec => hardwareAcceleration ? decoderById(decoder).hwdec : 'no';

  VideoSettings copyWith({
    bool? enabled,
    VideoSourceKind? source,
    String? rtspUrl,
    RtspTransport? rtspTransport,
    int? udpPort,
    String? udpAddress,
    String? tcpUrl,
    String? customUrl,
    bool? lowLatency,
    bool? hardwareAcceleration,
    String? decoder,
    VideoFit? fit,
    VideoAspect? aspect,
    bool? audio,
    bool? autoConnect,
    bool? autoReconnect,
    int? reconnectDelaySec,
    int? maxReconnectAttempts,
    int? timeoutSec,
    String? Function()? recordingDir,
    RecordingFormat? recordingFormat,
    int? storageLimitMb,
    bool? saveToGallery,
  }) => VideoSettings(
    enabled: enabled ?? this.enabled,
    source: source ?? this.source,
    rtspUrl: rtspUrl ?? this.rtspUrl,
    rtspTransport: rtspTransport ?? this.rtspTransport,
    udpPort: udpPort ?? this.udpPort,
    udpAddress: udpAddress ?? this.udpAddress,
    tcpUrl: tcpUrl ?? this.tcpUrl,
    customUrl: customUrl ?? this.customUrl,
    lowLatency: lowLatency ?? this.lowLatency,
    hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
    decoder: decoder ?? this.decoder,
    fit: fit ?? this.fit,
    aspect: aspect ?? this.aspect,
    audio: audio ?? this.audio,
    autoConnect: autoConnect ?? this.autoConnect,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    reconnectDelaySec: reconnectDelaySec ?? this.reconnectDelaySec,
    maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
    timeoutSec: timeoutSec ?? this.timeoutSec,
    recordingDir: recordingDir != null ? recordingDir() : this.recordingDir,
    recordingFormat: recordingFormat ?? this.recordingFormat,
    storageLimitMb: storageLimitMb ?? this.storageLimitMb,
    saveToGallery: saveToGallery ?? this.saveToGallery,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'source': source.name,
    'rtspUrl': rtspUrl,
    'rtspTransport': rtspTransport.name,
    'udpPort': udpPort,
    'udpAddress': udpAddress,
    'tcpUrl': tcpUrl,
    'customUrl': customUrl,
    'lowLatency': lowLatency,
    'hardwareAcceleration': hardwareAcceleration,
    'decoder': decoder,
    'fit': fit.name,
    'aspect': aspect.name,
    'audio': audio,
    'autoConnect': autoConnect,
    'autoReconnect': autoReconnect,
    'reconnectDelaySec': reconnectDelaySec,
    'maxReconnectAttempts': maxReconnectAttempts,
    'timeoutSec': timeoutSec,
    'recordingDir': recordingDir,
    'recordingFormat': recordingFormat.name,
    'storageLimitMb': storageLimitMb,
    'saveToGallery': saveToGallery,
  };

  /// Reads stored settings; any missing or out-of-range value keeps its default.
  factory VideoSettings.fromJson(Map<String, Object?> j, VideoSettings d) {
    T pick<T extends Enum>(List<T> values, Object? v, T fallback) =>
        values.firstWhere((e) => e.name == v, orElse: () => fallback);
    int intIn(Object? v, int lo, int hi, int fallback) {
      final n = (v is num) ? v.toInt() : null;
      return n != null && n >= lo && n <= hi ? n : fallback;
    }

    bool flag(String k, bool fallback) => j[k] is bool ? j[k] as bool : fallback;
    String text(String k, String fallback) => j[k] is String ? j[k] as String : fallback;

    final decoder = text('decoder', d.decoder);
    final dir = text('recordingDir', '').trim();
    return VideoSettings(
      enabled: flag('enabled', d.enabled),
      source: pick(VideoSourceKind.values, j['source'], d.source),
      rtspUrl: text('rtspUrl', d.rtspUrl),
      rtspTransport: pick(RtspTransport.values, j['rtspTransport'], d.rtspTransport),
      udpPort: intIn(j['udpPort'], 1, 65535, d.udpPort),
      udpAddress: text('udpAddress', d.udpAddress),
      tcpUrl: text('tcpUrl', d.tcpUrl),
      customUrl: text('customUrl', d.customUrl),
      lowLatency: flag('lowLatency', d.lowLatency),
      hardwareAcceleration: flag('hardwareAcceleration', d.hardwareAcceleration),
      // A decoder saved on another platform (settings copied over) isn't offered here.
      decoder: decoderOptions().any((o) => o.id == decoder) ? decoder : 'auto',
      fit: pick(VideoFit.values, j['fit'], d.fit),
      aspect: pick(VideoAspect.values, j['aspect'], d.aspect),
      audio: flag('audio', d.audio),
      autoConnect: flag('autoConnect', d.autoConnect),
      autoReconnect: flag('autoReconnect', d.autoReconnect),
      reconnectDelaySec: intIn(j['reconnectDelaySec'], 1, 60, d.reconnectDelaySec),
      maxReconnectAttempts: intIn(j['maxReconnectAttempts'], 0, 1000, d.maxReconnectAttempts),
      timeoutSec: intIn(j['timeoutSec'], 2, 60, d.timeoutSec),
      recordingDir: dir.isEmpty ? null : dir,
      recordingFormat: pick(RecordingFormat.values, j['recordingFormat'], d.recordingFormat),
      storageLimitMb: intIn(j['storageLimitMb'], 0, 10 * 1024 * 1024, d.storageLimitMb),
      saveToGallery: flag('saveToGallery', d.saveToGallery),
    );
  }

  /// Stream-defining fields: a change here means reconnecting.
  List<Object?> get streamKey => [
    source,
    switch (source) {
      VideoSourceKind.rtsp => '$rtspUrl|${rtspTransport.name}',
      VideoSourceKind.udpH264 || VideoSourceKind.udpH265 || VideoSourceKind.udpMpegTs => '$udpAddress:$udpPort',
      VideoSourceKind.tcpMpegTs => tcpUrl,
      VideoSourceKind.customUrl => customUrl,
    },
    lowLatency,
    audio,
    timeoutSec,
  ];

  /// Fields that need a new player (the renderer is chosen when it's created).
  List<Object?> get backendKey => [hardwareAcceleration, hwdec];
}

/// Problems with the current settings, by field. Empty when the stream can be
/// opened. The UI shows these next to the fields and blocks connecting.
Map<String, String> validateVideoSettings(VideoSettings s) {
  final e = <String, String>{};
  switch (s.source) {
    case VideoSourceKind.rtsp:
      final err = _checkUrl(s.rtspUrl, const {'rtsp', 'rtsps'}, needPort: false);
      if (err != null) e['rtspUrl'] = err;
    case VideoSourceKind.udpH264 || VideoSourceKind.udpH265 || VideoSourceKind.udpMpegTs:
      if (s.udpPort < 1 || s.udpPort > 65535) e['udpPort'] = 'Port 1–65535';
      final a = s.udpAddress.trim();
      if (a.isNotEmpty && !_isIPv4(a)) e['udpAddress'] = 'An IPv4 address (e.g. 239.0.0.1), or empty for any';
    case VideoSourceKind.tcpMpegTs:
      final err = _checkUrl(s.tcpUrl, const {'tcp'}, needPort: true);
      if (err != null) e['tcpUrl'] = err;
    case VideoSourceKind.customUrl:
      final err = _checkUrl(s.customUrl, const {
        'http',
        'https',
        'rtsp',
        'rtsps',
        'rtmp',
        'rtmps',
        'srt',
        'udp',
        'rtp',
        'tcp',
        'file',
      }, needPort: false);
      if (err != null) e['customUrl'] = err;
  }
  return e;
}

String? _checkUrl(String raw, Set<String> schemes, {required bool needPort}) {
  final t = raw.trim();
  if (t.isEmpty) return 'Enter the stream address';
  if (t.contains(' ')) return 'Addresses can\'t contain spaces';
  final u = Uri.tryParse(t);
  if (u == null || !u.hasScheme) return 'Start with ${schemes.map((s) => '$s://').join(' or ')}';
  if (!schemes.contains(u.scheme.toLowerCase())) {
    return 'Use ${schemes.map((s) => '$s://').join(', ')} (got ${u.scheme}://)';
  }
  if (u.scheme == 'file') return u.path.isEmpty ? 'Enter a file path' : null;
  if (u.host.isEmpty) return 'Missing host (e.g. ${schemes.first}://192.168.144.25:8554/main)';
  if (u.hasPort && (u.port < 1 || u.port > 65535)) return 'Port 1–65535';
  if (needPort && !u.hasPort) return 'Add a port (e.g. ${schemes.first}://192.168.1.10:5600)';
  return null;
}

bool _isIPv4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return false;
  return parts.every((p) {
    final n = int.tryParse(p);
    return n != null && n >= 0 && n <= 255 && p == '$n';
  });
}

/// What to open in libmpv for a source: a URL (or a generated SDP file's
/// contents for raw RTP) plus the per-source mpv options.
final class VideoEndpoint {
  const VideoEndpoint({required this.url, this.sdp, this.options = const {}, required this.description});

  /// The URL to load. For RTP sources this is replaced by the SDP file path.
  final String url;

  /// Session description for raw RTP over UDP: FFmpeg needs it to know the
  /// payload type and codec (gst `rtph264pay` / GCS "UDP h.264" senders).
  final String? sdp;
  final Map<String, String> options;
  final String description;

  factory VideoEndpoint.of(VideoSettings s) {
    final any = s.udpAddress.trim().isEmpty ? '0.0.0.0' : s.udpAddress.trim();
    switch (s.source) {
      case VideoSourceKind.rtsp:
        return VideoEndpoint(
          url: s.rtspUrl.trim(),
          options: {
            'rtsp-transport': switch (s.rtspTransport) {
              RtspTransport.tcp => 'tcp',
              RtspTransport.udp => 'udp',
              RtspTransport.auto => 'lavf',
            },
          },
          description: s.rtspUrl.trim(),
        );
      case VideoSourceKind.udpH264 || VideoSourceKind.udpH265:
        final codec = s.source == VideoSourceKind.udpH264 ? 'H264' : 'H265';
        final multicast = _isMulticast(any);
        return VideoEndpoint(
          url: '',
          sdp: [
            'v=0',
            'o=- 0 0 IN IP4 127.0.0.1',
            's=APX Flight Manager video',
            'c=IN IP4 $any${multicast ? '/32' : ''}',
            't=0 0',
            'm=video ${s.udpPort} RTP/AVP 96',
            'a=rtpmap:96 $codec/90000',
            '',
          ].join('\n'),
          options: const {'demuxer-lavf-format': 'sdp'},
          description: 'RTP $codec on UDP ${multicast ? '$any:' : ''}${s.udpPort}',
        );
      case VideoSourceKind.udpMpegTs:
        // Large FIFO, and overruns are not fatal: a burst after a stall must
        // not end the stream.
        return VideoEndpoint(
          url: 'udp://$any:${s.udpPort}?fifo_size=1000000&overrun_nonfatal=1',
          description: 'MPEG-TS on UDP ${any == '0.0.0.0' ? '' : '$any:'}${s.udpPort}',
        );
      case VideoSourceKind.tcpMpegTs:
        return VideoEndpoint(url: s.tcpUrl.trim(), description: s.tcpUrl.trim());
      case VideoSourceKind.customUrl:
        return VideoEndpoint(url: s.customUrl.trim(), description: s.customUrl.trim());
    }
  }

  static bool _isMulticast(String ip) {
    final first = int.tryParse(ip.split('.').first) ?? 0;
    return first >= 224 && first <= 239;
  }
}

final class VideoSettingsController extends Notifier<VideoSettings> {
  static const _key = 'video';

  @override
  VideoSettings build() {
    final d = VideoSettings.platformDefaults();
    final raw = ref.read(settingsStoreProvider).get<Map<String, Object?>>(_key);
    if (raw == null) return d;
    try {
      return VideoSettings.fromJson(raw, d);
    } catch (_) {
      return d;
    }
  }

  void update(VideoSettings Function(VideoSettings s) change) {
    state = change(state);
    ref.read(settingsStoreProvider).set(_key, state.toJson());
  }

  void reset() {
    state = VideoSettings.platformDefaults().copyWith(enabled: state.enabled);
    ref.read(settingsStoreProvider).set(_key, state.toJson());
  }
}

final videoSettingsProvider = NotifierProvider<VideoSettingsController, VideoSettings>(VideoSettingsController.new);
