import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dart_cast/dart_cast.dart' as dc;

export 'package:dart_cast/dart_cast.dart'
    show CastDevice, CastProtocol, CastMediaType, CastSession, SessionState;

/// Extensiones de compatibilidad con versiones previas
extension CastDeviceCompat on dc.CastDevice {
  String get friendlyName => name;
  UdnCompat get udn => UdnCompat(id);
}

class UdnCompat {
  final String value;
  const UdnCompat(this.value);
  @override
  String toString() => value;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UdnCompat && other.value == value);
  @override
  int get hashCode => value.hashCode;
}

/// Estados posibles de la sesión de casting
enum CastState {
  idle,
  discovering,
  connected,
  casting,
  error,
}

const String _kDefaultCastUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const String _kDlnaFlags = '01700000000000000000000000000000';
const String _kDlnaTsFeatures =
    'DLNA.ORG_PN=MPEG_TS_HD_NA_ISO;DLNA.ORG_OP=10;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=$_kDlnaFlags';
const String _kDlnaMp4Features =
    'DLNA.ORG_PN=AVC_MP4_HP_HD_AAC;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=$_kDlnaFlags';

// =============================================================================
// Cliente SOAP DLNA con throttling inteligente para no saturar el Smart TV
// =============================================================================

/// Evita enviar 3 peticiones SOAP por segundo (`GetPositionInfo`,
/// `GetTransportInfo`, `GetVolume`) al televisor. Muchos Smart TVs (LG webOS,
/// Samsung Tizen, Hisense, TCL) despiertan el OSD/reproductor o se vuelven
/// perezosos cuando reciben 180 POSTs UPnP por minuto.
class _ThrottledDlnaHttpClient extends dc.DlnaHttpClient {
  final http.Client _rawClient = http.Client();

  DateTime? _lastPositionPollAt;
  Duration _lastKnownPosition = Duration.zero;
  Duration _lastKnownDuration = Duration.zero;

  DateTime? _lastTransportPollAt;
  String _lastTransportState = 'PLAYING';

  DateTime? _lastVolumePollAt;
  int _lastVolume = 50;
  bool _hasInitialVolume = false;
  int _confirmPollsRemaining = 2;

  static const Duration _kConfirmPollInterval = Duration(seconds: 3);

  void invalidateCache({int confirmPolls = 2}) {
    _lastPositionPollAt = null;
    _lastTransportPollAt = null;
    _confirmPollsRemaining = confirmPolls;
  }

  @override
  Future<String> sendAction(
    String controlUrl,
    String serviceType,
    String action,
    String body,
  ) async {
    final now = DateTime.now();

    if (action == 'Play' ||
        action == 'Pause' ||
        action == 'Stop' ||
        action == 'Seek' ||
        action == 'SetAVTransportURI') {
      invalidateCache(
        confirmPolls: (action == 'Pause' || action == 'Stop') ? 0 : 2,
      );
      if (action == 'Play') _lastTransportState = 'PLAYING';
      if (action == 'Pause') _lastTransportState = 'PAUSED_PLAYBACK';
      if (action == 'Stop') _lastTransportState = 'STOPPED';
    }

    // 1. Consultar GetVolume solo una vez al inicio (nunca en bucle pasivo),
    // ya que en Xbox y varios Smart TVs GetVolume despierta el OSD en pantalla.
    if (action == 'GetVolume') {
      if (_hasInitialVolume || _lastVolumePollAt != null) {
        return _buildSyntheticVolumeXml(_lastVolume);
      }
      try {
        final xml = await _postSoap(controlUrl, serviceType, action, body);
        _lastVolume = dc.DlnaSoapParser.parseVolume(xml);
        _hasInitialVolume = true;
        _lastVolumePollAt = now;
        return xml;
      } catch (_) {
        _lastVolumePollAt = now;
        return _buildSyntheticVolumeXml(_lastVolume);
      }
    }

    // 2. Una vez confirmada la reproducción (PLAYING), silenciar el polling
    // pasivo de GetPositionInfo e interpolar localmente para no despertar el
    // reproductor/OSD de Xbox ni de Smart TVs durante la película.
    if (action == 'GetPositionInfo') {
      final shouldSkipNetwork = _lastPositionPollAt != null &&
          (_confirmPollsRemaining <= 0 ||
              now.difference(_lastPositionPollAt!) < _kConfirmPollInterval);
      if (shouldSkipNetwork) {
        final elapsed = (_lastTransportState == 'PLAYING' && _lastPositionPollAt != null)
            ? now.difference(_lastPositionPollAt!)
            : Duration.zero;
        final interpolated = _lastKnownPosition + elapsed;
        _lastKnownPosition = interpolated;
        _lastPositionPollAt = now;
        return _buildSyntheticPositionXml(interpolated, _lastKnownDuration);
      }
      try {
        final xml = await _postSoap(controlUrl, serviceType, action, body);
        final parsed = dc.DlnaSoapParser.parsePositionInfo(xml);
        if (parsed.position <= const Duration(seconds: 1) &&
            _lastKnownPosition > const Duration(seconds: 3)) {
          final elapsed = _lastTransportState == 'PLAYING' && _lastPositionPollAt != null
              ? now.difference(_lastPositionPollAt!)
              : Duration.zero;
          _lastKnownPosition += elapsed;
        } else {
          _lastKnownPosition = parsed.position;
        }
        if (parsed.duration > Duration.zero) {
          _lastKnownDuration = parsed.duration;
        }
        _lastPositionPollAt = now;
        return _buildSyntheticPositionXml(_lastKnownPosition, _lastKnownDuration);
      } catch (_) {
        _lastPositionPollAt = now;
        return _buildSyntheticPositionXml(
          _lastKnownPosition,
          _lastKnownDuration,
        );
      }
    }

    // 3. Confirmar PLAYING al iniciar/buscar y luego silenciar GetTransportInfo
    // para no enviar peticiones SOAP periódicas a la Xbox mientras reproduce.
    if (action == 'GetTransportInfo') {
      final shouldSkipNetwork = _lastTransportPollAt != null &&
          (_confirmPollsRemaining <= 0 ||
              now.difference(_lastTransportPollAt!) < _kConfirmPollInterval);
      if (shouldSkipNetwork) {
        return _buildSyntheticTransportXml(_lastTransportState);
      }
      try {
        final xml = await _postSoap(controlUrl, serviceType, action, body);
        final rawState = dc.DlnaSoapParser.parseTransportInfo(xml);
        if ((rawState == 'TRANSITIONING' || rawState == 'BUFFERING') &&
            _lastTransportState == 'PLAYING') {
          _lastTransportPollAt = now;
          return _buildSyntheticTransportXml('PLAYING');
        }
        if (rawState != 'UNKNOWN') {
          _lastTransportState = rawState;
        }
        if (_lastTransportState == 'PLAYING' && _confirmPollsRemaining > 0) {
          _confirmPollsRemaining--;
        }
        _lastTransportPollAt = now;
        return xml;
      } catch (_) {
        _lastTransportPollAt = now;
        return _buildSyntheticTransportXml(_lastTransportState);
      }
    }

    return _postSoap(controlUrl, serviceType, action, body);
  }

