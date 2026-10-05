import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/services/ad_pause_overlay.dart';

import '../../content/presentation/content_page.dart';
import 'subtitles/subtitle_widget.dart';
import 'quality/quality_selector.dart';
import 'subtitles/subtitle_selector.dart'; // ← NUEVO
import '../../../core/services/cast_service.dart';
import 'widgets/dlna_cast_sheet.dart';
import 'widgets/dlna_remote_control_bar.dart';
import 'widgets/dlna_casting_overlay.dart';
import '../../../core/services/dlna_helper.dart';
import 'widgets/mobile_skip_next_overlay.dart';
import '../../../data/datasources/remote/tmdb/tmdb_player_api.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/server_prevalidation_service.dart';
import '../../../core/services/remote_config_service.dart';
import '../../../core/services/server_loader_shared.dart';
import '../../../data/scrapers/base/registry.dart';

class _SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  const _SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

enum _VideoFitMode { contain, cover, fill, fitWidth, fitHeight }

class PlayerScreen extends StatefulWidget {
  /// Si viene vacío, el player resuelve con ServerLoader (caché / fuentes).
  final String videoUrl;
  final int idcontenido;
  final int? temporada;
  final int? capitulo;
  final String tipo;
  final String titulo;
  final int? tmdbId;
  final String? idioma;
  final Map<String, String>? headers;
  final bool isLive;
  final String? liveLogo;

  const PlayerScreen({
    super.key,
    this.videoUrl = '',
    required this.idcontenido,
    this.temporada,
    this.capitulo,
    required this.tipo,
    required this.titulo,
    this.tmdbId,
    this.idioma,
    this.headers,
    this.isLive = false,
    this.liveLogo,
    this.liveStreams,
    this.allChannels,
    this.initialChannelIndex = -1,
  });

  final List<String>? liveStreams;
  final List<dynamic>? allChannels;
  final int initialChannelIndex;

