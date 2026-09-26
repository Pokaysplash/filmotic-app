class LiveChannel {
  final String id; // hash único del canal
  final String name; // "Caracol TV"
  final String? logo; // URL del logo
  final String? group; // "Deportes", "Noticias", etc.
  final String? country; // "CO"
  final String? language; // "spa"
  final String streamUrl; // URL del stream (.m3u8 normalmente)
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
    required this.sourceList,
    this.isHD = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'logo': logo,
        'group': group,
        'country': country,
        'language': language,
        'stream_url': streamUrl,
        'source_list': sourceList,
        'is_hd': isHD,
      };

  factory LiveChannel.fromMap(Map<String, dynamic> map) => LiveChannel(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Canal en Vivo',
        logo: map['logo']?.toString(),
        group: map['group']?.toString(),
        country: map['country']?.toString(),
        language: map['language']?.toString(),
        streamUrl: map['stream_url']?.toString() ?? '',
        sourceList: map['source_list']?.toString() ?? '',
        isHD: map['is_hd'] == true,
      );
}
