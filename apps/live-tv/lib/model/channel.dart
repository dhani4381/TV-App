class Channel {
  final String name;
  final String logoUrl;
  final String category;
  final String tvgId;
  final int number;

  /// First URL is the main stream; the rest are backups tried when it fails.
  final List<String> streamUrls;

  Channel({
    required this.name,
    required this.logoUrl,
    required this.category,
    required this.streamUrls,
    this.tvgId = '',
    this.number = 0,
  });

  bool get hasLogo => logoUrl.startsWith('http');

  Map<String, dynamic> toJson() => {
        'n': name,
        'l': logoUrl,
        'c': category,
        'i': tvgId,
        'no': number,
        's': streamUrls,
      };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        name: j['n'] as String,
        logoUrl: j['l'] as String,
        category: j['c'] as String,
        tvgId: j['i'] as String? ?? '',
        number: j['no'] as int? ?? 0,
        streamUrls: (j['s'] as List).cast<String>(),
      );
}