  Future<String> _postSoap(
    String controlUrl,
    String serviceType,
    String action,
    String body,
  ) async {
    final uri = Uri.parse(controlUrl);
    final headers = <String, String>{
      'Content-Type': 'text/xml; charset=utf-8',
      'SOAPAction': '"$serviceType#$action"',
      'Connection': 'close',
    };

    http.Response response;
    try {
      response = await _rawClient
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 6));
    } on Exception {
      response = await _rawClient
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 6));
    }

    if (response.statusCode >= 400) {
      throw dc.ProtocolException(
        'DLNA SOAP error: HTTP ${response.statusCode}',
        dc.CastProtocol.dlna,
      );
    }
    return response.body;
  }

  static String _buildSyntheticPositionXml(Duration pos, Duration dur) {
    final rel = dc.NetworkUtils.formatDuration(pos);
    final tot = dc.NetworkUtils.formatDuration(dur);
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
        '<s:Body><u:GetPositionInfoResponse xmlns:u="${dc.DlnaServiceType.avTransport}">'
        '<RelTime>$rel</RelTime><TrackDuration>$tot</TrackDuration>'
        '</u:GetPositionInfoResponse></s:Body></s:Envelope>';
  }

  static String _buildSyntheticTransportXml(String state) {
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
        '<s:Body><u:GetTransportInfoResponse xmlns:u="${dc.DlnaServiceType.avTransport}">'
        '<CurrentTransportState>$state</CurrentTransportState>'
        '</u:GetTransportInfoResponse></s:Body></s:Envelope>';
  }

  static String _buildSyntheticVolumeXml(int volume) {
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
        '<s:Body><u:GetVolumeResponse xmlns:u="${dc.DlnaServiceType.renderingControl}">'
        '<CurrentVolume>$volume</CurrentVolume>'
        '</u:GetVolumeResponse></s:Body></s:Envelope>';
  }

  @override
  void close() {
    _rawClient.close();
    super.close();
  }
}

// =============================================================================
// Acelerador HTTP Local con Prefetching en RAM para HLS y MP4 (DLNA/Chromecast)
// =============================================================================

class _HlsVariantTrack {
  final int trackId;
  final String playlistUrl;
  final List<({String url, double duration})> segments;
  final Duration? totalDuration;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  final Map<int, Future<Uint8List?>> _inFlight = {};
  int _cachedBytes = 0;
  int _activeDownloads = 0;

  static const int _kMaxCachedSegments = 30;
  static const int _kMaxCacheBytes = 96 * 1024 * 1024; // 96 MB max RAM
  static const int _kPrefetchLookahead = 10;
  static const int _kMaxConcurrentPrefetch = 4;

  _HlsVariantTrack({
    required this.trackId,
    required this.playlistUrl,
    required this.segments,
    required this.totalDuration,
  });

  void clear() {
    _cache.clear();
    _inFlight.clear();
    _cachedBytes = 0;
  }

  void prefetchAround(
    int currentIndex,
    Future<Uint8List?> Function(String url) fetcher,
  ) {
    // Evictar segmentos viejos que ya quedaron atrás
    final minKeep = max(0, currentIndex - 1);
    final keysToRemove = _cache.keys.where((k) => k < minKeep).toList();
    for (final k in keysToRemove) {
      final removed = _cache.remove(k);
      if (removed != null) _cachedBytes -= removed.length;
    }

    final maxIdx = min(segments.length - 1, currentIndex + _kPrefetchLookahead);
    for (int idx = currentIndex; idx <= maxIdx; idx++) {
      if (_cache.containsKey(idx) || _inFlight.containsKey(idx)) continue;
      if (_activeDownloads >= _kMaxConcurrentPrefetch && idx > currentIndex) {
        break;
      }
      _startFetch(idx, fetcher);
    }
  }

  Future<Uint8List?> getOrFetch(
    int index,
    Future<Uint8List?> Function(String url) fetcher,
  ) async {
    if (index < 0 || index >= segments.length) return null;

    prefetchAround(index + 1, fetcher);

    final cached = _cache.remove(index);
    if (cached != null) {
      // Reinsertar como MRU
      _cache[index] = cached;
      return cached;
    }

    final existing = _inFlight[index];
    if (existing != null) {
      return existing;
    }

    return _startFetch(index, fetcher);
  }

  Future<Uint8List?> _startFetch(
    int index,
    Future<Uint8List?> Function(String url) fetcher,
  ) {
    if (index < 0 || index >= segments.length) {
      return Future.value(null);
    }
    final segUrl = segments[index].url;
    _activeDownloads++;
    final future = fetcher(segUrl).then((bytes) {
      _activeDownloads = max(0, _activeDownloads - 1);
      _inFlight.remove(index);
      if (bytes != null && bytes.isNotEmpty) {
        _storeInCache(index, bytes);
      }
      return bytes;
    }).catchError((_) {
      _activeDownloads = max(0, _activeDownloads - 1);
      _inFlight.remove(index);
      return null;
    });
    _inFlight[index] = future;
    return future;
  }

  void _storeInCache(int index, Uint8List bytes) {
    if (bytes.length > 14 * 1024 * 1024) return; // No cachear segmentos >14MB
    while ((_cache.length >= _kMaxCachedSegments ||
            _cachedBytes + bytes.length > _kMaxCacheBytes) &&
        _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey);
      if (removed != null) _cachedBytes -= removed.length;
    }
    _cache[index] = bytes;
    _cachedBytes += bytes.length;
  }
}

class _AccelSession {
  final String token;
  final String rootUrl;
  final Map<String, String> headers;
  final Duration initialStartOffset;

  final Map<String, String> playlistTextCache = {};
  final Map<String, Uint8List> resourceCache = {};
  final Map<String, int> playlistUrlToTrackId = {};
  final Map<int, _HlsVariantTrack> tracks = {};
  int _nextTrackId = 0;
  int activeDlnaStreamGen = 0;

  _AccelSession({
    required this.token,
    required this.rootUrl,
    required this.headers,
    this.initialStartOffset = Duration.zero,
  });

  _HlsVariantTrack getOrCreateTrack(String mediaPlaylistUrl, String content) {
    final existingId = playlistUrlToTrackId[mediaPlaylistUrl];
    if (existingId != null && tracks.containsKey(existingId)) {
      return tracks[existingId]!;
    }
    final id = _nextTrackId++;
    final rawSegments = dc.HlsParser.extractSegments(content, mediaPlaylistUrl);
    final segments = rawSegments
        .map((s) => (url: s.url, duration: s.duration))
        .toList(growable: false);
    final total = dc.HlsParser.totalDuration(content);
    final track = _HlsVariantTrack(
      trackId: id,
      playlistUrl: mediaPlaylistUrl,
      segments: segments,
      totalDuration: total,
    );
    playlistUrlToTrackId[mediaPlaylistUrl] = id;
    tracks[id] = track;
    return track;
  }

