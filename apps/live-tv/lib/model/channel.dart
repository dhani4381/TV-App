class Channel {
  final String name;
  final String logoUrl;
  final String category;
  final String tvgId;
  final int number;

  /// First URL is the main stream; the rest are backups tried when it fails.
  final List<String> streamUrls;

  /// True if the channel has Telugu audio or belongs to Telugu regional network
  final bool isTelugu;

  /// True if user or catalog marked as a verified working favorite
  final bool isFavorite;

  Channel({
    required this.name,
    required this.logoUrl,
    required this.category,
    required this.streamUrls,
    this.tvgId = '',
    this.number = 0,
    this.isTelugu = false,
    this.isFavorite = false,
  });

  bool get hasLogo => logoUrl.startsWith('http');

  Channel copyWith({
    String? name,
    String? logoUrl,
    String? category,
    String? tvgId,
    int? number,
    List<String>? streamUrls,
    bool? isTelugu,
    bool? isFavorite,
  }) {
    return Channel(
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      category: category ?? this.category,
      tvgId: tvgId ?? this.tvgId,
      number: number ?? this.number,
      streamUrls: streamUrls ?? this.streamUrls,
      isTelugu: isTelugu ?? this.isTelugu,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
        'n': name,
        'l': logoUrl,
        'c': category,
        'i': tvgId,
        'no': number,
        's': streamUrls,
        'tel': isTelugu,
        'fav': isFavorite,
      };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        name: j['n'] as String,
        logoUrl: j['l'] as String,
        category: j['c'] as String,
        tvgId: j['i'] as String? ?? '',
        number: j['no'] as int? ?? 0,
        streamUrls: (j['s'] as List).cast<String>(),
        isTelugu: j['tel'] as bool? ?? false,
        isFavorite: j['fav'] as bool? ?? false,
      );
}
