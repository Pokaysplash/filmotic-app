class LiveChannel {
  final String id; // hash único del canal
  final String name; // "Caracol TV"
  final String? logo; // URL del logo
  final String? group; // "Deportes", "Noticias", etc.
  final String? country; // "CO"
  final String? language; // "spa"
  final String streamUrl; // URL principal del stream
  final List<String> alternateUrls; // URLs de respaldo / opciones adicionales
  final String sourceList; // de qué lista vino (para diagnóstico)
  final bool isHD;

  LiveChannel({
    required this.id,
    required this.name,
    this.logo,
    this.group,
    this.country,
    this.language,
    required this.streamUrl,
    this.alternateUrls = const [],
    required this.sourceList,
    this.isHD = false,
  });

  /// Todas las señales disponibles sin duplicados y limpias
  List<String> get allStreamUrls {
    final urls = <String>[];
    if (streamUrl.trim().isNotEmpty) urls.add(streamUrl.trim());
    for (final alt in alternateUrls) {
      final t = alt.trim();
      if (t.isNotEmpty && !urls.contains(t)) {
        urls.add(t);
      }
    }
    return urls;
  }

  LiveChannel copyWith({
    String? id,
    String? name,
    String? logo,
    String? group,
    String? country,
    String? language,
    String? streamUrl,
    List<String>? alternateUrls,
    String? sourceList,
    bool? isHD,
  }) =>
      LiveChannel(
        id: id ?? this.id,
        name: name ?? this.name,
        logo: logo ?? this.logo,
        group: group ?? this.group,
        country: country ?? this.country,
        language: language ?? this.language,
        streamUrl: streamUrl ?? this.streamUrl,
        alternateUrls: alternateUrls ?? this.alternateUrls,
        sourceList: sourceList ?? this.sourceList,
        isHD: isHD ?? this.isHD,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'logo': logo,
        'group': group,
        'country': country,
        'language': language,
        'stream_url': streamUrl,
        'alternate_urls': alternateUrls,
        'source_list': sourceList,
        'is_hd': isHD,
      };

  factory LiveChannel.fromMap(Map<String, dynamic> map) {
    final alts = (map['alternate_urls'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return LiveChannel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Canal en Vivo',
      logo: map['logo']?.toString(),
      group: map['group']?.toString(),
      country: map['country']?.toString(),
      language: map['language']?.toString(),
      streamUrl: map['stream_url']?.toString() ?? '',
      alternateUrls: alts,
      sourceList: map['source_list']?.toString() ?? '',
      isHD: map['is_hd'] == true,
    );
  }
}