  void clear() {
    for (final t in tracks.values) {
      t.clear();
    }
    tracks.clear();
    playlistTextCache.clear();
    resourceCache.clear();
  }
}

/// Servidor proxy local con prefetching paralelo en RAM de segmentos HLS (`.ts`)
/// y soporte HTTP/1.1 + DLNA optimizado.
///
/// Resuelve el problema donde cada 4–6 segundos (al terminar cada segmento `.ts`)
/// el televisor se quedaba esperando la descarga remota, mostrando el indicador
/// de carga y activando el reproductor del TV.
class _CastStreamAccelerator {
  _CastStreamAccelerator._();
  static final _CastStreamAccelerator instance = _CastStreamAccelerator._();

  HttpServer? _server;
  HttpClient? _httpClient;
  String? _baseUrl;
  final Map<String, _AccelSession> _sessions = {};
  final Random _random = Random.secure();

  String? get baseUrl => _baseUrl;

  Future<void> start({String? targetDeviceIp}) async {
    final ip = await dc.NetworkUtils.getLocalIpAddress(
      targetDeviceIp: targetDeviceIp,
    );
    final bindAddress = ip ?? '0.0.0.0';

    if (_server != null && _baseUrl != null) {
      if (ip == null || _baseUrl!.contains(ip)) return;
      await stop();
    }

    _httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 8;

    _server = await HttpServer.bind(bindAddress, 0);
    _server!.defaultResponseHeaders.clear();
    _baseUrl = 'http://${ip ?? bindAddress}:${_server!.port}';
    _server!.listen(_handleRequest, onError: (_) {});
    debugPrint('[CastStreamAccelerator] Iniciado en $_baseUrl');
  }

  Future<void> stop() async {
    for (final s in _sessions.values) {
      s.clear();
    }
    _sessions.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = null;
    _baseUrl = null;
  }

  void _cleanupOldSessions({String? keepToken}) {
    final toRemove =
        _sessions.keys.where((k) => k != keepToken).toList(growable: false);
    for (final k in toRemove) {
      _sessions.remove(k)?.clear();
    }
  }

  String _newToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(14, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  /// Pre-carga la playlist HLS en RAM, calcula su duración y arranca el
  /// prefetching de los primeros 4 segmentos antes de que el TV pida el stream.
  Future<Duration?> probeAndWarmupHls(
    String m3u8Url, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final session = _findOrCreateSession(m3u8Url, headers);
      final track = await _resolvePrimaryTrack(session);
      if (track != null) {
        track.prefetchAround(0, (url) => _fetchBytes(url, session.headers));
        return track.totalDuration;
      }
    } catch (e) {
      debugPrint('[CastStreamAccelerator] probeAndWarmupHls error: $e');
    }
    return null;
  }

  String registerHlsForChromecast(
    String m3u8Url, {
    Map<String, String> headers = const {},
  }) {
    final session = _findOrCreateSession(m3u8Url, headers);
    // Calentar playlist y primeros segmentos en background
    unawaited(_resolvePrimaryTrack(session).then((track) {
      track?.prefetchAround(0, (url) => _fetchBytes(url, session.headers));
    }));
    return '$_baseUrl/hls/${session.token}/index.m3u8';
  }

  String registerHlsForDlna(
    String m3u8Url, {
    Map<String, String> headers = const {},
    Duration startOffset = Duration.zero,
  }) {
    final session = _findOrCreateSession(
      m3u8Url,
      headers,
      startOffset: startOffset,
    );
    unawaited(_resolvePrimaryTrack(session).then((track) {
      if (track != null) {
        final startIdx = _findSegmentIndexForTime(track.segments, startOffset);
        track.prefetchAround(
          startIdx,
          (url) => _fetchBytes(url, session.headers),
        );
      }
    }));
    if (startOffset > Duration.zero) {
      final sec = (startOffset.inMilliseconds / 1000.0).toStringAsFixed(3);
      return '$_baseUrl/dlna-ts/${session.token}/stream.ts?t=$sec';
    }
    return '$_baseUrl/dlna-ts/${session.token}/stream.ts';
  }

  String registerDirectMedia(
    String mediaUrl, {
    Map<String, String> headers = const {},
    String ext = '.mp4',
  }) {
    final session = _findOrCreateSession(mediaUrl, headers);
    final cleanExt = ext.startsWith('.') ? ext : '.$ext';
    return '$_baseUrl/direct/${session.token}/video$cleanExt';
  }

  _AccelSession _findOrCreateSession(
    String url,
    Map<String, String> headers, {
    Duration startOffset = Duration.zero,
  }) {
    for (final existing in _sessions.values) {
      if (existing.rootUrl == url) {
        return existing;
      }
    }
    final token = _newToken();
    _cleanupOldSessions(keepToken: token);
    final normalizedHeaders = <String, String>{...headers};
    if (!normalizedHeaders.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      normalizedHeaders['User-Agent'] = _kDefaultCastUserAgent;
    }
    final session = _AccelSession(
      token: token,
      rootUrl: url,
      headers: normalizedHeaders,
      initialStartOffset: startOffset,
    );
    _sessions[token] = session;
    return session;
  }

  Future<_HlsVariantTrack?> _resolvePrimaryTrack(_AccelSession session) async {
    final rootContent = await _fetchPlaylistText(session, session.rootUrl);
    if (rootContent == null || !rootContent.trimLeft().startsWith('#EXTM3U')) {
      return null;
    }
    if (dc.HlsParser.isMasterPlaylist(rootContent)) {
      final variants = dc.HlsParser.extractVariants(
        rootContent,
        session.rootUrl,
      );
      if (variants.isEmpty) return null;
      // Elegir una variante fluida para WiFi (idealmente <= 6.5 Mbps para evitar
      // saturar el buffer del TV, o la primera si no declara bandwidth).
      var picked = variants.first;
      for (final v in variants) {
        if (v.bandwidth > 0 && v.bandwidth <= 6500000) {
          picked = v;
          break;
        }
      }
      final varContent = await _fetchPlaylistText(session, picked.url);
      if (varContent == null) return null;
      return session.getOrCreateTrack(picked.url, varContent);
    }
    return session.getOrCreateTrack(session.rootUrl, rootContent);
  }

  Future<String?> _fetchPlaylistText(_AccelSession session, String url) async {
    final cached = session.playlistTextCache[url];
    if (cached != null) return cached;
    final bytes = await _fetchBytes(url, session.headers);
    if (bytes == null || bytes.isEmpty) return null;
    final text = utf8.decode(bytes, allowMalformed: true);
    // Solo cachear playlists VOD (#EXT-X-ENDLIST) o Master playlists
    if (text.contains('#EXT-X-ENDLIST') ||
        dc.HlsParser.isMasterPlaylist(text)) {
      session.playlistTextCache[url] = text;
    }
    return text;
  }

