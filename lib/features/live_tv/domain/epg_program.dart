class EpgProgram {
  final String id; // hash único
  final String channelId; // referencia al tvg-id del canal
  final String title;
  final String? description;
  final String? category;
  final String? icon;
  final DateTime startTime; // UTC
  final DateTime endTime; // UTC
  final bool isNew;
  final bool isLive; // calculado dinámicamente

  EpgProgram({
    required this.id,
    required this.channelId,
    required this.title,
    this.description,
    this.category,
    this.icon,
    required this.startTime,
    required this.endTime,
    this.isNew = false,
    this.isLive = false,
  });

  bool get isCurrentlyAiring {
    final now = DateTime.now().toUtc();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  Duration get duration => endTime.difference(startTime);

  double get progress {
    final now = DateTime.now().toUtc();
    if (now.isBefore(startTime)) return 0.0;
    if (now.isAfter(endTime)) return 1.0;
    final totalSec = duration.inSeconds;
    if (totalSec <= 0) return 0.0;
    return (now.difference(startTime).inSeconds / totalSec).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'channel_id': channelId,
        'title': title,
        'description': description,
        'category': category,
        'icon': icon,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'is_new': isNew,
        'is_live': isLive,
      };

  factory EpgProgram.fromMap(Map<String, dynamic> map) => EpgProgram(
        id: map['id']?.toString() ?? '',
        channelId: map['channel_id']?.toString() ?? '',
        title: map['title']?.toString() ?? 'Sin título',
        description: map['description']?.toString(),
        category: map['category']?.toString(),
        icon: map['icon']?.toString(),
        startTime: DateTime.tryParse(map['start_time']?.toString() ?? '') ?? DateTime.now().toUtc(),
        endTime: DateTime.tryParse(map['end_time']?.toString() ?? '') ?? DateTime.now().toUtc(),
        isNew: map['is_new'] == true,
        isLive: map['is_live'] == true,
      );
}