  static void openLiveChannel(
    BuildContext context,
    dynamic channel, {
    List<dynamic>? allChannels,
    int? currentChannelIndex,
  }) {
    List<String> streams = [];
    try {
      streams = List<String>.from(channel.allStreamUrls);
    } catch (_) {
      try {
        streams = [channel.streamUrl?.toString() ?? ''];
      } catch (_) {}
    }
    if (streams.isEmpty && channel.streamUrl != null) {
      streams = [channel.streamUrl.toString()];
    }

    final chanIdx = currentChannelIndex ?? (allChannels != null ? allChannels.indexOf(channel) : -1);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoUrl: streams.isNotEmpty ? streams.first : (channel.streamUrl ?? ''),
          idcontenido: channel.id.hashCode,
          tipo: 'live',
          titulo: channel.name,
          isLive: true,
          liveLogo: channel.logo,
          liveStreams: streams,
          allChannels: allChannels,
          initialChannelIndex: chanIdx,
        ),
      ),
    );
  }

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color netflixRed = Color(0xFFFF6B35);

  /// Contador de players activos: solo restauramos orientación
  /// cuando el ÚLTIMO player se cierra (evita vertical al pushReplacement).
  static int _activePlayers = 0;

  final TmdbPlayerService _tmdbPlayer = TmdbPlayerService();
  final ServerLoader _serverLoader = ServerLoader();
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );

  late VideoPlayerController _controller;
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _hasStartedPlaying = false;
  bool _subtitlesEnabled = false;
  String? _switchingLangOverlay;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String _errorMessage = '';
  bool _showControls = true;
  bool _isBuffering = false;
  Timer? _hideControlsTimer;
  Timer? _vodWatchdogTimer;
  Timer? _audioCheckTimer;
  bool _isSwitchingServerNotice = false;
  bool _isDragging = false;
  bool _isDisposing = false;
  bool _controllerReady = false;
  int _currentLiveIndex = 0;

  List<_SubtitleCue> _subtitleCues = const [];
  String _currentSubtitleText = '';

  // OpenSubtitles state
  String? _selectedSubtitleId;
  String _selectedSubtitleLabel = 'Subs';
  double _subtitleOffsetSec = 0.0;
  double _subtitleFontSize = 18.0;
  bool _subtitleBold = true;
  double _subtitleVerticalOffset = 0.0;

  static const String _prefSubIdKey = 'player_sub_id_';
  static const String _prefSubUrlKey = 'player_sub_url_';
  static const String _prefSubLangKey = 'player_sub_lang_';
  static const String _prefSubOffsetKey = 'subtitulo_offset_sec';
  static const String _prefSubFontKey = 'subtitulo_font_size';
  static const String _prefSubBoldKey = 'subtitulos_negrita';
  static const String _prefSubVertKey = 'subtitulo_vertical_offset';

  Map<String, dynamic>? _apiData;
  String? _backdropUrl;
  String? _logoUrl;
  String _tituloContenido = '';
  String? _tituloCapitulo;
  String? _capituloFmt;
  List<dynamic> _temporadas = const [];
  List<dynamic> _recomendaciones = const [];
  int _selectedSeasonIndex = 0;
  Map<String, dynamic>? _siguiente;
  String _idioma = 'ES';

  String _currentQualityLabel = 'Auto';
  String? _currentQualityUrl;

  // URL activa y cola de fallback (ServerLoader)
  String _activeUrl = '';
  Map<String, String> _activeHeaders = {};
  List<Map<String, dynamic>> _fallbackServers = [];
  int _fallbackIndex = 0;
  bool _isResolving = false;
  bool _allServersFailed = false;
  int _consecutiveServerFailures = 0;
  Timer? _loadingLongTimer;
  bool _showTryAnotherServer = false;

  // ── Bloque D.6: Resiliencia ante cortes de red ──
  Timer? _reconnectTimer;
  Timer? _reconnectCountdownTimer;
  bool _isReconnecting = false;
  int _reconnectRemainingSec = 60;
  DateTime? _bufferingStartTime;

  void _startReconnectTolerance() {
    if (_isReconnecting || !mounted || _isDisposing) return;
    final timeoutSec = RemoteConfigService.instance.config.player.reconnectTimeoutSeconds;
    final showOverlay = RemoteConfigService.instance.config.player.showReconnectOverlay;

    setState(() {
      _isReconnecting = showOverlay;
      _reconnectRemainingSec = timeoutSec;
    });

    _reconnectCountdownTimer?.cancel();
    _reconnectCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _isDisposing || !_isReconnecting) {
        t.cancel();
        return;
      }
      setState(() {
        if (_reconnectRemainingSec > 0) {
          _reconnectRemainingSec--;
        }
      });
    });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: timeoutSec), () async {
      if (!mounted || _isDisposing) return;
      _cancelReconnectTolerance(recovered: false);
      await _handleReconnectionTimeoutFallback();
    });
  }

  void _cancelReconnectTolerance({bool recovered = true}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectCountdownTimer?.cancel();
    _reconnectCountdownTimer = null;
    _bufferingStartTime = null;

    if (_isReconnecting && mounted) {
      setState(() {
        _isReconnecting = false;
      });
      if (recovered) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.wifi_rounded, color: Colors.greenAccent, size: 20),
                SizedBox(width: 8),
                Text('Conexión restaurada'),
              ],
            ),
            backgroundColor: Color(0xFF1E1E24),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleReconnectionTimeoutFallback() async {
    if (!mounted || _isDisposing) return;

    final fallbackLower = RemoteConfigService.instance.config.player.fallbackToLowerQualityFirst;
    final savedPos = _currentPosition;

    if (fallbackLower && _activeUrl.contains('.m3u8')) {
      try {
        final variants = await HlsQualityParser.parse(_activeUrl);
        final lower = variants.where((q) => !q.isAuto && (q.height == null || q.height! <= 720)).toList();
        if (lower.isNotEmpty) {
          final target = lower.first;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cambiando a un servidor más estable...'),
                backgroundColor: Color(0xFF1E1E24),
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          await _selectQuality(target);
          return;
        }
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cambiando a un servidor más estable...'),
          backgroundColor: Color(0xFF1E1E24),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (_fallbackIndex < _fallbackServers.length) {
      _serverLoader.markServerAsInvalid(_fallbackServers[_fallbackIndex]);
    }
    await _tryNextServer(reason: 'Tiempo de reconexión agotado (60s)');
    if (_controllerReady && savedPos > const Duration(seconds: 2)) {
      try {
        await _controller.seekTo(savedPos);
      } catch (_) {}
    }
  }

  void _startLoadingTimer() {
    _loadingLongTimer?.cancel();
    _showTryAnotherServer = false;
    _loadingLongTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isLoading) {
        setState(() => _showTryAnotherServer = true);
      }
    });
  }

  void _stopLoadingTimer() {
    _loadingLongTimer?.cancel();
    _loadingLongTimer = null;
    if (_showTryAnotherServer && mounted) {
      setState(() => _showTryAnotherServer = false);
    }
  }

  int _lastPositionUpdateMs = 0;
  static const int _positionThrottleMs = 250;

  bool _showEndPrompt = false;
  bool _hasHandledEnd = false;
  bool _showBottomPanel = false;
  bool _showNextButton = false;
  bool _preloadTriggered = false;

  double? _introStartSec;
  double? _introEndSec;
  bool _showSkipIntro = false;
  bool _skipIntroDismissed = false;
  bool _skipIntroAutoHidden = false;
  bool _nextPromptUserDismissed = false;
  bool _nextPromptAutoHidden = false;

  // ─── Video Fit ──────────────────────────────────────────────────────────
  _VideoFitMode _fitMode = _VideoFitMode.contain;

  BoxFit get _currentBoxFit {
    switch (_fitMode) {
      case _VideoFitMode.contain:
        return BoxFit.contain;
      case _VideoFitMode.cover:
        return BoxFit.cover;
      case _VideoFitMode.fill:
        return BoxFit.fill;
      case _VideoFitMode.fitWidth:
        return BoxFit.fitWidth;
      case _VideoFitMode.fitHeight:
        return BoxFit.fitHeight;
    }
  }

  String get _fitModeLabel {
    switch (_fitMode) {
      case _VideoFitMode.contain:
        return 'Original';
      case _VideoFitMode.cover:
        return 'Expandir';
      case _VideoFitMode.fill:
        return 'Estirar';
      case _VideoFitMode.fitWidth:
        return 'Ancho';
      case _VideoFitMode.fitHeight:
        return 'Alto';
    }
  }

  IconData get _fitModeIcon {
    switch (_fitMode) {
      case _VideoFitMode.contain:
        return Icons.fit_screen_rounded;
      case _VideoFitMode.cover:
        return Icons.aspect_ratio_rounded;
      case _VideoFitMode.fill:
        return Icons.open_in_full_rounded;
      case _VideoFitMode.fitWidth:
        return Icons.swap_horiz_rounded;
      case _VideoFitMode.fitHeight:
        return Icons.swap_vert_rounded;
    }
  }

  void _cycleFitMode() {
    setState(() {
      final values = _VideoFitMode.values;
      _fitMode = values[(_fitMode.index + 1) % values.length];
    });
    _scheduleHideControls();
  }

  int get _resolvedId {
    final id = widget.tmdbId ?? widget.idcontenido;
    return id > 0 ? id : 0;
  }

  String get _mediaType {
    final t = widget.tipo.toLowerCase();
    return t == 'tv' ? 'tv' : 'movie';
  }

  bool get _hasBottomContent =>
      (_mediaType == 'tv' && _temporadas.isNotEmpty) ||
      _recomendaciones.isNotEmpty;

  // ─── Optimizar URLs de TMDB ─────────────────────────────────────────────
  String _optimizeTmdbUrl(String? url, {String size = 'w500'}) {
    if (url == null || url.isEmpty) return '';
    if (url.contains('image.tmdb.org/t/p/')) {
      return url.replaceFirstMapped(
        RegExp(r'/t/p/(original|w\d+|h\d+)/'),
        (m) => '/t/p/$size/',
      );
    }
    if (url.startsWith('/')) {
      return 'https://image.tmdb.org/t/p/$size$url';
    }
    return url;
  }

  String _idiomaFlagUrl() {
    final c = _idioma.toLowerCase().trim();
    if (c == 'es_mx' ||
        c == 'es-mx' ||
        c == 'es_la' ||
        c == 'es-la' ||
        c == 'lat' ||
        c == 'es' ||
        c.contains('latino')) {
      return 'https://embed69.org/static/lang/LAT.png';
    }
    if (c == 'es_es' ||
        c == 'es-es' ||
        c == 'esp' ||
        c.contains('castellano')) {
      return 'https://embed69.org/static/lang/ESP.png';
    }
    return 'https://embed69.org/static/lang/SUB.png';
  }

  @override
  void initState() {
    super.initState();
    _activePlayers++;

    if (widget.idioma != null && widget.idioma!.isNotEmpty) {
      _idioma = widget.idioma!.toUpperCase();
    }
    _setupSystemUi();
    // Reaplica landscape tras el dispose del player anterior (pushReplacement)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposing) _setupSystemUi();
    });
    _keepScreenOn();
    if (widget.isLive) {
      _initializePlayer();
    } else {
      _loadApiData().then((_) {
        _initializePlayer();
        _loadSubtitles();
      });
      _loadRecommendationsFromGuardados();
      _loadSubtitlePrefs();
    }
  }

  void _setupSystemUi() {
    // Siempre horizontal al abrir el player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreSystemUi() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _keepScreenOn() => WakelockPlus.enable();

  // ─── CACHÉ ──────────────────────────────────────────────────────────────
  String _getCacheKey() {
    if (_mediaType == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'cachePlayer_${_resolvedId}_T${widget.temporada}_C${widget.capitulo}';
    }
    return 'cachePlayer_$_resolvedId';
  }

  String _getCacheKeyRapido() {
    if (_mediaType == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'cachePlayerRapido_${_resolvedId}_T${widget.temporada}_C${widget.capitulo}';
    }
    return 'cachePlayerRapido_$_resolvedId';
  }

  Future<void> _saveCache() async {
    if (!_controllerReady || !_controller.value.isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    final pos = _controller.value.position.inSeconds;

    String? backdrop = _backdropUrl;
    if (_apiData != null) {
      final b = _apiData!['backdrop'] ?? _apiData!['backdrop_path'];
      if (b is String && b.isNotEmpty) backdrop = b;
    }

    final full = {
      'idcontenido': _resolvedId,
      'temporada': widget.temporada,
      'capitulo': widget.capitulo,
      'segundo': pos,
      'titulo': _tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo,
      'tipo': _mediaType,
      'videoUrl': _activeUrl.isNotEmpty ? _activeUrl : widget.videoUrl,
      'backdrop': backdrop ?? '',
      'timestamp': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_getCacheKey(), jsonEncode(full));

    // Guardar en Sembast según el perfil activo
    AppDatabase.instance.saveHistory(
      contenidoId: _resolvedId,
      episodioId: widget.temporada != null && widget.capitulo != null
          ? 'T${widget.temporada}_C${widget.capitulo}'
          : 'movie',
      progresoSegundos: pos,
      duracionTotal: _controller.value.duration.inSeconds,
      temporada: widget.temporada,
      capitulo: widget.capitulo,
      titulo: _tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo,
      poster: backdrop,
      tipo: _mediaType,
      videoUrl: _activeUrl.isNotEmpty ? _activeUrl : widget.videoUrl,
      tmdbId: widget.tmdbId ?? _resolvedId,
    );

    final rapido = {
      'idcontenido': _resolvedId,
      'temporada': widget.temporada,
      'capitulo': widget.capitulo,
      'segundo': pos,
    };
    await prefs.setString(_getCacheKeyRapido(), jsonEncode(rapido));

    GuardadosBus.bump();
  }

  Future<int?> _getSavedPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_getCacheKeyRapido());
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      return data['segundo'] as int?;
    } catch (_) {
      return null;
    }
  }

  // ─── Cargar datos desde TMDB ────────────────────────────────────────────
  Future<void> _loadApiData() async {
    try {
      final data = await _tmdbPlayer.fetchPlayer(
        tmdbId: _resolvedId,
        mediaType: _mediaType,
        temporada: widget.temporada ?? 0,
        capitulo: widget.capitulo ?? 0,
      );

      if (data['error'] == true) {
        debugPrint('TmdbPlayerService error: ${data['mensaje']}');
        return;
      }

      if (!mounted || _isDisposing) return;

      setState(() {
        _apiData = data;
        _backdropUrl = _optimizeTmdbUrl(
          data['backdrop']?.toString(),
          size: 'w780',
        );
        _logoUrl = _optimizeTmdbUrl(data['logo']?.toString(), size: 'w500');
        _tituloContenido =
            data['titulo_contenido']?.toString() ?? widget.titulo;
        _tituloCapitulo = data['titulo_capitulo']?.toString();
        _capituloFmt = data['capitulo']?.toString();
        _temporadas = data['temporadas'] is List
            ? List<dynamic>.from(data['temporadas'] as List)
            : const [];
        _siguiente = data['siguiente'] is Map
            ? Map<String, dynamic>.from(data['siguiente'] as Map)
            : null;

        if (data['recomendaciones'] is List) {
          _recomendaciones = List<dynamic>.from(
            data['recomendaciones'] as List,
          );
        }

        if (widget.temporada != null && _temporadas.isNotEmpty) {
          final idx = _temporadas.indexWhere(
            (t) => (t is Map && t['numero'] == widget.temporada),
          );
          if (idx >= 0) _selectedSeasonIndex = idx;
        }
      });
      _loadIntroSkip();
    } catch (e) {
      debugPrint('Error API player TMDB: $e');
    }
  }

  Future<void> _loadIntroSkip() async {
    try {
      final imdb = (_apiData?['imdb_id'] ?? '').toString().trim();
      if (imdb.isEmpty) return;

      final season = widget.temporada ?? _apiData?['temporada'];
      final episode = widget.capitulo ?? _apiData?['numero_capitulo'];

      final params = <String, String>{'imdb_id': imdb, 'segment_type': 'intro'};
      if (season != null) params['season'] = season.toString();
      if (episode != null) params['episode'] = episode.toString();

      final uri = Uri.https('api.introdb.app', '/segments', params);
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || !mounted || _isDisposing) return;

      final data = jsonDecode(res.body);
      final intro = data['intro'];
      if (intro is Map) {
        final start = intro['start_sec'];
        final end = intro['end_sec'];
        if (start != null && end != null && mounted && !_isDisposing) {
          setState(() {
            _introStartSec = (start as num).toDouble();
            _introEndSec = (end as num).toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint('Error intro skip: $e');
    }
  }

  void _updateSkipIntroVisibility() {
    if (_introStartSec == null || _introEndSec == null) {
      if (_showSkipIntro) _showSkipIntro = false;
      return;
    }
    final pos = _currentPosition.inMilliseconds / 1000.0;
    final inInterval = pos >= _introStartSec! && pos <= _introEndSec!;
    final visible =
        inInterval &&
        !_skipIntroDismissed &&
        !(_skipIntroAutoHidden && !_showControls);
    if (visible != _showSkipIntro) {
      _showSkipIntro = visible;
      if (!inInterval) {
        _skipIntroDismissed = false;
        _skipIntroAutoHidden = false;
      }
    }
  }

  void _skipIntro() {
    if (_introEndSec == null || !_controllerReady) return;
    final target = Duration(milliseconds: (_introEndSec! * 1000).round());
    _controller.seekTo(target);
    setState(() {
      _showSkipIntro = false;
      _skipIntroDismissed = true;
      _skipIntroAutoHidden = false;
    });
    _scheduleHideControls();
  }

  void _maybeReshowPrompts() {
    // Skip intro: solo si auto-ocultó (no dismiss manual)
    if (_introStartSec != null &&
        _introEndSec != null &&
        !_skipIntroDismissed) {
      final pos = _currentPosition.inMilliseconds / 1000.0;
      if (pos >= _introStartSec! && pos <= _introEndSec!) {
        _skipIntroAutoHidden = false;
        _showSkipIntro = true;
      }
    }
    // Next: solo al abrir controles; limpia autoHidden
    if (!_nextPromptUserDismissed &&
        _showEndPrompt &&
        (_siguiente != null || _recomendaciones.isNotEmpty)) {
      _nextPromptAutoHidden = false;
      _showNextButton = true;
    }
  }

  void _seekBy(int seconds) {
    if (!_controllerReady) return;
    var newPos = _currentPosition + Duration(seconds: seconds);
    if (newPos < Duration.zero) newPos = Duration.zero;
    if (newPos > _totalDuration) newPos = _totalDuration;
    _controller.seekTo(newPos);
    _scheduleHideControls();
  }

  Future<void> _loadRecommendationsFromGuardados() async {
    if (_recomendaciones.isNotEmpty) return;
    try {
      final items = await GuardadosCache.getAll();
      final filtered = items
          .where((e) => e['idcontenido'] != _resolvedId)
          .take(8)
          .toList();

      final adapted = filtered.map((e) {
        return <String, dynamic>{
          'idcontenido': e['idcontenido'],
          'tmdb_id': e['idcontenido'],
          'titulo': e['title'] ?? '',
          'poster': _optimizeTmdbUrl(
            (e['poster_path'] ?? e['backdrop_path'] ?? '').toString(),
            size: 'w342',
          ),
          'backdrop': _optimizeTmdbUrl(
            (e['backdrop_path'] ?? e['poster_path'] ?? '').toString(),
            size: 'w500',
          ),
          'tipo': e['type'] ?? e['media_type'] ?? 'movie',
        };
      }).toList();

      if (mounted && !_isDisposing && _recomendaciones.isEmpty) {
        setState(() => _recomendaciones = adapted);
      }
    } catch (e) {
      debugPrint('Error cargando guardados: $e');
    }
  }

  Map<String, String> _playerHeaders([String? overrideUrl]) {
    final url = (overrideUrl ?? _activeUrl).toLowerCase();
    final isNet =
        url.contains('hakunaymatata.com') ||
        url.contains('net27.cc') ||
        url.contains('/bt/');

    if (isNet) {
      return {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': 'https://net27.cc/',
        'Origin': 'https://net27.cc',
        'Accept': '*/*',
        'Range': 'bytes=0-',
      };
    }

    final h = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': '*/*',
      if (widget.headers != null) ...widget.headers!,
      ..._activeHeaders,
    };
    return h;
  }

  /// True si la URL ya es stream directo (m3u8/mp4/etc) — no hace falta extraer.
  bool _isDirectStreamUrl(String url) {
    final u = url.toLowerCase().trim();
    if (u.isEmpty) return false;
    if (u.contains('.m3u8')) return true;
    if (u.contains('.mp4')) return true;
    if (u.contains('.mpd')) return true; // DASH
    if (u.contains('.mkv') || u.contains('.webm')) return true;
    // Algunos CDN sirven m3u8 sin extensión clara
    if (u.contains('/playlist') || u.contains('format=m3u8')) return true;
    return false;
  }

  Future<void> _initializePlayer() async {
    if (_isResolving) return;
    _isResolving = true;
    _allServersFailed = false;

    try {
      Map<String, String> headers = {
        if (widget.headers != null) ...widget.headers!,
      };

      // ─── 1) URL ya pasada (p.ej. m3u8 desde ServidoresModal o TV en Vivo) ───────────
      final liveList = (widget.isLive && widget.liveStreams != null && widget.liveStreams!.isNotEmpty)
          ? widget.liveStreams!
          : null;
      final passed = (liveList != null && _currentLiveIndex < liveList.length)
          ? liveList[_currentLiveIndex].trim()
          : widget.videoUrl.trim();
      if (passed.isNotEmpty && _isDirectStreamUrl(passed)) {
        // Directo al reproductor: NO resolvePlayable, NO getServers
        debugPrint('Player: m3u8/directo recibido → play inmediato ($passed)');
        _activeUrl = passed;
        _activeHeaders = headers;
        _fallbackServers = [];
        _fallbackIndex = 0;
        await _startControllerWithUrl(passed, headers);
        return;
      }

      // ─── 2) URL no-directa (embed) pasada: intentar usarla; fallback sí ─
      String? url = passed.isNotEmpty ? passed : null;

      // ─── 3) Sin URL → ServerLoader (caché / fuentes) ────────────────────
      if (url == null || url.isEmpty) {
        final playable = await _serverLoader.resolvePlayable(
          contentId: _resolvedId,
          isMovie: _mediaType != 'tv',
          season: widget.temporada ?? 0,
          episode: widget.capitulo ?? 0,
          context: mounted ? context : null,
        );
        if (playable != null && playable.url.isNotEmpty) {
          url = playable.url;
          headers = {...headers, ...playable.headers};
          if (playable.idioma.isNotEmpty) {
            _idioma = playable.idioma.toUpperCase();
          }
          // Si ya resolvió a m3u8, jugar directo manteniendo la lista de fallback
          final directUrl = url;
          if (directUrl != null && _isDirectStreamUrl(directUrl)) {
            _activeUrl = directUrl;
            _activeHeaders = headers;
            if (playable.rawServer.isNotEmpty) {
              _fallbackServers = [playable.rawServer];
            }
            unawaited(_prepareFallbackServers(directUrl));
            await _startControllerWithUrl(directUrl, headers);
            return;
          }
        }
      }

      // ─── 4) Cola de fallback solo si NO tenemos stream directo ─────────
      await _prepareFallbackServers(url);

      if (url == null || url.isEmpty) {
        if (!mounted || _isDisposing) return;
        setState(() {
          _isLoading = false;
          _allServersFailed = true;
          _errorMessage =
              'No se encontró ningún servidor disponible para este contenido.';
        });
        return;
      }

      _activeUrl = url;
      _activeHeaders = headers;
      await _startControllerWithUrl(url, headers);
    } catch (e) {
      debugPrint('Error resolve/init: $e');
      await _tryNextServer(reason: e.toString());
    } finally {
      _isResolving = false;
    }
  }

  Future<void> _prepareFallbackServers(String? currentUrl) async {
    try {
      final servers = await _serverLoader.getServers(
        contentId: _resolvedId,
        isMovie: _mediaType != 'tv',
        season: widget.temporada ?? 0,
        episode: widget.capitulo ?? 0,
        context: mounted ? context : null,
      );
      _fallbackServers = servers;
      _fallbackIndex = 0;
      if (currentUrl != null) {
        final idx = servers.indexWhere((s) {
          final u =
              s['resolved_m3u8']?.toString() ??
              s['servidor_url']?.toString() ??
              '';
          return u == currentUrl;
        });
        if (idx >= 0) _fallbackIndex = idx;
      }
    } catch (_) {}
  }

  Future<void> _startControllerWithUrl(
    String url,
    Map<String, String> headers,
  ) async {
    // Liberar controller anterior si existe
    if (_controllerReady) {
      try {
        _controller.removeListener(_videoListener);
        await _controller.dispose();
      } catch (_) {}
      _controllerReady = false;
    }

    if (!mounted || _isDisposing) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _allServersFailed = false;
    });

    try {
      _activeUrl = url;
      _activeHeaders = headers;
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: _playerHeaders(url),
      );

      if (widget.isLive) {
        await _controller.initialize().timeout(
          const Duration(seconds: 7),
          onTimeout: () {
            throw TimeoutException('Tiempo de espera agotado al conectar con el canal.');
          },
        );
      } else {
        await _controller.initialize().timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            throw TimeoutException('Tiempo de espera agotado al conectar con el servidor.');
          },
        );
      }

      if (!mounted || _isDisposing) {
        await _controller.dispose();
        return;
      }

      _controller.addListener(_videoListener);
      _controllerReady = true;
      _currentQualityLabel = 'Auto';
      _currentQualityUrl = null;
      if (_apiData == null && !widget.isLive) {
        unawaited(_loadApiData());
      }
      if (_subtitlesEnabled && _subtitleCues.isEmpty && !widget.isLive) {
        unawaited(_loadSubtitles());
      }
      try {
        await _controller.setVolume(1.0);
        final currentVol = await AudioBoostService.instance.getVolumePercent();
        if (currentVol <= 0.05 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sube el volumen de tu dispositivo para escuchar.'),
              backgroundColor: Color(0xFF1E1E24),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (_) {}

      // ── Detección de servidor sin audio (3 segundos) ────────────────────
      _audioCheckTimer?.cancel();
      if (!widget.isLive) {
        _audioCheckTimer = Timer(const Duration(seconds: 3), () async {
          if (!mounted || _isDisposing || !_controllerReady) return;
          final currentServer = (_fallbackIndex < _fallbackServers.length)
              ? _fallbackServers[_fallbackIndex]
              : null;
          final isMutedServer = currentServer?['sin_audio'] == true ||
              currentServer?['has_audio'] == false ||
              currentServer?['hasAudio'] == false;
          if (isMutedServer && mounted) {
            _showNoAudioFallbackPrompt();
          }
        });
      }

      // ── Watchdog de 8 segundos para VOD ─────────────────────────────────
      _vodWatchdogTimer?.cancel();
      if (!widget.isLive) {
        _vodWatchdogTimer = Timer(const Duration(seconds: 8), () {
          if (!mounted || _isDisposing || widget.isLive) return;
          final pos = _controllerReady ? _controller.value.position.inMilliseconds : 0;
          final playing = _controllerReady && _controller.value.isPlaying;
          final hasError = _controllerReady && _controller.value.hasError;
          if (!playing || pos < 300 || hasError || !_controllerReady) {
            debugPrint('[VOD Watchdog] Servidor tardó más de 8s sin reproducir. Cambiando servidor...');
            if (mounted) {
              setState(() {
                _isSwitchingServerNotice = true;
              });
            }
            if (_fallbackIndex < _fallbackServers.length) {
              _serverLoader.markServerAsInvalid(_fallbackServers[_fallbackIndex]);
            }
            _tryNextServer(reason: 'El servidor tardó más de 8s en iniciar reproducción');
          }
        });
      }

      final saved = await _getSavedPosition();
      if (saved != null && saved > 5) {
        await _controller.seekTo(Duration(seconds: saved));
      }

      if (!mounted || _isDisposing) return;
      _stopLoadingTimer();
      setState(() {
        _isLoading = false;
        _errorMessage = '';
        _totalDuration = _controller.value.duration;
        _isPlaying = true;
      });
      await _controller.play();
      _scheduleHideControls();
    } catch (e) {
      _stopLoadingTimer();
      debugPrint('Error al reproducir URL: $e');
      if (widget.isLive) {
        final streams = widget.liveStreams ?? [widget.videoUrl];
        if (_currentLiveIndex + 1 < streams.length) {
          _currentLiveIndex++;
          final nextStream = streams[_currentLiveIndex];
          debugPrint('[Live] Señal previa falló. Conectando a opción ${_currentLiveIndex + 1}/${streams.length}: $nextStream');
          if (mounted && !_isDisposing) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Señal no disponible. Probando señal alternativa (${_currentLiveIndex + 1}/${streams.length})...'),
                duration: const Duration(seconds: 2),
                backgroundColor: accentOrange,
              ),
            );
            await _startControllerWithUrl(nextStream, headers);
          }
          return;
        }

        if (!mounted || _isDisposing) return;
        setState(() {
          _isLoading = false;
          _errorMessage = streams.length > 1
              ? 'No se pudo conectar a ninguna de las ${streams.length} señales disponibles para este canal.\nEl canal podría estar fuera del aire.'
              : 'La señal en vivo no está disponible en este momento.\nEl canal podría estar fuera del aire o temporalmente inaccesible.';
          _allServersFailed = true;
        });
        return;
      }
      // Marcar inválido y probar siguiente
      if (mounted) {
        setState(() {
          _isSwitchingServerNotice = true;
        });
      }
      if (_fallbackIndex < _fallbackServers.length) {
        final cur = _fallbackServers[_fallbackIndex];
        _serverLoader.markServerAsInvalid(cur);
      }
      await _tryNextServer(reason: e.toString());
    }
  }

  /// Fallback automático al siguiente servidor válido
  Future<void> _tryNextServer({String? reason}) async {
    if (!mounted || _isDisposing) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    _startLoadingTimer();
    _consecutiveServerFailures++;

    // Si van 3 o más fallos seguidos, mostrar diálogo de fallback visible
    if (_consecutiveServerFailures >= 3) {
      if (!mounted || _isDisposing) return;
      _stopLoadingTimer();
      setState(() {
        _isLoading = false;
        _isSwitchingServerNotice = false;
        _allServersFailed = true;
        _errorMessage = reason != null && reason.isNotEmpty
            ? 'Ningún servidor funcionó.\n$reason'
            : 'Ningún servidor disponible para este contenido.';
      });
      _showAllServersFailedDialog();
      return;
    }

    // Si llegamos con m3u8 directo y no hay cola, prepararla ahora
    if (_fallbackServers.isEmpty) {
      await _prepareFallbackServers(_activeUrl);
      _fallbackIndex = -1; // se incrementa abajo
    }

    // Avanzar índice
    _fallbackIndex++;

    while (_fallbackIndex < _fallbackServers.length) {
      final srv = _fallbackServers[_fallbackIndex];
      try {
        final playable = await _serverLoader.tryResolveServer(
          srv,
          context: mounted ? context : null,
        );
        if (playable != null &&
            playable.url.isNotEmpty &&
            playable.url != _activeUrl) {
          await _startControllerWithUrl(playable.url, playable.headers);
          return;
        }
      } catch (_) {}
      _serverLoader.markServerAsInvalid(srv);
      _fallbackIndex++;
    }

    // Sin más servidores
    if (!mounted || _isDisposing) return;
    _stopLoadingTimer();
    setState(() {
      _isLoading = false;
      _isSwitchingServerNotice = false;
      _allServersFailed = true;
      _errorMessage = reason != null && reason.isNotEmpty
          ? 'Ningún servidor funcionó.\n$reason'
          : 'Ningún servidor disponible para este contenido.';
    });
    _showAllServersFailedDialog();
  }

  Future<void> _buscarEnTodasLasFuentesFallback() async {
    final query = _tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo;
    if (query.trim().isEmpty) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Buscando "$query" en todas las fuentes...'),
          backgroundColor: const Color(0xFF1E1E24),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    try {
      final res = await buscarEnFuentes(q: query);
      if (!mounted || _isDisposing) return;

      final allItems = res.resultados.values.expand((list) => list).toList();
      if (allItems.isNotEmpty) {
        final first = allItems.first;
        final id = first.tmdbId ?? query.hashCode.abs();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PageContenido(
              idcontenido: id,
              tmdbId: id,
              mediaType: first.tipo.isNotEmpty ? first.tipo : _mediaType,
              expectedTitle: first.titulo.isNotEmpty ? first.titulo : query,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontraron otras fuentes disponibles para este contenido.'),
            backgroundColor: Color(0xFF1E1E24),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al buscar en fuentes: $e'),
            backgroundColor: const Color(0xFF1E1E24),
          ),
        );
      }
    }
  }

  void _showAllServersFailedDialog() {
    if (!mounted || _isDisposing) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: accentOrange, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Fallo de reproducción',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Ningún servidor funcionó. ¿Quieres buscar este contenido en otras fuentes?',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop();
            },
            child: const Text('Volver', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showAudioLanguageSelector();
            },
            child: const Text('Elegir servidor', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _buscarEnTodasLasFuentesFallback();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Buscar en todas las fuentes'),
          ),
        ],
      ),
    );
  }

  String _langLabel(String raw) {
    final s = raw.toLowerCase().trim();
    if (s.contains('lat') || s == 'es_mx') return 'Español Latino';
    if (s.contains('cast') || s == 'es_es' || s.contains('esp')) return 'Español Castellano';
    if (s.contains('sub') || s.contains('jap') || s.contains('vose')) return 'Subtitulado';
    if (s.contains('ing') || s.contains('eng') || s == 'en') return 'Inglés';
    if (s.isEmpty) return 'Desconocido';
    return s[0].toUpperCase() + s.substring(1);
  }

  Future<void> _showAudioLanguageSelector({bool forCasting = false}) async {
    _hideControlsTimer?.cancel();

    if (_fallbackServers.isEmpty ||
        _fallbackServers.map((s) => _langLabel(s['idioma']?.toString() ?? '')).toSet().length <= 1) {
      try {
        final all = await _serverLoader.getAllServers(
          contentId: _resolvedId,
          isMovie: _mediaType != 'tv',
          season: widget.temporada ?? 0,
          episode: widget.capitulo ?? 0,
          context: mounted ? context : null,
        );
        if (all.isNotEmpty) {
          final existingUrls = _fallbackServers.map((s) => s['servidor_url']?.toString()).toSet();
          for (final s in all) {
            final u = s['servidor_url']?.toString();
            if (u != null && !existingUrls.contains(u)) {
              _fallbackServers.add(s);
            }
          }
        }
      } catch (_) {}
    }

    final Map<String, List<Map<String, dynamic>>> byLang = {};
    for (final srv in _fallbackServers) {
      final rawLang = srv['idioma']?.toString() ?? '';
      final label = _langLabel(rawLang);
      byLang.putIfAbsent(label, () => []).add(srv);
    }

    if (byLang.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este servidor no soporta pistas de audio múltiples. Cambia de servidor para otro idioma.'),
            backgroundColor: Color(0xFF1a1a1a),
          ),
        );
      }
      _scheduleHideControls();
      return;
    }

    final currentLangLabel = _langLabel(_idioma);

    // Cargar caché Sembast de servidores validados (TTL 15m / 1h)
    final verifiedKeys = <String>{};
    final unverifiedKeys = <String>{};
    final noAudioKeys = <String>{};
    for (final srv in _fallbackServers) {
      final key = _serverKey(srv);
      final cached = await AppDatabase.instance.getCachedServerStatus(key);
      if (cached != null) {
        if (cached['has_audio'] == false) noAudioKeys.add(key);
      }
      final srvUrl = (srv['resolved_m3u8'] ?? srv['servidor_url'] ?? '').toString();
      if (srvUrl.isNotEmpty) {
        final preVal = await ServerPreValidationService.instance.getCachedResult(srvUrl);
        if (preVal != null && preVal.isValid) {
          verifiedKeys.add(key);
        } else if (preVal != null && !preVal.isValid) {
          unverifiedKeys.add(key);
        }
      }
    }

    // Regla estricta WAVE 12.6: NUNCA ocultar idiomas ni servidores.
    if (byLang.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay servidores disponibles para este contenido en este momento. Intenta más tarde.'),
            backgroundColor: Color(0xFF1a1a1a),
          ),
        );
      }
      _scheduleHideControls();
      return;
    }

    if (!mounted) return;

    String selectedLang = byLang.containsKey(currentLangLabel)
        ? currentLangLabel
        : byLang.keys.first;

    StreamSubscription? valSub;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            valSub ??= ServerPreValidationService.instance.onValidationBatchCompleted.listen((_) async {
              for (final srv in _fallbackServers) {
                final key = _serverKey(srv);
                final srvUrl = (srv['resolved_m3u8'] ?? srv['servidor_url'] ?? '').toString();
                if (srvUrl.isNotEmpty) {
                  final preVal = await ServerPreValidationService.instance.getCachedResult(srvUrl);
                  if (preVal != null && preVal.isValid) {
                    verifiedKeys.add(key);
                    unverifiedKeys.remove(key);
                  } else if (preVal != null && !preVal.isValid) {
                    unverifiedKeys.add(key);
                    verifiedKeys.remove(key);
                  }
                }
              }
              if (modalCtx.mounted) {
                setModalState(() {});
              }
            });

            // Ordenar: si forCasting es true, priorizar servidores MP4/DLNA
            final allForLang = (byLang[selectedLang] ?? []).toList();
            allForLang.sort((a, b) {
              if (forCasting) {
                final aUrl = (a['resolved_m3u8'] ?? a['servidor_url'] ?? '').toString();
                final bUrl = (b['resolved_m3u8'] ?? b['servidor_url'] ?? '').toString();
                final aDlna = DlnaHelper.isLikelyMp4(aUrl, serverName: a['servidor_nombre']?.toString());
                final bDlna = DlnaHelper.isLikelyMp4(bUrl, serverName: b['servidor_nombre']?.toString());
                if (aDlna && !bDlna) return -1;
                if (!aDlna && bDlna) return 1;
              }
              final aVer = verifiedKeys.contains(_serverKey(a));
              final bVer = verifiedKeys.contains(_serverKey(b));
              if (aVer && !bVer) return -1;
              if (!aVer && bVer) return 1;
              return 0;
            });
            final activeLangServers = allForLang;
            final hasAnyVerified = activeLangServers.any((s) => verifiedKeys.contains(_serverKey(s)));

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const Row(
                        children: [
                          Icon(Icons.headphones_rounded, color: Color(0xFFFF6B35), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Seleccionar Idioma y Servidor',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: ServerPreValidationService.instance.isValidatingNotifier,
                        builder: (context, isValidating, _) {
                          if (!isValidating) return const SizedBox.shrink();
                          return const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Validando el resto de servidores...',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // 1. Selector de Idiomas Disponibles
                      const Text(
                        'IDIOMA DISPONIBLE',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: byLang.entries.map((entry) {
                            final isCur = entry.key == selectedLang;
                            final count = entry.value.length;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.language_rounded,
                                      size: 16,
                                      color: isCur ? Colors.white : Colors.white70,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        color: isCur ? Colors.white : Colors.white70,
                                        fontWeight: isCur ? FontWeight.bold : FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isCur ? Colors.black26 : Colors.white12,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: TextStyle(
                                          color: isCur ? Colors.white : Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                selected: isCur,
                                selectedColor: const Color(0xFFFF6B35),
                                backgroundColor: const Color(0xFF222222),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: isCur ? const Color(0xFFFF6B35) : Colors.white12,
                                  ),
                                ),
                                onSelected: (_) {
                                  setModalState(() {
                                    selectedLang = entry.key;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 16),
                      // 2. Servidores filtrados para el idioma seleccionado
                      Row(
                        children: [
                          Text(
                            'SERVIDORES EN $selectedLang'.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${activeLangServers.length} disponibles',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (!hasAnyVerified && activeLangServers.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: Colors.amberAccent),
                              SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  'No pudimos verificar los servidores automáticamente. Prueba uno por uno.',
                                  style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),

                      Flexible(
                        child: activeLangServers.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(24),
                                alignment: Alignment.center,
                                child: Text(
                                  'No hay servidores activos para $selectedLang',
                                  style: const TextStyle(color: Colors.white38),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: activeLangServers.length,
                                itemBuilder: (ctx, idx) {
                                  final srv = activeLangServers[idx];
                                  final srvName = srv['fuente_label']?.toString() ??
                                      srv['servidor_nombre']?.toString() ??
                                      srv['server']?.toString() ??
                                      'Servidor ${idx + 1}';
                                  final quality = srv['quality']?.toString() ??
                                      srv['calidad']?.toString() ??
                                      'HD';
                                  final isCurrentServer = _activeUrl == srv['servidor_url'] ||
                                      _activeUrl == srv['resolved_m3u8'];
                                  final isVerified = verifiedKeys.contains(_serverKey(srv));

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Material(
                                      color: isCurrentServer
                                          ? const Color(0xFFFF6B35).withValues(alpha: 0.15)
                                          : const Color(0xFF202020),
                                      borderRadius: BorderRadius.circular(10),
                                      child: ListTile(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          side: BorderSide(
                                            color: isCurrentServer
                                                ? const Color(0xFFFF6B35)
                                                : Colors.white.withValues(alpha: 0.06),
                                          ),
                                        ),
                                        leading: Icon(
                                          isCurrentServer
                                              ? Icons.play_circle_filled_rounded
                                              : Icons.play_circle_outline_rounded,
                                          color: isCurrentServer
                                              ? const Color(0xFFFF6B35)
                                              : Colors.white54,
                                        ),
                                        title: Text(
                                          srvName,
                                          style: TextStyle(
                                            color: isCurrentServer ? const Color(0xFFFF6B35) : Colors.white,
                                            fontWeight: isCurrentServer ? FontWeight.bold : FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                        ),
                                        subtitle: isCurrentServer
                                            ? const Text(
                                                'Reproduciendo actualmente',
                                                style: TextStyle(color: Color(0xFFFF6B35), fontSize: 11),
                                              )
                                            : null,
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (DlnaHelper.isLikelyMp4((srv['resolved_m3u8'] ?? srv['servidor_url'] ?? '').toString(), serverName: srvName)) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFF6B35).withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: const Color(0xFFFF6B35),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.cast_rounded, size: 10, color: Color(0xFFFF6B35)),
                                                    SizedBox(width: 3),
                                                    Text(
                                                      'Cast',
                                                      style: TextStyle(
                                                        color: Color(0xFFFF6B35),
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                              decoration: BoxDecoration(
                                                color: isVerified
                                                    ? Colors.green.withValues(alpha: 0.18)
                                                    : Colors.white.withValues(alpha: 0.06),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isVerified ? Colors.greenAccent : Colors.white24,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    isVerified ? Icons.check_circle_rounded : Icons.help_outline_rounded,
                                                    size: 11,
                                                    color: isVerified ? Colors.greenAccent : Colors.white60,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    isVerified ? 'Verificado' : 'Sin verificar',
                                                    style: TextStyle(
                                                      color: isVerified ? Colors.greenAccent : Colors.white60,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.white12,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                quality,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          if (!isCurrentServer) {
                                            _switchToServerLanguage([srv]);
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    await valSub?.cancel();
    _scheduleHideControls();
  }

  String _serverKey(Map<String, dynamic> srv) {
    final url = srv['servidor_url'] ?? srv['resolved_m3u8'] ?? srv['server'] ?? srv['nombre'] ?? '';
    return '${widget.tmdbId ?? widget.idcontenido}_${widget.temporada ?? 0}_${widget.capitulo ?? 0}_$url';
  }

  void _showNoAudioFallbackPrompt() {
    if (!mounted || _isDisposing) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          title: const Row(
            children: [
              Icon(Icons.volume_off_rounded, color: Colors.orangeAccent, size: 24),
              SizedBox(width: 10),
              Text(
                '¿Sin audio?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Este servidor no tiene audio. ¿Cambiar a otro?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('No, continuar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _tryNextServer(reason: 'Servidor sin audio reportado');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Sí, cambiar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _switchToServerLanguage(List<Map<String, dynamic>> targetServers) async {
    final targetPosition = _controllerReady ? _controller.value.position : _currentPosition;
    final previousUrl = _activeUrl;
    final previousHeaders = _activeHeaders;
    final wasPlaying = _isPlaying;
    final langName = targetServers.isNotEmpty
        ? _langLabel(targetServers.first['idioma']?.toString() ?? '')
        : 'otro servidor';

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _switchingLangOverlay = 'Cambiando a $langName...';
    });

    try {
      for (final targetServer in targetServers) {
        final srvKey = _serverKey(targetServer);
        try {
          final playable = await _serverLoader.tryResolveServer(
            targetServer,
            context: mounted ? context : null,
          ).timeout(const Duration(seconds: 8));

          if (playable != null && playable.url.isNotEmpty) {
            _activeUrl = playable.url;
            _activeHeaders = playable.headers;
            _idioma = playable.idioma;
            // Reorganizar fallbackServers para priorizar los de este idioma
            final remainingSameLang = targetServers.where((s) => s != targetServer).toList();
            final others = _fallbackServers.where((s) => !targetServers.contains(s)).toList();
            _fallbackServers = [targetServer, ...remainingSameLang, ...others];
            _fallbackIndex = 0;

            await AppDatabase.instance.setCachedServerStatus(
              srvKey,
              isValid: true,
              hasAudio: targetServer['sin_audio'] != true && targetServer['has_audio'] != false,
            );

            await _startControllerWithUrl(playable.url, playable.headers);
            if (_controllerReady) {
              await _controller.seekTo(targetPosition);
              if (wasPlaying) {
                await _controller.play();
              }
            }
            return;
          }
        } catch (_) {
          _serverLoader.markServerAsInvalid(targetServer);
          await AppDatabase.instance.setCachedServerStatus(
            srvKey,
            isValid: false,
            hasAudio: false,
          );
        }
      }

      // Si falló el cambio, restaurar el servidor anterior
      if (previousUrl.isNotEmpty) {
        try {
          await _startControllerWithUrl(previousUrl, previousHeaders);
          if (_controllerReady) {
            await _controller.seekTo(targetPosition);
            if (wasPlaying) {
              await _controller.play();
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cambiar el idioma. Intenta con otro servidor.'),
            backgroundColor: Color(0xFFD32F2F),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() => _isLoading = false);
      }
    } finally {
      if (mounted) {
        setState(() => _switchingLangOverlay = null);
      }
    }
  }

  // ─── Subtítulos originales (fallback) ───────────────────────────────────
  Future<void> _loadSubtitles() async {
    try {
      final fromApi = _apiData?['subtitulo']?.toString();
      final url = (fromApi != null && fromApi.isNotEmpty)
          ? fromApi
          : 'https://modlyo.com/subtitulo/contenido/$_resolvedId/es_MX.vtt';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final cues = _parseVtt(utf8.decode(response.bodyBytes));
        if (mounted && !_isDisposing) setState(() => _subtitleCues = cues);
      }
    } catch (_) {}
  }

  List<_SubtitleCue> _parseVtt(String content) {
    final cues = <_SubtitleCue>[];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final timeRegex = RegExp(
      r'(\d{2}:)?(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*(\d{2}:)?(\d{2}):(\d{2})[.,](\d{3})',
    );
    int i = 0;
    while (i < lines.length) {
      final match = timeRegex.firstMatch(lines[i].trim());
      if (match != null) {
        final start = _durationFromMatch(match, 1);
        final end = _durationFromMatch(match, 5);
        i++;
        final buffer = StringBuffer();
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(_stripVttTags(lines[i].trim()));
          i++;
        }
        cues.add(_SubtitleCue(start: start, end: end, text: buffer.toString()));
      }
      i++;
    }
    return cues;
  }

  Duration _durationFromMatch(RegExpMatch match, int startGroup) {
    final hoursStr = match.group(startGroup);
    final hours = hoursStr != null
        ? int.parse(hoursStr.replaceAll(':', ''))
        : 0;
    final minutes = int.parse(match.group(startGroup + 1)!);
    final seconds = int.parse(match.group(startGroup + 2)!);
    final millis = int.parse(match.group(startGroup + 3)!);
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  String _stripVttTags(String text) => text.replaceAll(RegExp(r'<[^>]*>'), '');

  // ─── Actualizar subtítulo con OFFSET ────────────────────────────────────
  void _updateCurrentSubtitle() {
    if (!_subtitlesEnabled || _subtitleCues.isEmpty) {
      if (_currentSubtitleText.isNotEmpty) _currentSubtitleText = '';
      return;
    }

    final adjustedPos =
        _currentPosition +
        Duration(milliseconds: (_subtitleOffsetSec * 1000).round());

    String newText = '';
    for (final cue in _subtitleCues) {
      if (adjustedPos >= cue.start && adjustedPos <= cue.end) {
        newText = cue.text;
        break;
      }
      if (adjustedPos < cue.start) break;
    }
    if (newText != _currentSubtitleText) {
      _currentSubtitleText = newText;
    }
  }

  // ─── Cargar subtítulo desde OpenSubtitles ───────────────────────────────
  Future<void> _loadSelectedSubtitle(Map<String, dynamic> sub) async {
    final url = sub['url']?.toString();
    final id = sub['id']?.toString() ?? '';
    final lang = (sub['lang'] ?? '').toString().toLowerCase();
    final fileName = sub['subtitleFileName']?.toString() ?? 'sub.srt';

    if (url == null || url.isEmpty) return;

    try {
      final finalId = id.isNotEmpty ? id : url.hashCode.toString();
      final cacheKey = 'os_sub_${_resolvedId}_$finalId';
      final content = await SubtitleUtils.downloadAndCache(
        url: url,
        cacheKey: cacheKey,
        fileName: fileName,
      );

      final cues = _parseVtt(content);

      if (mounted && !_isDisposing) {
        setState(() {
          _subtitleCues = cues;
          _subtitlesEnabled = true;
          _selectedSubtitleId = finalId;
          _selectedSubtitleLabel = lang.isNotEmpty
              ? lang.toUpperCase()
              : 'Subs';
          _currentSubtitleText = '';
        });
        await _saveActiveSubtitle(id: finalId, url: url, lang: lang);
      }
    } catch (e) {
      debugPrint('Error cargando subtítulo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No se pudo cargar el subtítulo'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  Future<void> _loadSubtitlePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final offset = prefs.getDouble(_prefSubOffsetKey) ?? 0.0;
      final font = prefs.getDouble(_prefSubFontKey) ?? 18.0;
      final bold = prefs.getBool(_prefSubBoldKey) ?? true;
      final vert = prefs.getDouble(_prefSubVertKey) ?? 0.0;
      final savedId = prefs.getString('$_prefSubIdKey$_resolvedId');
      final savedUrl = prefs.getString('$_prefSubUrlKey$_resolvedId');
      final savedLang = prefs.getString('$_prefSubLangKey$_resolvedId');
      if (!mounted || _isDisposing) return;
      setState(() {
        _subtitleOffsetSec = offset.clamp(-30.0, 30.0);
        _subtitleFontSize = font.clamp(12.0, 36.0);
        _subtitleBold = bold;
        _subtitleVerticalOffset = vert.clamp(-40.0, 160.0);
        _selectedSubtitleId = savedId;
        if (savedLang != null && savedLang.isNotEmpty) {
          _selectedSubtitleLabel = savedLang.toUpperCase();
        }
      });
      if (savedUrl != null && savedUrl.isNotEmpty) {
        await _loadSelectedSubtitle({
          'url': savedUrl,
          'id': savedId ?? '',
          'lang': savedLang ?? '',
          'subtitleFileName': 'cached.vtt',
        });
      }
    } catch (e) {
      debugPrint('Error cargando prefs subtítulos: $e');
    }
  }

  Future<void> _saveSubtitleStylePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefSubOffsetKey, _subtitleOffsetSec);
      await prefs.setDouble(_prefSubFontKey, _subtitleFontSize);
      await prefs.setBool(_prefSubBoldKey, _subtitleBold);
      await prefs.setDouble(_prefSubVertKey, _subtitleVerticalOffset);
    } catch (_) {}
  }

  Future<void> _saveActiveSubtitle({
    required String id,
    required String url,
    String? lang,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefSubIdKey$_resolvedId', id);
      await prefs.setString('$_prefSubUrlKey$_resolvedId', url);
      if (lang != null && lang.isNotEmpty) {
        await prefs.setString('$_prefSubLangKey$_resolvedId', lang);
      }
    } catch (_) {}
  }

  Future<void> _clearActiveSubtitleCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefSubIdKey$_resolvedId');
      await prefs.remove('$_prefSubUrlKey$_resolvedId');
    } catch (_) {}
  }

  Future<void> _openSubtitlesModal() async {
    _hideControlsTimer?.cancel();

    if (_subtitleCues.isEmpty) {
      await _loadSubtitles();
    }

    final imdb = (_apiData?['imdb_id'] ?? '').toString().trim();

    final cuesForModal = _subtitleCues.map((c) {
      return {'start': c.start, 'end': c.end, 'text': c.text};
    }).toList();

    await OpenSubtitlesModal.show(
      context: context,
      imdbId: imdb.isEmpty ? null : imdb,
      tmdbId: _resolvedId > 0 ? _resolvedId : null,
      mediaType: _mediaType,
      season: widget.temporada ?? _apiData?['temporada'],
      episode: widget.capitulo ?? _apiData?['numero_capitulo'],
      currentSubtitleId: _selectedSubtitleId,
      subtitleOffsetSec: _subtitleOffsetSec,
      subtitleFontSize: _subtitleFontSize,
      subtitleBold: _subtitleBold,
      subtitleVerticalOffset: _subtitleVerticalOffset,
      cues: cuesForModal,
      currentPosition: _currentPosition,
      positionListenable: _positionNotifier, // ← esto

      onOffsetChanged: (v) {
        setState(() => _subtitleOffsetSec = v);
        _saveSubtitleStylePrefs();
      },
      onFontSizeChanged: (v) {
        setState(() => _subtitleFontSize = v);
        _saveSubtitleStylePrefs();
      },
      onBoldChanged: (v) {
        setState(() => _subtitleBold = v);
        _saveSubtitleStylePrefs();
      },
      onVerticalOffsetChanged: (v) {
        setState(() => _subtitleVerticalOffset = v);
        _saveSubtitleStylePrefs();
      },
      onSubtitleSelected: _loadSelectedSubtitle,
      onDisable: () {
        setState(() {
          _subtitlesEnabled = false;
          _subtitleCues = const [];
          _currentSubtitleText = '';
          _selectedSubtitleId = null;
          _selectedSubtitleLabel = 'Subs';
        });
        _clearActiveSubtitleCache();
      },
    );

    if (mounted) _scheduleHideControls();
  }

  void _videoListener() {
    if (!mounted || _isDisposing) return;

    final value = _controller.value;

    // ── Detección inmediata de fallo en el player ───────────────────────
    if (value.hasError && !_isSwitchingServerNotice && !_allServersFailed) {
      debugPrint('[Player] Error detectado en VideoPlayer: ${value.errorDescription}');
      _vodWatchdogTimer?.cancel();
      _vodWatchdogTimer = null;
      if (_fallbackIndex < _fallbackServers.length) {
        _serverLoader.markServerAsInvalid(_fallbackServers[_fallbackIndex]);
      }
      if (mounted) {
        setState(() {
          _isSwitchingServerNotice = true;
        });
      }
      _tryNextServer(reason: value.errorDescription ?? 'Error al procesar flujo de video');
      return;
    }

    final nowMs = value.position.inMilliseconds;
    final shouldUpdatePosition =
        _isDragging ||
        (nowMs - _lastPositionUpdateMs).abs() >= _positionThrottleMs;

    final newPlaying = value.isPlaying;
    final newBuffering = value.isBuffering;
    final newDuration = value.duration;

    bool needsSetState = false;

    // Si ya comenzó a reproducir (>300ms de posición), cancelar watchdog y ocultar aviso
    if (!widget.isLive && (_isSwitchingServerNotice || _vodWatchdogTimer != null) && newPlaying && nowMs > 300) {
      _consecutiveServerFailures = 0;
      _stopLoadingTimer();
      _vodWatchdogTimer?.cancel();
      _vodWatchdogTimer = null;
      if (_isSwitchingServerNotice) {
        _isSwitchingServerNotice = false;
        needsSetState = true;
      }
    }

    if (shouldUpdatePosition) {
      _currentPosition = value.position;
      _positionNotifier.value = value.position;
      _currentPosition = value.position;
      _lastPositionUpdateMs = nowMs;
      _updateCurrentSubtitle();
      final prevSkip = _showSkipIntro;
      _updateSkipIntroVisibility();
      if (prevSkip != _showSkipIntro) needsSetState = true;
      needsSetState = true;

      if (_totalDuration.inSeconds > 30) {
        final remaining = _totalDuration - _currentPosition;
        final progress =
            _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;

        final nearEnd =
            progress >= 0.90 ||
            (remaining <= const Duration(minutes: 3) &&
                remaining > const Duration(seconds: 2));

        final shouldShowNext =
            nearEnd &&
            remaining > const Duration(seconds: 2) &&
            (_siguiente != null || _recomendaciones.isNotEmpty) &&
            !_nextPromptUserDismissed &&
            !(_nextPromptAutoHidden && !_showControls);

        if (shouldShowNext != _showNextButton) {
          _showNextButton = shouldShowNext;
          needsSetState = true;
        }

        if (nearEnd != _showEndPrompt) {
          _showEndPrompt = nearEnd;
          needsSetState = true;
        }

        // Precarga silenciosa del siguiente capítulo al 90 %
        if (progress >= 0.90 &&
            !_preloadTriggered &&
            _mediaType == 'tv' &&
            widget.temporada != null &&
            widget.capitulo != null) {
          _preloadTriggered = true;
          final nextEp = (widget.capitulo ?? 0) + 1;
          _serverLoader.preloadNext(
            contentId: _resolvedId,
            season: widget.temporada ?? 1,
            nextEpisode: nextEp,
            context: mounted ? context : null,
          );
        }

        if (progress >= 0.98) {
          _saveCache();
        }

        if (!_hasHandledEnd &&
            _currentPosition >= _totalDuration - const Duration(seconds: 1)) {
          _hasHandledEnd = true;
          _saveCache();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isDisposing) _handleVideoEnded();
          });
        }
      }
    }

    if (newPlaying != _isPlaying) {
      _isPlaying = newPlaying;
      if (newPlaying) _hasStartedPlaying = true;
      needsSetState = true;
    }
    if (newBuffering != _isBuffering) {
      _isBuffering = newBuffering;
      needsSetState = true;

      // ── Bloque D.6: Manejo de corte temporal vs error fatal ──
      if (newBuffering && !value.hasError && _hasStartedPlaying && !widget.isLive) {
        _bufferingStartTime ??= DateTime.now();
        // Si el buffer persiste más de 2 segundos, iniciar la tolerancia de reconexión de 60s
        _reconnectTimer ??= Timer(const Duration(seconds: 2), () {
          if (mounted && !_isDisposing && _isBuffering && !_controller.value.hasError) {
            _startReconnectTolerance();
          }
        });
      } else if (!newBuffering && _isReconnecting) {
        // Stream recuperado antes del minuto sin cambiar de servidor
        _cancelReconnectTolerance(recovered: true);
      } else if (!newBuffering) {
        _bufferingStartTime = null;
      }
    }
    if (newPlaying && _isReconnecting) {
      // Si volvió a reproducir, cancelar overlay de reconexión
      _cancelReconnectTolerance(recovered: true);
    }
    if (newDuration != _totalDuration) {
      _totalDuration = newDuration;
      needsSetState = true;
    }

    if (needsSetState) setState(() {});
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_showControls || _isDragging || _showBottomPanel) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isDisposing) {
        setState(() {
          _showControls = false;
          _showBottomPanel = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showBottomPanel = false;
      } else {
        // Al mostrar controles, reaparecen skip intro / siguiente si toca
        _maybeReshowPrompts();
      }
    });
    if (_showControls) _scheduleHideControls();
  }

  void _togglePlay() {
    if (!_controllerReady) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    _scheduleHideControls();
  }

  void _restart() {
    if (!_controllerReady) return;
    _controller.seekTo(Duration.zero);
    _controller.play();
    _scheduleHideControls();
  }

  void _openInfoModal() {
    _hideControlsTimer?.cancel();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _logoUrl != null && _logoUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _logoUrl!,
                              height: 42,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              memCacheHeight: 84,
                              errorWidget: (_, __, ___) => Text(
                                _tituloContenido,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Text(
                              _tituloContenido,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_capituloFmt != null || _tituloCapitulo != null) ...[
                        Text(
                          [
                            if (_capituloFmt != null) _capituloFmt,
                            if (_tituloCapitulo != null) _tituloCapitulo,
                          ].whereType<String>().join(' · '),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_apiData?['calificacion'] != null) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_apiData!['calificacion']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_apiData?['fecha_salida'] != null) ...[
                              const SizedBox(width: 12),
                              Text(
                                _apiData!['fecha_salida'].toString().length >= 4
                                    ? _apiData!['fecha_salida']
                                          .toString()
                                          .substring(0, 4)
                                    : '',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        _apiData?['overview']?.toString() ?? 'Sin descripción',
                        style: TextStyle(
                          color: Colors.grey[300],
                          height: 1.45,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _scheduleHideControls());
  }

  Future<void> _openQualitySelector() async {
    _hideControlsTimer?.cancel();

    // URL maestra real: la activa (ServerLoader) o la del widget
    final master = _activeUrl.isNotEmpty
        ? _activeUrl
        : (_currentQualityUrl ?? widget.videoUrl);
    if (master.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay stream HLS activo para cambiar calidad'),
            backgroundColor: Color(0xFF1a1a1a),
          ),
        );
      }
      _scheduleHideControls();
      return;
    }

    final selected = await HlsQualitySelectorModal.show(
      context,
      masterUrl: master,
      currentQualityUrl: _currentQualityUrl,
      currentQualityLabel: _currentQualityLabel,
      accentColor: accentOrange,
    );

    if (selected == null || !mounted || _isDisposing) {
      if (mounted && !_isDisposing) _scheduleHideControls();
      return;
    }

    final currentUrl = _currentQualityUrl ?? master;
    if (selected.url == currentUrl) {
      _scheduleHideControls();
      return;
    }

    await _selectQuality(selected);
  }

  Future<void> _selectQuality(HlsQuality selected) async {
    final master = _activeUrl;
    final savedPos = _controllerReady
        ? _controller.value.position
        : Duration.zero;
    await _saveCache();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _currentQualityLabel = selected.label;
      _currentQualityUrl = selected.isAuto ? null : selected.url;
      _hasHandledEnd = false;
      _showEndPrompt = false;
      _showNextButton = false;
    });

    try {
      if (_controllerReady) {
        _controller.removeListener(_videoListener);
        try {
          await _controller.pause();
        } catch (_) {}
        try {
          await _controller.dispose();
        } catch (_) {}
      }
    } catch (_) {}
    _controllerReady = false;

    try {
      final playUrl = selected.url;
      // Mantener _activeUrl como master para futuros cambios; la calidad va en controller
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: _playerHeaders(master),
      );
      await _controller.initialize();

      if (!mounted || _isDisposing) {
        await _controller.dispose();
        return;
      }

      _controller.addListener(_videoListener);
      _controllerReady = true;
      try {
        await _controller.setVolume(1.0);
      } catch (_) {}

      if (savedPos > const Duration(seconds: 2)) {
        await _controller.seekTo(savedPos);
      }

      if (!mounted || _isDisposing) return;

      setState(() {
        _isLoading = false;
        _errorMessage = '';
        _totalDuration = _controller.value.duration;
        _currentPosition = savedPos;
        _showControls = true;
        _isPlaying = true;
      });

      await _controller.play();
      _scheduleHideControls();
    } catch (e) {
      debugPrint('Error al cambiar calidad: $e');
      if (!mounted || _isDisposing) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cambiar calidad: $e';
      });
    }
  }

  void _goNextEpisode() {
    _saveCache();
    if (_mediaType == 'tv') {
      if (_siguiente == null) return;
      final temp = _siguiente!['temporada'] as int?;
      final cap = _siguiente!['capitulo'] as int?;
      final tituloNext = _siguiente!['titulo']?.toString() ?? _tituloContenido;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            // Sin URL → el nuevo player resuelve con ServerLoader (caché del preload)
            videoUrl: '',
            idcontenido: _resolvedId,
            tmdbId: _resolvedId,
            temporada: temp,
            capitulo: cap,
            tipo: 'tv',
            titulo: tituloNext.isNotEmpty ? tituloNext : widget.titulo,
          ),
        ),
      );
    } else {
      if (_recomendaciones.isEmpty) return;
      final next = _recomendaciones.first;
      final id = next['tmdb_id'] ?? next['idcontenido'];
      final tipo = next['tipo']?.toString() ?? 'movie';
      final titulo = next['titulo']?.toString() ?? '';
      final idInt = id is int ? id : int.tryParse('$id') ?? 0;
      if (idInt <= 0) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            videoUrl: '',
            idcontenido: idInt,
            tmdbId: idInt,
            tipo: tipo,
            titulo: titulo.isNotEmpty ? titulo : widget.titulo,
          ),
        ),
      );
    }
  }

  void _handleVideoEnded() {
    if (!mounted || _isDisposing) return;
    setState(() {
      _showNextButton = true;
      _showControls = true;
    });
  }

  Future<void> _showExitConfirmation() async {
    final castService = CastService.instance;
    if (castService.state == CastState.casting ||
        castService.state == CastState.connected) {
      final shouldStop = await _handleBackPress();
      if (shouldStop && mounted) {
        _restoreSystemUi();
        WakelockPlus.disable();
        Navigator.pop(context);
      }
      return;
    }

    final wasPlaying = _isPlaying;
    if (_isPlaying) _controller.pause();
    await _saveCache();

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Salir del reproductor?',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'Se guardará el progreso actual.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir', style: TextStyle(color: netflixRed)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // Restaurar UI aquí; dispose también lo hará si es el último player
      _restoreSystemUi();
      WakelockPlus.disable();
      Navigator.pop(context);
    } else if (mounted && wasPlaying) {
      _controller.play();
      _scheduleHideControls();
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _isDisposing = true;
    _loadingLongTimer?.cancel();
    _vodWatchdogTimer?.cancel();
    _audioCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectCountdownTimer?.cancel();
    _hideControlsTimer?.cancel();
    _positionNotifier.dispose();

    _saveCache();
    if (_controllerReady) {
      _controller.removeListener(_videoListener);
      _controller.dispose();
    }

    // Solo restaurar orientación / wakelock si no queda otro player activo
    // (evita que al pushReplacement el dispose del viejo ponga vertical)
    _activePlayers--;
    if (_activePlayers <= 0) {
      _activePlayers = 0;
      _restoreSystemUi();
      WakelockPlus.disable();
    }

    if (CastService.instance.state == CastState.casting ||
        CastService.instance.state == CastState.connected) {
      CastService.instance.disconnect();
    }

    super.dispose();
  }

  Future<bool> _handleBackPress() async {
    final castService = CastService.instance;
    if (castService.state == CastState.casting ||
        castService.state == CastState.connected) {
      final shouldStop = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.cast_connected_rounded, color: Color(0xFFFF6B35)),
              SizedBox(width: 10),
              Text(
                'Reproducción remota',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            '¿Detener la reproducción remota?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sí, detener', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (shouldStop == true) {
        await castService.disconnect();
        return true;
      }
      return false;
    }
    return true;
  }

  Future<void> _handleDlnaCastPressed() async {
    if (widget.isLive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El envío a TV estará disponible próximamente para TV en vivo.'),
          backgroundColor: Color(0xFF1E1E1E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final castService = CastService.instance;

    // Si ya está conectado o casteando, ofrecer desconectar o cambiar
    if (castService.state == CastState.connected ||
        castService.state == CastState.casting) {
      final devName = castService.connectedDevice?.friendlyName ?? 'TV';
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.cast_connected_rounded, color: Color(0xFFFF6B35)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Transmitiendo a $devName',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            '¿Deseas desconectar la sesión de Cast o cambiar de dispositivo?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('disconnect'),
              child: const Text('Desconectar', style: TextStyle(color: Colors.redAccent)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('change'),
              child: const Text('Cambiar dispositivo', style: TextStyle(color: Color(0xFFFF6B35))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar', style: TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      );

      if (action == 'disconnect') {
        await castService.disconnect();
        if (_controllerReady && !_isPlaying) {
          _controller.play();
        }
        if (mounted) setState(() {});
        return;
      } else if (action != 'change') {
        return;
      }
    }

    if (!mounted) return;

    // Esperar a que la URL del stream esté resuelta si el loader aún está cargando
    String streamUrl = _activeUrl.isNotEmpty ? _activeUrl : widget.videoUrl;
    if (streamUrl.trim().isEmpty || _isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cargando el enlace del video, espera un momento...'),
          backgroundColor: Color(0xFF1E1E1E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final title = _tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo;
    final poster = _backdropUrl;

    if (!mounted) return;

    await DlnaCastSheet.show(
      context: context,
      videoUrl: streamUrl,
      title: title,
      posterUrl: poster,
      onCastStarted: () {
        // Pausar reproducción local para evitar duplicidad de audio
        if (_controllerReady && _isPlaying) {
          _controller.pause();
        }
        if (mounted) setState(() {});
      },
      onSelectServerForDlna: () => _showAudioLanguageSelector(forCasting: true),
      onResumeLocal: () {
        if (_controllerReady && !_isPlaying) {
          _controller.play();
        }
      },
    );
  }

  void _showLiveStreamSelector() {
    final streams = widget.liveStreams ?? [widget.videoUrl];
    if (streams.length <= 1) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_input_antenna_rounded, color: accentOrange, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Señales de ${widget.titulo} (${streams.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: streams.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, idx) {
                    final isSelected = idx == _currentLiveIndex;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accentOrange.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isSelected ? Icons.play_circle_fill_rounded : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? accentOrange : Colors.white54,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        'Señal ${idx + 1} ${idx == 0 ? "(Principal / CDN)" : "(Alternativa)"}',
                        style: TextStyle(
                          color: isSelected ? accentOrange : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        streams[idx],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: accentOrange, size: 20)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (idx != _currentLiveIndex) {
                          setState(() {
                            _currentLiveIndex = idx;
                            _isLoading = true;
                            _errorMessage = '';
                            _allServersFailed = false;
                          });
                          _startControllerWithUrl(streams[idx], _activeHeaders);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canLeave = await _handleBackPress();
        if (canLeave && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<CastState>(
          valueListenable: CastService.instance.stateNotifier,
          builder: (context, castState, _) {
            final isCasting = castState == CastState.connected || castState == CastState.casting;

            if (isCasting) {
              if (_controllerReady && _isPlaying) {
                _controller.pause();
              }
              return DlnaCastingOverlay(
                title: _tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo,
                posterUrl: _backdropUrl,
                currentPosition: _controllerReady ? _controller.value.position : Duration.zero,
                totalDuration: _controllerReady ? _controller.value.duration : Duration.zero,
                onSeek: (pos) {
                  if (_controllerReady) _controller.seekTo(pos);
                },
                onDisconnect: () async {
                  await CastService.instance.disconnect();
                  if (_controllerReady && !_isPlaying) {
                    _controller.play();
                  }
                  if (mounted) setState(() {});
                },
                onBackPressed: () async {
                  final canLeave = await _handleBackPress();
                  if (canLeave && mounted) {
                    Navigator.of(context).pop();
                  }
                },
                onReconnectTimeout: () {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No se pudo reconectar. Reproduciendo localmente.'),
                        backgroundColor: Color(0xFF1E1E1E),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  if (_controllerReady && !_isPlaying) {
                    _controller.play();
                  }
                  if (mounted) setState(() {});
                },
                isTv: false,
              );
            }

            return GestureDetector(
              onTap: _toggleControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
            if (_isLoading)
              _buildLoadingScreen()
            else if (_errorMessage.isNotEmpty)
              _buildErrorScreen()
            else
              SizedBox.expand(
                child: FittedBox(
                  fit: _currentBoxFit,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),

            // ── Bloque D.6: Overlay discreto de Reconectando con spinner ──
            if (_isReconnecting)
              Positioned(
                top: 48,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.90),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFFF6B35).withOpacity(0.9),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.7),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Reconectando... ($_reconnectRemainingSec s)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Overlay discreto al cambiar de idioma
            if (_switchingLangOverlay != null)
              Positioned(
                top: 48,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFFF6B35).withOpacity(0.85),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _switchingLangOverlay!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Aviso de cambio de servidor si tarda más de 5s
            if (_isSwitchingServerNotice)
              Positioned(
                top: 48,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFFF6B35).withOpacity(0.85),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                          ),
                        ),
                        SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Está tomando más tiempo de lo normal, cambiando servidor...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_isBuffering && !_isLoading && _errorMessage.isEmpty)
              const Center(
                child: CircularProgressIndicator(
                  color: accentOrange,
                  strokeWidth: 3,
                ),
              ),
            if (!_isLoading && _errorMessage.isEmpty && _subtitlesEnabled)
              SubtitleWidget(
                text: _currentSubtitleText,
                isActive: _currentSubtitleText.isNotEmpty,
                bottomPadding: _showControls
                    ? (_showBottomPanel ? 220.0 : 120.0)
                    : 36.0,
                fontSize: _subtitleFontSize,
                textColor: Colors.white,
                strokeColor: Colors.black,
                strokeWidth: 2.0,
                fontWeight: _subtitleBold ? FontWeight.w700 : FontWeight.w500,
                maxWidth: 640,
                verticalOffset: _subtitleVerticalOffset,
              ),
            // Controles debajo; skip intro / next ENCIMA para recibir toques
            if (!_isLoading && _errorMessage.isEmpty && _showControls)
              _buildControlsOverlay(),

            // ── Anuncio en pausa (WAVE 9 & 10) ─────────────────────────
            if (!_isLoading && _errorMessage.isEmpty)
              AdPauseOverlay(
                isPaused: !_isPlaying,
                hasStartedPlaying: _hasStartedPlaying,
                isControlsOrModalOpen: _showBottomPanel,
                isTv: false,
                onResume: () {
                  if (_controllerReady) {
                    _controller.play();
                  }
                },
              ),

            // ── Omitir intro (estilo Nuvio) — encima del overlay ─────
            if (!_isLoading && _errorMessage.isEmpty)
              Positioned(
                right: 16,
                bottom: _showControls
                    ? (_showBottomPanel ? 200.0 : 110.0)
                    : 40.0,
                child: MobileSkipNextButton(
                  visible: _showSkipIntro,
                  controlsVisible: _showControls,
                  label: 'Omitir intro',
                  icon: Icons.fast_forward_rounded,
                  accentColor: accentOrange,
                  primary: false,
                  autoHideMs: 15000,
                  onTap: _skipIntro,
                  onAutoHide: () {
                    if (!mounted || _isDisposing) return;
                    setState(() {
                      _skipIntroAutoHidden = true;
                      _showSkipIntro = false;
                    });
                  },
                ),
              ),

            // ── Siguiente episodio — encima del overlay ──────────────
            if (!_isLoading &&
                _errorMessage.isEmpty &&
                (_siguiente != null || _recomendaciones.isNotEmpty))
              Positioned(
                right: 16,
                bottom: _showControls
                    ? (_showBottomPanel ? 200.0 : 110.0)
                    : 40.0,
                child: MobileSkipNextButton(
                  visible: _showNextButton,
                  controlsVisible: _showControls,
                  label: _mediaType == 'tv'
                      ? 'Siguiente episodio'
                      : 'Siguiente',
                  icon: Icons.skip_next_rounded,
                  accentColor: accentOrange,
                  primary: true,
                  autoHideMs: 15000,
                  onTap: () {
                    setState(() {
                      _nextPromptUserDismissed = true;
                      _nextPromptAutoHidden = false;
                    });
                    _goNextEpisode();
                  },
                  onAutoHide: () {
                    if (!mounted || _isDisposing) return;
                    setState(() {
                      _showNextButton = false;
                      _nextPromptAutoHidden = true;
                    });
                  },
                ),
              ),

            // ── Barra de control remoto DLNA (Xbox / Smart TV) ────────
            ValueListenableBuilder<CastState>(
              valueListenable: CastService.instance.stateNotifier,
              builder: (context, castState, _) {
                if (castState != CastState.connected &&
                    castState != CastState.casting) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left: 12,
                  right: 12,
                  bottom: _showControls
                      ? (_showBottomPanel ? 230.0 : 120.0)
                      : 20.0,
                  child: DlnaRemoteControlBar(
                    onDisconnect: () {
                      if (mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
            ],
          ),
        );
      },
    ),
  ),
);
}

  Widget _buildLoadingScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_backdropUrl != null)
          CachedNetworkImage(
            imageUrl: _backdropUrl!,
            fit: BoxFit.cover,
            memCacheWidth: 800,
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: accentOrange,
                  strokeWidth: 3.5,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _isSwitchingServerNotice
                    ? 'Cambiando de servidor...'
                    : 'Conectando al servidor...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              if (_showTryAnotherServer) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () {
                    _tryNextServer(reason: 'Solicitado por el usuario');
                  },
                  icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                  label: const Text(
                    'Probar otro servidor',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: accentOrange, width: 1.5),
                    backgroundColor: Colors.black45,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: netflixRed,
              size: 56,
            ),
            const SizedBox(height: 14),
            const Text(
              'No se pudo cargar el video',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (widget.isLive) ...[
              if ((widget.liveStreams?.length ?? 0) > 1) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: List.generate(widget.liveStreams!.length, (idx) {
                    final isCurrent = idx == _currentLiveIndex;
                    return ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _currentLiveIndex = idx;
                          _isLoading = true;
                          _errorMessage = '';
                          _allServersFailed = false;
                        });
                        _startControllerWithUrl(widget.liveStreams![idx], _activeHeaders);
                      },
                      icon: Icon(
                        Icons.settings_input_antenna_rounded,
                        size: 16,
                        color: isCurrent ? Colors.white : accentOrange,
                      ),
                      label: Text('Probar Señal ${idx + 1}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrent ? accentOrange : Colors.white12,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = '';
                      _allServersFailed = false;
                    });
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar canal'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Volver a la lista de canales', style: TextStyle(color: Colors.white70)),
              ),
            ] else if (_allServersFailed) ...[
              ElevatedButton.icon(
                onPressed: () => _showAudioLanguageSelector(),
                icon: const Icon(Icons.translate_rounded),
                label: const Text('Abrir lista de servidores'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = '';
                    _allServersFailed = false;
                    _fallbackIndex = -1;
                  });
                  _serverLoader.clearCache(CacheType.all);
                  _initializePlayer();
                },
                child: const Text(
                  'Reintentar búsqueda',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = '';
                  });
                  _tryNextServer();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: netflixRed,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Probar otro servidor'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.75),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.92),
          ],
          stops: const [0.0, 0.18, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
              child: Row(
                children: [
                  if (widget.isLive) ...[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    if (widget.liveLogo != null && widget.liveLogo!.isNotEmpty) ...[
                      CachedNetworkImage(
                        imageUrl: widget.liveLogo!,
                        height: 28,
                        fit: BoxFit.contain,
                        memCacheHeight: 56,
                        errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white70, size: 20),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        widget.titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                          SizedBox(width: 4),
                          Text(
                            'EN VIVO',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    if ((widget.liveStreams?.length ?? 0) > 1) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _showLiveStreamSelector,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: accentOrange.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.settings_input_antenna_rounded, color: accentOrange, size: 14),
                              const SizedBox(width: 5),
                              Text(
                                'Señal ${_currentLiveIndex + 1}/${widget.liveStreams!.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    IconButton(
                      onPressed: _showExitConfirmation,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (_logoUrl != null && _logoUrl!.isNotEmpty) ...[
                            CachedNetworkImage(
                            imageUrl: _logoUrl!,
                            height: 28,
                            fit: BoxFit.contain,
                            memCacheHeight: 56,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: _mediaType == 'tv'
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_capituloFmt != null &&
                                        _capituloFmt!.isNotEmpty)
                                      Text(
                                        _capituloFmt!,
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      (_tituloCapitulo != null &&
                                              _tituloCapitulo!.isNotEmpty)
                                          ? _tituloCapitulo!
                                          : _tituloContenido,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                )
                              // Película: solo logo; si no hay logo → título
                              : (_logoUrl == null || _logoUrl!.isEmpty)
                              ? Text(
                                  _tituloContenido,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  // ── Distribuido por Filmotic ──
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.movie_rounded, color: Color(0xFFFF6B35), size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Distribuido por Filmotic',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: _idiomaFlagUrl(),
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      memCacheWidth: 48,
                      errorWidget: (_, __, ___) => Text(
                        _idioma,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // ── BOTÓN AUDÍFONOS (Selector de idioma de audio del servidor) ──
                  ValueListenableBuilder<bool>(
                    valueListenable: ServerPreValidationService.instance.isValidatingNotifier,
                    builder: (context, isValidating, _) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.headphones_rounded, color: Colors.white, size: 22),
                            tooltip: 'Idioma de audio del servidor',
                            onPressed: _showAudioLanguageSelector,
                          ),
                          if (isValidating)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                width: 10,
                                height: 10,
                                padding: const EdgeInsets.all(1),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF161616),
                                  shape: BoxShape.circle,
                                ),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  // ── BOTÓN CAST DLNA (Enviar a TV) ────────────────
                  ValueListenableBuilder<CastState>(
                    valueListenable: CastService.instance.stateNotifier,
                    builder: (context, castState, _) {
                      final isConnected = castState == CastState.connected ||
                          castState == CastState.casting;
                      return IconButton(
                        icon: Icon(
                          isConnected
                              ? Icons.cast_connected_rounded
                              : Icons.cast_rounded,
                          color: isConnected ? accentOrange : Colors.white,
                          size: 22,
                        ),
                        tooltip: isConnected
                            ? 'Conectado a TV (Administrar)'
                            : 'Enviar a TV',
                        onPressed: _handleDlnaCastPressed,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
            const Spacer(),
            if (widget.isLive)
              Center(
                child: _centerBtn(
                  icon: _isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 64,
                  onTap: _togglePlay,
                  filled: true,
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _centerBtn(
                    icon: Icons.replay_10_rounded,
                    size: 40,
                    onTap: () => _seekBy(-10),
                  ),
                  const SizedBox(width: 28),
                  _centerBtn(
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 56,
                    onTap: _togglePlay,
                    filled: true,
                  ),
                  const SizedBox(width: 28),
                  _centerBtn(
                    icon: Icons.forward_10_rounded,
                    size: 40,
                    onTap: () => _seekBy(10),
                  ),
                ],
              ),
            const Spacer(),
            if (widget.isLive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.sensors_rounded, color: accentOrange, size: 20),
                    const SizedBox(width: 8),
                    const Text('Transmisión en vivo', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    _actionIcon(_fitModeIcon, _fitModeLabel, _cycleFitMode),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(_currentPosition),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: accentOrange,
                          inactiveTrackColor: Colors.white.withValues(
                            alpha: 0.25,
                          ),
                          thumbColor: accentOrange,
                          overlayColor: accentOrange.withValues(alpha: 0.25),
                        ),
                        child: Slider(
                          value: _totalDuration.inSeconds > 0
                              ? _currentPosition.inSeconds
                                    .clamp(0, _totalDuration.inSeconds)
                                    .toDouble()
                              : 0.0,
                          max: _totalDuration.inSeconds > 0
                              ? _totalDuration.inSeconds.toDouble()
                              : 1.0,
                          onChanged: (v) {
                            setState(() {
                              _currentPosition = Duration(seconds: v.toInt());
                            });
                            _controller.seekTo(Duration(seconds: v.toInt()));
                          },
                          onChangeStart: (_) {
                            _hideControlsTimer?.cancel();
                            setState(() => _isDragging = true);
                          },
                          onChangeEnd: (_) {
                            setState(() => _isDragging = false);
                            _scheduleHideControls();
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(_totalDuration - _currentPosition),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _actionIcon(Icons.replay_rounded, 'Reiniciar', _restart),
                    if (_mediaType == 'tv' ||
                        (_showEndPrompt && _recomendaciones.isNotEmpty))
                      _actionIcon(
                        Icons.skip_next_rounded,
                        'Siguiente',
                        _goNextEpisode,
                      ),
                    // ── BOTÓN SUBTÍTULOS (abre el modal) ────────────────
                    _actionIcon(
                      _subtitlesEnabled
                          ? Icons.closed_caption_rounded
                          : Icons.closed_caption_disabled_rounded,
                      _selectedSubtitleLabel,
                      _openSubtitlesModal,
                    ),
                    _actionIcon(
                      Icons.translate_rounded,
                      'Idiomas',
                      () => _showAudioLanguageSelector(),
                    ),
                    _actionIcon(
                      Icons.high_quality_rounded,
                      _currentQualityLabel,
                      _openQualitySelector,
                    ),
                    _actionIcon(_fitModeIcon, _fitModeLabel, _cycleFitMode),
                    _actionIcon(
                      Icons.info_outline_rounded,
                      'Info',
                      _openInfoModal,
                    ),
                    if (_hasBottomContent)
                      _actionIcon(
                        _showBottomPanel
                            ? Icons.expand_more_rounded
                            : Icons.expand_less_rounded,
                        _showBottomPanel ? 'Ocultar' : 'Más',
                        () {
                          setState(() => _showBottomPanel = !_showBottomPanel);
                          if (_showBottomPanel) {
                            _hideControlsTimer?.cancel();
                          } else {
                            _scheduleHideControls();
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
            if (_showBottomPanel && _hasBottomContent) ...[
              const SizedBox(height: 10),
              if (_mediaType == 'tv' && _temporadas.isNotEmpty) ...[
                SizedBox(
                  height: 34,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _temporadas.length,
                    itemBuilder: (ctx, i) {
                      final temp = _temporadas[i] as Map;
                      final isSelected = i == _selectedSeasonIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedSeasonIndex = i),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accentOrange.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? accentOrange
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            temp['nombre']?.toString() ??
                                'Temporada ${temp['numero']}',
                            style: TextStyle(
                              color: isSelected ? accentOrange : Colors.white70,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(height: 90, child: _buildEpisodesList()),
              ] else if (_recomendaciones.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ver a continuación',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 90, child: _buildRecommendationsList()),
              ],
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _centerBtn({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size + 12,
        height: size + 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  Widget _actionIcon(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodesList() {
    if (_temporadas.isEmpty) return const SizedBox.shrink();
    final season = _temporadas[_selectedSeasonIndex];
    if (season is! Map) return const SizedBox.shrink();
    final caps = season['capitulos'] as List? ?? [];
    final seasonNum = season['numero'];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: caps.length,
      itemBuilder: (ctx, i) {
        final cap = caps[i];
        if (cap is! Map) return const SizedBox.shrink();
        final isActual = cap['actual'] == true;
        final num = cap['numero'];
        final titulo = cap['titulo'] ?? 'Episodio $num';
        final backdrop = _optimizeTmdbUrl(
          cap['backdrop']?.toString(),
          size: 'w300',
        );

        return GestureDetector(
          onTap: () {
            final tNum = seasonNum is int
                ? seasonNum
                : int.tryParse('$seasonNum');
            final cNum = num is int ? num : int.tryParse('$num');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  videoUrl: '',
                  idcontenido: _resolvedId,
                  tmdbId: _resolvedId,
                  temporada: tNum,
                  capitulo: cNum,
                  tipo: 'tv',
                  titulo: _tituloContenido.isNotEmpty
                      ? _tituloContenido
                      : widget.titulo,
                ),
              ),
            );
          },
          child: Container(
            width: 140,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActual ? accentOrange : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: backdrop,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) =>
                          ColoredBox(color: Colors.grey[900]!),
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: Colors.grey[900]!),
                    )
                  else
                    ColoredBox(color: Colors.grey[900]!),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xD9000000)],
                      ),
                    ),
                  ),
                  if (isActual)
                    const Positioned(
                      top: 4,
                      left: 4,
                      child: Icon(
                        Icons.play_circle_fill,
                        color: accentOrange,
                        size: 18,
                      ),
                    ),
                  Positioned(
                    bottom: 5,
                    left: 6,
                    right: 6,
                    child: Text(
                      '$num · $titulo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendationsList() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _recomendaciones.length,
      itemBuilder: (ctx, i) {
        final rec = _recomendaciones[i];
        if (rec is! Map) return const SizedBox.shrink();
        final poster = _optimizeTmdbUrl(
          (rec['backdrop'] ?? rec['poster'])?.toString(),
          size: 'w300',
        );
        final titulo = rec['titulo'] ?? '';
        final id = rec['tmdb_id'] ?? rec['idcontenido'];
        final tipo = rec['tipo']?.toString() ?? 'movie';

        return GestureDetector(
          onTap: () {
            final idInt = id is int ? id : int.tryParse('$id') ?? 0;
            if (idInt <= 0) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  videoUrl: '',
                  idcontenido: idInt,
                  tmdbId: idInt,
                  tipo: tipo,
                  titulo: titulo.toString().isNotEmpty
                      ? titulo.toString()
                      : widget.titulo,
                ),
              ),
            );
          },
          child: Container(
            width: 150,
            margin: const EdgeInsets.only(right: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) =>
                          ColoredBox(color: Colors.grey[900]!),
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: Colors.grey[900]!),
                    )
                  else
                    ColoredBox(color: Colors.grey[900]!),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xE6000000)],
                        ),
                      ),
                      child: Text(
                        titulo.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}