  Future<Uint8List?> _fetchBytes(
    String url,
    Map<String, String> headers,
  ) async {
    final client = _httpClient;
    if (client == null) return null;
    try {
      final uri = Uri.parse(url);
      final req = await client
          .openUrl('GET', uri)
          .timeout(const Duration(seconds: 8));
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in resp) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      } else {
        await resp.drain<void>();
      }
    } catch (e) {
      debugPrint('[CastStreamAccelerator] Error descargando $url: $e');
    }
    return null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final origin = request.headers.value('Origin');
      _setCorsHeaders(request.response, origin);

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final segments = request.uri.pathSegments;
      if (segments.length >= 3 && segments[0] == 'hls') {
        final token = segments[1];
        final session = _sessions[token];
        if (session == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        await _handleHlsRequest(request, session, segments);
        return;
      }

      if (segments.length >= 3 && segments[0] == 'dlna-ts') {
        final token = segments[1];
        final session = _sessions[token];
        if (session == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        await _handleDlnaTsRequest(request, session);
        return;
      }

      if (segments.length >= 3 && segments[0] == 'direct') {
        final token = segments[1];
        final session = _sessions[token];
        if (session == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        await _handleDirectMediaRequest(request, session);
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Sirve playlists HLS reescritas y segmentos `.ts`/`.m4s` desde la caché RAM
  /// con prefetching automático de los siguientes 4 segmentos.
  Future<void> _handleHlsRequest(
    HttpRequest request,
    _AccelSession session,
    List<String> pathSegments,
  ) async {
    final action = pathSegments[2];

    // 1. Petición de segmento: /hls/<token>/seg/<trackId>/<segIndex>.ts
    if (action == 'seg' && pathSegments.length >= 5) {
      final trackId = int.tryParse(pathSegments[3]);
      final filePart = pathSegments[4].split('.').first;
      final segIndex = int.tryParse(filePart);
      final track = trackId != null ? session.tracks[trackId] : null;
      if (track == null || segIndex == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final bytes = await track.getOrFetch(
        segIndex,
        (url) => _fetchBytes(url, session.headers),
      );
      if (bytes == null || bytes.isEmpty) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }

      request.response.bufferOutput = true;
      request.response.headers.contentType = _sniffSegmentContentType(bytes);
      request.response.headers.set('Accept-Ranges', 'bytes');

      final rangeHeader = request.headers.value('Range');
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final range = _parseByteRange(rangeHeader, bytes.length);
        if (range != null) {
          final slice = Uint8List.sublistView(bytes, range.$1, range.$2 + 1);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            'Content-Range',
            'bytes ${range.$1}-${range.$2}/${bytes.length}',
          );
          request.response.headers.set(
            'Content-Length',
            slice.length.toString(),
          );
          if (request.method != 'HEAD') {
            request.response.add(slice);
          }
          await request.response.close();
          return;
        }
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set('Content-Length', bytes.length.toString());
      if (request.method != 'HEAD') {
        request.response.add(bytes);
      }
      await request.response.close();
      return;
    }

    // 2. Petición de recurso auxiliar (llave AES-128, segmento init EXT-X-MAP, subtítulo)
    if (action == 'res') {
      final targetUrl = request.uri.queryParameters['url'];
      if (targetUrl == null || targetUrl.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      var bytes = session.resourceCache[targetUrl];
      if (bytes == null) {
        bytes = await _fetchBytes(targetUrl, session.headers);
        if (bytes != null && bytes.length <= 2 * 1024 * 1024) {
          session.resourceCache[targetUrl] = bytes;
        }
      }
      if (bytes == null) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }
      request.response.bufferOutput = true;
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set('Content-Length', bytes.length.toString());
      if (request.method != 'HEAD') {
        request.response.add(bytes);
      }
      await request.response.close();
      return;
    }

    // 3. Petición de playlist: /hls/<token>/index.m3u8 o /hls/<token>/playlist.m3u8?url=...
    final playlistUrl = request.uri.queryParameters['url'] ?? session.rootUrl;
    final content = await _fetchPlaylistText(session, playlistUrl);
    if (content == null || !content.trimLeft().startsWith('#EXTM3U')) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    final String rewritten;
    if (dc.HlsParser.isMasterPlaylist(content)) {
      rewritten = _rewriteMasterPlaylist(content, playlistUrl, session);
    } else {
      final track = session.getOrCreateTrack(playlistUrl, content);
      track.prefetchAround(0, (url) => _fetchBytes(url, session.headers));
      rewritten = _rewriteMediaPlaylist(content, playlistUrl, session, track);
    }

    final encoded = utf8.encode(rewritten);
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType(
      'application',
      'x-mpegURL',
    );
    request.response.headers.set('Content-Length', encoded.length.toString());
    if (request.method != 'HEAD') {
      request.response.add(encoded);
    }
    await request.response.close();
  }

  String _rewriteMasterPlaylist(
    String content,
    String baseUrl,
    _AccelSession session,
  ) {
    final lines = content.split(RegExp(r'\r?\n'));
    final buffer = StringBuffer();
    final uriAttrRegex = RegExp(r'URI="([^"]+)"');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        buffer.writeln(line);
        continue;
      }
      if (trimmed.startsWith('#')) {
        if (trimmed.contains('URI="')) {
          final rewrittenTag = line.replaceAllMapped(uriAttrRegex, (m) {
            final resolved = dc.HlsParser.resolveUrl(m.group(1)!, baseUrl);
            final encoded = Uri.encodeComponent(resolved);
            return 'URI="$_baseUrl/hls/${session.token}/playlist.m3u8?url=$encoded"';
          });
          buffer.writeln(rewrittenTag);
        } else {
          buffer.writeln(line);
        }
        continue;
      }
      final resolved = dc.HlsParser.resolveUrl(trimmed, baseUrl);
      final encoded = Uri.encodeComponent(resolved);
      buffer.writeln(
        '$_baseUrl/hls/${session.token}/playlist.m3u8?url=$encoded',
      );
    }
    return buffer.toString();
  }

  String _rewriteMediaPlaylist(
    String content,
    String baseUrl,
    _AccelSession session,
    _HlsVariantTrack track,
  ) {
    final lines = content.split(RegExp(r'\r?\n'));
    final buffer = StringBuffer();
    final uriAttrRegex = RegExp(r'URI="([^"]+)"');
    final isFmp4 = content.contains('#EXT-X-MAP');
    final segExt = isFmp4 ? 'm4s' : 'ts';
    int segIndex = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        buffer.writeln(line);
        continue;
      }
      if (trimmed.startsWith('#')) {
        if (trimmed.contains('URI="')) {
          final rewrittenTag = line.replaceAllMapped(uriAttrRegex, (m) {
            final resolved = dc.HlsParser.resolveUrl(m.group(1)!, baseUrl);
            final encoded = Uri.encodeComponent(resolved);
            return 'URI="$_baseUrl/hls/${session.token}/res?url=$encoded"';
          });
          buffer.writeln(rewrittenTag);
        } else {
          buffer.writeln(line);
        }
        continue;
      }
      final currentIdx = segIndex++;
      buffer.writeln(
        '$_baseUrl/hls/${session.token}/seg/${track.trackId}/$currentIdx.$segExt',
      );
    }
    return buffer.toString();
  }

  /// Sirve el flujo HLS como un stream continuo MPEG-TS (`video/mp2t`) para
  /// televisores DLNA, usando la caché RAM con prefetching paralelo de 4
  /// segmentos y cortando de inmediato si el TV cierra el socket de sondeo.
  Future<void> _handleDlnaTsRequest(
    HttpRequest request,
    _AccelSession session,
  ) async {
    final track = await _resolvePrimaryTrack(session);
    if (track == null || track.segments.isEmpty) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    // Calcular desplazamiento temporal si el TV o el usuario hizo seek
    final seekHeader =
        request.headers.value('TimeSeekRange.dlna.org') ??
        request.headers.value('X-Seek-Range');
    var startAt = dc.MediaProxy.parseTimeSeekRange(seekHeader);
    if (startAt == Duration.zero) {
      final tParam = request.uri.queryParameters['t'];
      final sec = tParam != null ? double.tryParse(tParam) : null;
      if (sec != null && sec > 0) {
        startAt = Duration(milliseconds: (sec * 1000).round());
      } else if (session.initialStartOffset > Duration.zero) {
        startAt = session.initialStartOffset;
      }
    }

    final startIndex = _findSegmentIndexForTime(track.segments, startAt);
    double startSeconds = 0.0;
    for (int i = 0; i < startIndex && i < track.segments.length; i++) {
      startSeconds += track.segments[i].duration;
    }

    final response = request.response;
    response.bufferOutput = true;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('video', 'mp2t');
    response.headers.set('Accept-Ranges', 'none');
    response.headers.set('transferMode.dlna.org', 'Streaming');
    response.headers.set('contentFeatures.dlna.org', _kDlnaTsFeatures);

    final total = track.totalDuration;
    if (total != null && total > Duration.zero) {
      final totalSeconds = total.inMilliseconds / 1000.0;
      response.headers.set(
        'TimeSeekRange.dlna.org',
        'npt=${startSeconds.toStringAsFixed(3)}-'
            '${totalSeconds.toStringAsFixed(3)}/'
            '${totalSeconds.toStringAsFixed(3)}',
      );
      response.headers.set(
        'X-Seek-Range',
        'npt=${startSeconds.toStringAsFixed(3)}-'
            '${totalSeconds.toStringAsFixed(3)}',
      );
    }

    // Si el Smart TV solo envió HEAD para inspeccionar cabeceras, responder
    // de inmediato sin descargar segmentos.
    if (request.method == 'HEAD') {
      track.prefetchAround(
        startIndex,
        (url) => _fetchBytes(url, session.headers),
      );
      await response.close();
      return;
    }

    final myGen = ++session.activeDlnaStreamGen;
    bool clientDisconnected = false;
    response.done
        .then((_) => clientDisconnected = true)
        .catchError((_) => clientDisconnected = true);

    track.prefetchAround(
      startIndex,
      (url) => _fetchBytes(url, session.headers),
    );

    for (int i = startIndex; i < track.segments.length; i++) {
      if (clientDisconnected) break;
      // Si el TV abrió una nueva conexión de reproducción (p.ej. seek o reconexión),
      // abortar la conexión vieja para no saturar ancho de banda.
      if (session.activeDlnaStreamGen != myGen) {
        break;
      }

      final bytes = await track.getOrFetch(
        i,
        (url) => _fetchBytes(url, session.headers),
      );
      if (clientDisconnected) break;
      if (bytes == null || bytes.isEmpty) continue;

      try {
        response.add(bytes);
        // NO llamamos response.flush() en cada segmento para permitir que el buffer
        // del socket fluya en paralelo a la descarga del siguiente segmento sin pausas.
      } catch (_) {
        // El Smart TV cerró el socket (p. ej. fin del probe inicial o Stop).
        clientDisconnected = true;
        break;
      }
    }

    try {
      await response.close();
    } catch (_) {}
  }

  /// Proxy directo para MP4/MKV con soporte real de `HEAD`, `Range: bytes=...`,
  /// cabeceras DLNA y cancelación inmediata de la descarga si el TV cierra el socket.
  Future<void> _handleDirectMediaRequest(
    HttpRequest request,
    _AccelSession session,
  ) async {
    final client = _httpClient;
    if (client == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final uri = Uri.parse(session.rootUrl);
    final isHead = request.method == 'HEAD';
    HttpClientRequest upstreamReq;
    HttpClientResponse upstreamResp;

    try {
      upstreamReq = await client
          .openUrl(isHead ? 'HEAD' : 'GET', uri)
          .timeout(const Duration(seconds: 8));
      session.headers.forEach((k, v) => upstreamReq.headers.set(k, v));
      final rangeHeader = request.headers.value('Range');
      if (rangeHeader != null) {
        upstreamReq.headers.set('Range', rangeHeader);
      }
      upstreamResp = await upstreamReq.close().timeout(
        const Duration(seconds: 10),
      );

      // Algunos CDNs rechazan HEAD con 405/403; caer a GET con Range: bytes=0-0
      if (isHead && upstreamResp.statusCode >= 400) {
        await upstreamResp.drain<void>();
        upstreamReq = await client
            .openUrl('GET', uri)
            .timeout(const Duration(seconds: 8));
        session.headers.forEach((k, v) => upstreamReq.headers.set(k, v));
        upstreamReq.headers.set('Range', 'bytes=0-0');
        upstreamResp = await upstreamReq.close().timeout(
          const Duration(seconds: 10),
        );
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    final response = request.response;
    response.bufferOutput = true;
    response.statusCode = isHead && upstreamResp.statusCode == 206
        ? HttpStatus.ok
        : upstreamResp.statusCode;

    final upType = upstreamResp.headers.contentType;
    response.headers.contentType = upType ?? ContentType('video', 'mp4');
    response.headers.set('Accept-Ranges', 'bytes');
    response.headers.set('transferMode.dlna.org', 'Streaming');
    response.headers.set('contentFeatures.dlna.org', _kDlnaMp4Features);

    final contentRange = upstreamResp.headers.value('Content-Range');
    final contentLength = upstreamResp.headers.value('Content-Length');
    if (isHead && contentRange != null && contentRange.contains('/')) {
      final totalStr = contentRange.split('/').last.trim();
      if (int.tryParse(totalStr) != null) {
        response.headers.set('Content-Length', totalStr);
      }
    } else {
      if (contentRange != null) {
        response.headers.set('Content-Range', contentRange);
      }
      if (contentLength != null) {
        response.headers.set('Content-Length', contentLength);
      }
    }

    if (isHead) {
      await upstreamResp.drain<void>();
      await response.close();
      return;
    }

    StreamSubscription<List<int>>? sub;
    final completer = Completer<void>();

    sub = upstreamResp.listen(
      (chunk) {
        try {
          response.add(chunk);
        } catch (_) {
          sub?.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    response.done.then((_) {
      sub?.cancel();
      if (!completer.isCompleted) completer.complete();
    }).catchError((_) {
      sub?.cancel();
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;
    try {
      await response.close();
    } catch (_) {}
  }

  static int _findSegmentIndexForTime(
    List<({String url, double duration})> segments,
    Duration target,
  ) {
    if (target <= Duration.zero || segments.isEmpty) return 0;
    final targetSec = target.inMilliseconds / 1000.0;
    double elapsed = 0.0;
    for (int i = 0; i < segments.length; i++) {
      if (elapsed + segments[i].duration > targetSec) {
        return i;
      }
      elapsed += segments[i].duration;
    }
    return max(0, segments.length - 1);
  }

  static ContentType _sniffSegmentContentType(Uint8List bytes) {
    if (bytes.isNotEmpty && bytes[0] == 0x47) {
      return ContentType('video', 'mp2t');
    }
    if (bytes.length >= 8) {
      final box = String.fromCharCodes(bytes.sublist(4, 8));
      if (box == 'ftyp' ||
          box == 'moof' ||
          box == 'styp' ||
          box == 'sidx' ||
          box == 'emsg') {
        return ContentType('video', 'mp4');
      }
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0) {
      return ContentType('audio', 'aac');
    }
    return ContentType('video', 'mp2t');
  }

  static (int, int)? _parseByteRange(String rangeHeader, int totalLength) {
    if (!rangeHeader.startsWith('bytes=') || totalLength <= 0) return null;
    final spec = rangeHeader.substring('bytes='.length).split(',').first.trim();
    final parts = spec.split('-');
    if (parts.length != 2) return null;
    int start = 0;
    int end = totalLength - 1;
    if (parts[0].isEmpty) {
      final suffix = int.tryParse(parts[1]);
      if (suffix == null || suffix <= 0) return null;
      start = (totalLength - suffix).clamp(0, totalLength - 1);
    } else {
      final parsedStart = int.tryParse(parts[0]);
      if (parsedStart == null) return null;
      start = parsedStart;
      if (parts[1].isNotEmpty) {
        final parsedEnd = int.tryParse(parts[1]);
        if (parsedEnd != null) {
          end = parsedEnd.clamp(0, totalLength - 1);
        }
      }
    }
    if (start > end || start >= totalLength) return null;
    return (start, end);
  }

  static void _setCorsHeaders(HttpResponse response, String? origin) {
    response.headers.set(
      'Access-Control-Allow-Origin',
      (origin != null && origin.isNotEmpty) ? origin : '*',
    );
    response.headers.set('Vary', 'Origin');
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, HEAD, OPTIONS',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Range, Content-Type, Accept, Accept-Encoding, Origin',
    );
    response.headers.set(
      'Access-Control-Expose-Headers',
      'Content-Length, Content-Range, Accept-Ranges',
    );
  }
}

// =============================================================================
// Adaptadores de MediaProxy y MediaTransformer para dart_cast
// =============================================================================

class _PrefetchingMediaProxy extends dc.MediaProxy {
  @override
  Future<void> start({int? port, String? targetDeviceIp}) async {
    await super.start(port: port, targetDeviceIp: targetDeviceIp);
    await _CastStreamAccelerator.instance.start(
      targetDeviceIp: targetDeviceIp,
    );
  }

  @override
  Future<Duration?> probeHlsDuration(
    String m3u8Url, {
    Map<String, String> headers = const {},
  }) {
    return _CastStreamAccelerator.instance.probeAndWarmupHls(
      m3u8Url,
      headers: headers,
    );
  }

  @override
  String registerHlsAsStream(
    String m3u8Url, {
    Map<String, String> headers = const {},
  }) {
    return _CastStreamAccelerator.instance.registerHlsForDlna(
      m3u8Url,
      headers: headers,
    );
  }

  @override
  String registerMedia(
    String url, {
    Map<String, String> headers = const {},
    String? pathExtension,
    bool stripDvbTables = true,
  }) {
    final lower = url.toLowerCase();
    if (!lower.endsWith('.vtt') &&
        !lower.endsWith('.srt') &&
        pathExtension != 'vtt') {
      final ext = lower.contains('.mkv') ? '.mkv' : '.mp4';
      return _CastStreamAccelerator.instance.registerDirectMedia(
        url,
        headers: headers,
        ext: ext,
      );
    }
    return super.registerMedia(
      url,
      headers: headers,
      pathExtension: pathExtension,
      stripDvbTables: stripDvbTables,
    );
  }
}

class _AcceleratedChromecastTransformer extends dc.TsHlsMediaTransformer {
  final String deviceIp;

  const _AcceleratedChromecastTransformer({required this.deviceIp})
      : super(wrapRemoteTs: true);

  @override
  Future<dc.TransformedMedia> transform(
    dc.CastMedia media,
    dc.MediaProxy proxy,
  ) async {
    if (media.isLocalFile) {
      return super.transform(media, proxy);
    }
    await _CastStreamAccelerator.instance.start(targetDeviceIp: deviceIp);
    final cleanHeaders = Map<String, String>.from(media.httpHeaders);
    final isWrappedHls = cleanHeaders.remove('x-pelisapp-hls') == '1';

    if (isWrappedHls || media.type == dc.CastMediaType.hls) {
      final accelUrl = _CastStreamAccelerator.instance.registerHlsForChromecast(
        media.url,
        headers: cleanHeaders,
      );
      return dc.TransformedMedia(
        proxyUrl: accelUrl,
        effectiveType: dc.CastMediaType.hls,
      );
    }

    final ext = media.type == dc.CastMediaType.mkv ? '.mkv' : '.mp4';
    final accelUrl = _CastStreamAccelerator.instance.registerDirectMedia(
      media.url,
      headers: cleanHeaders,
      ext: ext,
    );
    return dc.TransformedMedia(
      proxyUrl: accelUrl,
      effectiveType: media.type,
    );
  }
}

// =============================================================================
// Servicio central de Casting unificado (DLNA, Chromecast, AirPlay)
// =============================================================================

/// Servicio central de Casting unificado (pure Dart: DLNA, Chromecast, AirPlay)
/// Utiliza `dart_cast` junto con `_CastStreamAccelerator` para prefetching
/// paralelo de segmentos HLS en RAM y throttling SOAP UPnP en Smart TVs.
class CastService {
  CastService._internal();
  static final CastService instance = CastService._internal();
  factory CastService() => instance;

  late final dc.CastService _dcService = dc.CastService(
    discoveryProviders: [
      dc.ChromecastDiscoveryProvider(),
      dc.AirPlayDiscoveryProvider(),
      dc.DlnaDiscoveryProvider(),
    ],
    sessionFactory: (device) {
      switch (device.protocol) {
        case dc.CastProtocol.chromecast:
          return dc.ChromecastSession(
            device: device,
            mediaTransformer: _AcceleratedChromecastTransformer(
              deviceIp: device.address.address,
            ),
          );
        case dc.CastProtocol.airplay:
          return dc.AirPlaySession(device);
        case dc.CastProtocol.dlna:
          return _createOptimizedDlnaSession(device);
      }
    },
  );

  static dc.DlnaSession _createOptimizedDlnaSession(dc.CastDevice device) {
    final avTransportUrl = device.metadata['avTransportControlUrl'];
    final renderingControlUrl = device.metadata['renderingControlUrl'];
    if (avTransportUrl == null || avTransportUrl.isEmpty) {
      return dc.DlnaSession.fromDevice(device);
    }
    final description = dc.DlnaDeviceDescription(
      friendlyName: device.name,
      udn: device.id,
      manufacturer: device.metadata['manufacturer'],
      modelName: device.metadata['modelName'],
      avTransportControlUrl: avTransportUrl,
      renderingControlUrl: renderingControlUrl,
      connectionManagerControlUrl:
          device.metadata['connectionManagerControlUrl'],
      locationUrl: 'http://${device.address.address}:${device.port}',
    );
    return dc.DlnaSession(
      device: device,
      description: description,
      httpClient: _ThrottledDlnaHttpClient(),
      proxy: _PrefetchingMediaProxy(),
    );
  }

  dc.CastSession? _activeSession;
  dc.CastSession? get activeSession => _activeSession;

  dc.CastDevice? _connectedDevice;
  dc.CastDevice? get connectedDevice => _connectedDevice;

  final ValueNotifier<CastState> stateNotifier =
      ValueNotifier<CastState>(CastState.idle);
  CastState get state => stateNotifier.value;

  final ValueNotifier<bool> isRemotePlaying = ValueNotifier<bool>(false);

  String? _lastError;
  String? get lastError => _lastError;

  final List<dc.CastDevice> _devices = [];
  List<dc.CastDevice> get devices => List.unmodifiable(_devices);

  final StreamController<List<dc.CastDevice>> _devicesController =
      StreamController<List<dc.CastDevice>>.broadcast();

  StreamSubscription<List<dc.CastDevice>>? _discoverySub;
  StreamSubscription<dc.SessionState>? _sessionStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _discoveryTimeoutTimer;
  Timer? _bufferingDebounceTimer;

  Duration _position = Duration.zero;
  Duration get position => _position;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionController.stream;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  Stream<Duration> get durationStream => _durationController.stream;

  /// Inicialización retrocompatible (no-op en dart_cast pure Dart)
  Future<void> init() async {}

  /// Inicia el descubrimiento de dispositivos en la red local (DLNA, Chromecast, AirPlay)
  Stream<List<dc.CastDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 10),
  }) {
    _startDiscovery(timeout);
    return _devicesController.stream;
  }

  Future<void> _startDiscovery(Duration timeout) async {
    _devices.clear();
    _devicesController.add(List.unmodifiable(_devices));
    _lastError = null;
    stateNotifier.value = CastState.discovering;

    _discoverySub?.cancel();
    _discoveryTimeoutTimer?.cancel();

    try {
      final stream = _dcService.startDiscovery(timeout: timeout);
      _discoverySub = stream.listen(
        (list) {
          _devices.clear();
          final seenIds = <String>{};
          for (final d in list) {
            if (d.name.trim().isNotEmpty && seenIds.add(d.id)) {
              _devices.add(d);
            }
          }
          _devicesController.add(List.unmodifiable(_devices));
          if (_devices.isNotEmpty && state == CastState.discovering) {
            _lastError = null;
          }
        },
        onError: (err) {
          debugPrint('[CastService] discovery error: $err');
        },
        onDone: () {
          if (state == CastState.discovering) {
            stateNotifier.value =
                _devices.isNotEmpty ? CastState.idle : CastState.error;
            if (_devices.isEmpty) {
              _lastError =
                  'No se encontraron dispositivos. Asegúrate de estar en la misma red WiFi y que el dispositivo esté encendido.';
            }
          }
        },
      );
    } catch (e) {
      debugPrint('[CastService] startDiscovery error: $e');
    }

    _discoveryTimeoutTimer = Timer(timeout, () {
      if (_devices.isEmpty && state == CastState.discovering) {
        _lastError =
            'No se encontraron dispositivos. Asegúrate de estar en la misma red WiFi y que el dispositivo esté encendido.';
        stateNotifier.value = CastState.error;
      } else if (state == CastState.discovering) {
        stateNotifier.value = CastState.idle;
      }
    });
  }

  /// Conecta con el dispositivo seleccionado
  Future<bool> connectToDevice(String deviceId) async {
    _lastError = null;
    dc.CastDevice? targetDevice;
    try {
      targetDevice = _devices.firstWhere(
        (d) => d.id == deviceId,
      );
    } catch (_) {
      if (_connectedDevice != null && _connectedDevice!.id == deviceId) {
        targetDevice = _connectedDevice;
      }
    }

    if (targetDevice == null) {
      _lastError = 'Dispositivo no encontrado en la red.';
      stateNotifier.value = CastState.error;
      return false;
    }

    try {
      await _CastStreamAccelerator.instance.start(
        targetDeviceIp: targetDevice.address.address,
      );
      final session = await _dcService.connect(targetDevice);
      _activeSession = session;
      _connectedDevice = targetDevice;
      _attachSessionListeners(session);
      stateNotifier.value = CastState.connected;
      return true;
    } catch (e) {
      debugPrint('[CastService] connect error: $e');
      _lastError = 'Error al conectar con ${targetDevice.name}.';
      stateNotifier.value = CastState.error;
      return false;
    }
  }

  void _attachSessionListeners(dc.CastSession session) {
    _sessionStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingDebounceTimer?.cancel();

    _sessionStateSub = session.stateStream.listen((sessState) {
      debugPrint('[CastService] Session state: $sessState');
      switch (sessState) {
        case dc.SessionState.connecting:
        case dc.SessionState.connected:
          _bufferingDebounceTimer?.cancel();
          stateNotifier.value = CastState.connected;
          break;
        case dc.SessionState.playing:
          _bufferingDebounceTimer?.cancel();
          stateNotifier.value = CastState.casting;
          isRemotePlaying.value = true;
          break;
        case dc.SessionState.loading:
        case dc.SessionState.buffering:
          stateNotifier.value = CastState.casting;
          // No cambiar isRemotePlaying a false en micro-buffers (<2s) para
          // evitar parpadeos de controles y notificaciones.
          _bufferingDebounceTimer?.cancel();
          _bufferingDebounceTimer = Timer(const Duration(seconds: 2), () {
            if (_activeSession?.state == dc.SessionState.buffering ||
                _activeSession?.state == dc.SessionState.loading) {
              isRemotePlaying.value = false;
            }
          });
          break;
        case dc.SessionState.paused:
          _bufferingDebounceTimer?.cancel();
          stateNotifier.value = CastState.casting;
          isRemotePlaying.value = false;
          break;
        case dc.SessionState.idle:
          _bufferingDebounceTimer?.cancel();
          isRemotePlaying.value = false;
          if (stateNotifier.value == CastState.casting) {
            stateNotifier.value = CastState.connected;
          }
          break;
        case dc.SessionState.disconnected:
          _bufferingDebounceTimer?.cancel();
          isRemotePlaying.value = false;
          _activeSession = null;
          _connectedDevice = null;
          stateNotifier.value = CastState.idle;
          break;
      }
    });

    _positionSub = session.positionStream.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _durationSub = session.durationStream.listen((dur) {
      if (dur > Duration.zero) {
        _duration = dur;
        _durationController.add(dur);
      }
    });
  }

  /// Envía la URL del video y metadatos con cabeceras HTTP (Referer / User-Agent)
  /// al dispositivo remoto a través del acelerador con prefetching en RAM.
  Future<bool> castMedia(
    String videoUrl, {
    String? title,
    String? posterUrl,
    Map<String, String>? headers,
    Duration? startPosition,
    Duration? duration,
  }) async {
    if (_activeSession == null || _connectedDevice == null) {
      _lastError = 'No hay ningún dispositivo conectado para enviar el video.';
      stateNotifier.value = CastState.error;
      return false;
    }

    final cleanUrl = videoUrl.trim();
    if (cleanUrl.isEmpty) {
      _lastError = 'La URL del video aún no está disponible.';
      stateNotifier.value = CastState.error;
      return false;
    }

    stateNotifier.value = CastState.casting;
    _lastError = null;
    if (duration != null && duration > Duration.zero) {
      _duration = duration;
      _durationController.add(duration);
    }

    try {
      final httpHeaders = Map<String, String>.from(headers ?? {});
      if (!httpHeaders.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        httpHeaders['User-Agent'] = _kDefaultCastUserAgent;
      }

      final detectedType = await _detectAndWarmupMediaType(
        cleanUrl,
        httpHeaders,
        targetDeviceIp: _connectedDevice!.address.address,
      );

      final isChromecast =
          _connectedDevice!.protocol == dc.CastProtocol.chromecast;
      // Para Chromecast + HLS usamos _AcceleratedChromecastTransformer
      // pasando CastMediaType.mpegTs con la marca 'x-pelisapp-hls': '1'
      // para que Chromecast consuma directamente el playlist acelerado
      // en un solo salto y con prefetching de 4 segmentos en RAM.
      final effectiveMediaType =
          (isChromecast && detectedType == dc.CastMediaType.hls)
              ? dc.CastMediaType.mpegTs
              : detectedType;
      if (isChromecast && detectedType == dc.CastMediaType.hls) {
        httpHeaders['x-pelisapp-hls'] = '1';
      }

      final media = dc.CastMedia(
        url: cleanUrl,
        type: effectiveMediaType,
        title: title,
        imageUrl: posterUrl,
        httpHeaders: httpHeaders,
        startPosition:
            (startPosition != null && startPosition > const Duration(seconds: 5))
                ? startPosition
                : null,
        duration: (duration != null && duration > Duration.zero)
            ? duration
            : null,
      );

      await _activeSession!.loadMedia(media);
      isRemotePlaying.value = true;
      return true;
    } catch (e) {
      debugPrint('[CastService] castMedia error: $e');
      _lastError =
          'Este dispositivo no puede reproducir este formato. Prueba con otro contenido.';
      stateNotifier.value = CastState.error;
      return false;
    }
  }

  /// Reanuda la reproducción remota
  Future<void> play() async {
    if (_activeSession == null) return;
    try {
      await _activeSession!.play();
      isRemotePlaying.value = true;
    } catch (e) {
      debugPrint('[CastService] play error: $e');
    }
  }

  /// Pausa la reproducción remota
  Future<void> pause() async {
    if (_activeSession == null) return;
    try {
      await _activeSession!.pause();
      isRemotePlaying.value = false;
    } catch (e) {
      debugPrint('[CastService] pause error: $e');
    }
  }

  /// Detiene la reproducción remota
  Future<void> stop() async {
    if (_activeSession == null) return;
    try {
      await _activeSession!.stop();
      isRemotePlaying.value = false;
      stateNotifier.value = CastState.connected;
    } catch (e) {
      debugPrint('[CastService] stop error: $e');
    }
  }

  /// Salta a una posición específica en el dispositivo remoto
  Future<void> seek(Duration position) async {
    if (_activeSession == null) return;
    try {
      _position = position;
      _positionController.add(position);
      await _activeSession!.seek(position);
    } catch (e) {
      debugPrint('[CastService] seek error: $e');
    }
  }

  /// Cierra la conexión, detiene la reproducción remota y resetea el servicio
  Future<void> disconnect() async {
    _discoveryTimeoutTimer?.cancel();
    _bufferingDebounceTimer?.cancel();
    _discoverySub?.cancel();
    _sessionStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();

    if (_activeSession != null) {
      try {
        await _activeSession!.stop();
      } catch (_) {}
      try {
        await _activeSession!.disconnect();
      } catch (_) {}
      _activeSession = null;
    }

    await _CastStreamAccelerator.instance.stop();

    _connectedDevice = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    isRemotePlaying.value = false;
    stateNotifier.value = CastState.idle;
  }

  static Future<dc.CastMediaType> _detectAndWarmupMediaType(
    String url,
    Map<String, String> headers, {
    String? targetDeviceIp,
  }) async {
    await _CastStreamAccelerator.instance.start(targetDeviceIp: targetDeviceIp);
    final staticType = _detectMediaType(url);
    if (staticType == dc.CastMediaType.hls) {
      unawaited(
        _CastStreamAccelerator.instance.probeAndWarmupHls(
          url,
          headers: headers,
        ),
      );
      return dc.CastMediaType.hls;
    }
    return staticType;
  }

  static dc.CastMediaType _detectMediaType(String url) {
    final lower = url.toLowerCase();
    final pathOnly = lower.split('?').first;
    if (pathOnly.endsWith('.mp4') || pathOnly.endsWith('.m4v')) {
      return dc.CastMediaType.mp4;
    }
    if (pathOnly.endsWith('.mkv')) {
      return dc.CastMediaType.mkv;
    }
    if (lower.contains('.m3u8') ||
        lower.contains('.m3u') ||
        lower.contains('hls') ||
        lower.contains('format=m3u8') ||
        pathOnly.endsWith('.txt') ||
        pathOnly.contains('/master')) {
      return dc.CastMediaType.hls;
    }
    if (pathOnly.endsWith('.ts')) {
      return dc.CastMediaType.mpegTs;
    }
    if (lower.contains('.mkv')) {
      return dc.CastMediaType.mkv;
    }
    return dc.CastMediaType.mp4;
  }
}
