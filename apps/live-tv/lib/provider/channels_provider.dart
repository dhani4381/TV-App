import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../model/channel.dart';

/// Sidebar order. Favorites and Telugu come first, followed by genres.
const categoryOrder = [
  'Favorites',
  'Telugu',
  'News',
  'Entertainment',
  'Movies',
  'Sports',
  'Devotional',
  'Kids',
  'Music',
  'Infotainment',
  'Business',
  'Other',
];

/// Keywords for verified working favorite channels
const verifiedFavoriteKeywords = [
  'star maa hd',
  'star maa movies',
  'zee telugu hd',
  'sun gemini',
  'etv cinema',
  'etv plus',
  'etv comedy',
  'etv josh',
  'etv news',
  'etv beats',
  'tv9 telugu',
  'ntv telugu',
  'sakshi tv',
  'abn andhra',
  'v6 news',
  '10 tv',
  'bhakthi tv',
  'svbc',
  'aastha telugu',
  'star sports 2 telugu',
  'dd sports hd',
  'aaj tak hd',
  'abp news',
  'ndtv 24x7',
  'ndtv india',
  'india tv',
  'republic bharat',
  'discovery channel (india) hd',
  'discovery kids',
  'cartoon network (india)',
  'hungama tv',
  'nickelodeon (india)',
  'national geographic (india) hd',
  'sony bbc earth hd',
  'b4u movies',
  'b4u music',
  'raj musix telugu',
];

/// Loads every playlist in the catalog, prioritizes verified Telugu & Indian HD streams,
/// handles user favorites, and caches the result on disk.
class ChannelsProvider {
  static const streamsCatalogUrl =
      'https://raw.githubusercontent.com/kananinirav/Indian-IPTV-App/refs/heads/master/data/streams.csv';

  /// Dedicated Telugu playlist
  static const teluguM3uUrl = 'https://iptv-org.github.io/iptv/languages/tel.m3u';

  /// Complete Indian stream index
  static const indianM3uUrl = 'https://raw.githubusercontent.com/iptv-org/iptv/refs/heads/master/streams/in.m3u';

  /// Carries logos and group-titles (categories) for Indian channels.
  static const logoIndexUrl = 'https://iptv-org.github.io/iptv/countries/in.m3u';

  static const _cacheFile = 'channels_v3.json';
  static const _favsFile = 'user_favorites.json';
  static const _timeout = Duration(seconds: 20);

  /// Loads custom user-saved favorites from disk.
  Future<Set<String>> loadUserFavorites() async {
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/$_favsFile');
      if (!await f.exists()) return {};
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Saves custom user-saved favorites to disk.
  Future<void> saveUserFavorites(Set<String> favs) async {
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/$_favsFile');
      await f.writeAsString(jsonEncode(favs.toList()));
    } catch (_) {}
  }

  /// Last result saved on disk, so the app can show channels instantly on start.
  Future<List<Channel>?> loadCached() async {
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/$_cacheFile');
      if (!await f.exists()) return null;
      final list = await compute(_decodeChannels, await f.readAsString());
      return list.isEmpty ? null : list;
    } catch (_) {
      return null;
    }
  }

  /// Downloads playlists, parses off UI thread, merges favorites & Telugu channels, saves cache.
  Future<List<Channel>> refresh() async {
    final userFavs = await loadUserFavorites();

    final sources = <MapEntry<String, String>>[
      const MapEntry('Telugu', teluguM3uUrl),
      const MapEntry('Indian', indianM3uUrl),
    ];

    try {
      final catalog = await http.get(Uri.parse(streamsCatalogUrl)).timeout(_timeout);
      if (catalog.statusCode == 200) {
        sources.addAll(_parseCatalog(catalog.body));
      }
    } catch (_) {}

    // Check if JioTV-Go local server is running on the TV (port 5350 or fallback 5001)
    for (final port in [5350, 5001]) {
      try {
        final jioRes = await http
            .get(Uri.parse('http://127.0.0.1:$port/channels?type=m3u&q=&c=&l=&sg=&sub='))
            .timeout(const Duration(seconds: 3));
        if (jioRes.statusCode == 200 && jioRes.body.contains('#EXTINF')) {
          sources.add(MapEntry('JioTV', 'http://127.0.0.1:$port/channels?type=m3u&q=&c=&l=&sg=&sub='));
          break;
        }
      } catch (_) {}
    }

    final responses = await Future.wait([
      http.get(Uri.parse(logoIndexUrl)).timeout(_timeout).then(
          (r) => r.statusCode == 200 ? r.body : '',
          onError: (_) => ''),
      for (final s in sources)
        http.get(Uri.parse(s.value)).timeout(_timeout).then(
            (r) => r.statusCode == 200 ? r.body : '',
            onError: (_) => ''),
    ]);

    final args = <String, dynamic>{
      'index': responses.first,
      'playlists': [
        for (var i = 0; i < sources.length; i++)
          {'name': sources[i].key, 'body': responses[i + 1]},
      ],
      'userFavs': userFavs.toList(),
    };
    final json = await compute(_buildChannels, args);
    if (json.isEmpty) throw Exception('No channels found');

    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/$_cacheFile');
      await f.writeAsString(jsonEncode(json));
    } catch (_) {}
    return json.map(Channel.fromJson).toList();
  }

  static List<MapEntry<String, String>> _parseCatalog(String csv) {
    final out = <MapEntry<String, String>>[];
    for (final line in csv.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.toLowerCase().startsWith('name,')) continue;
      final comma = t.indexOf(',');
      if (comma <= 0) continue;
      out.add(MapEntry(t.substring(0, comma).trim(), t.substring(comma + 1).trim()));
    }
    return out;
  }
}

List<Channel> _decodeChannels(String text) {
  final list = jsonDecode(text) as List;
  return list.map((e) => Channel.fromJson(e as Map<String, dynamic>)).toList();
}

// ---------------------------------------------------------------- parsing (runs in an isolate)

final _tvgId = RegExp(r'tvg-id="([^"]*)"');
final _tvgLogo = RegExp(r'tvg-logo="([^"]*)"');
final _group = RegExp(r'group-title="([^"]*)"');
final _language = RegExp(r'tvg-language="([^"]*)"');

class _Entry {
  final String info;
  final String url;
  _Entry(this.info, this.url);

  String attr(RegExp r) => r.firstMatch(info)?.group(1) ?? '';
  String get name => info.substring(info.lastIndexOf(',') + 1).trim();
}

List<_Entry> _entries(String body) {
  final out = <_Entry>[];
  String? info;
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF:')) {
      info = line;
    } else if (line.isNotEmpty && !line.startsWith('#') && info != null) {
      out.add(_Entry(info, line));
      info = null;
    }
  }
  return out;
}

String _baseId(String id) => id.split('@').first.toLowerCase();

String _nameKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
    .replaceAll(RegExp(r'\bhd\b'), '')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

String _cleanName(String name) =>
    name.replaceAll(RegExp(r'\s*\(\d+[pi]\)'), '').replaceAll(RegExp(r'\s*\[.*?\]'), '').trim();

bool _isTeluguChannel(String name, String group, String lang, String playlistName) {
  if (playlistName.toLowerCase().contains('telugu')) return true;
  final l = lang.toLowerCase();
  if (l.contains('telugu') || l == 'tel') return true;
  final g = group.toLowerCase();
  if (g.contains('telugu')) return true;
  final n = name.toLowerCase();
  return n.contains('telugu') ||
      n.contains('etv') ||
      n.contains('gemini') ||
      n.contains('maa') ||
      n.contains('tv9 tel') ||
      n.contains('ntv') ||
      n.contains('sakshi') ||
      n.contains('abn') ||
      n.contains('v6') ||
      n.contains('bhakthi') ||
      n.contains('svbc') ||
      n.contains('10 tv') ||
      n.contains('99tv') ||
      n.contains('hmtv') ||
      n.contains('t news') ||
      n.contains('prime9') ||
      n.contains('cvr') ||
      n.contains('swatantra') ||
      n.contains('tolly') ||
      n.contains('kushi') ||
      n.contains('vanitha') ||
      n.contains('vissa') ||
      n.contains('subhavartha') ||
      n.contains('aastha telugu');
}

String _category(String group, bool isTelugu) {
  final g = group.split(';').first.trim().toLowerCase();
  switch (g) {
    case 'news':
    case 'legislative':
      return 'News';
    case 'entertainment':
    case 'general':
    case 'comedy':
    case 'series':
      return 'Entertainment';
    case 'movies':
    case 'classic':
      return 'Movies';
    case 'music':
      return 'Music';
    case 'sports':
      return 'Sports';
    case 'kids':
    case 'animation':
    case 'family':
      return 'Kids';
    case 'documentary':
    case 'science':
    case 'travel':
    case 'culture':
    case 'education':
    case 'lifestyle':
    case 'cooking':
    case 'outdoor':
      return 'Infotainment';
    case 'business':
      return 'Business';
    case 'religious':
    case 'spiritual':
      return 'Devotional';
    default:
      if (isTelugu) return 'Entertainment';
      return 'Other';
  }
}

int _assignChannelNumber(String name, String category, bool isTelugu) {
  final n = name.toLowerCase();

  if (isTelugu) {
    // 100s: Telugu News
    if (n.contains('tv9')) return 101;
    if (n.contains('ntv')) return 102;
    if (n.contains('sakshi')) return 103;
    if (n.contains('abn')) return 104;
    if (n.contains('v6')) return 105;
    if (n.contains('10 tv')) return 106;
    if (n.contains('etv news') || n.contains('etv andhra') || n.contains('etv telangana')) return 107;
    if (n.contains('99tv')) return 108;
    if (n.contains('t news') || n.contains('hmtv') || n.contains('prime9')) return 109;

    // 200s: Telugu Entertainment & Movies
    if (n.contains('star maa hd') || (n.contains('star maa') && !n.contains('movies'))) return 201;
    if (n.contains('star maa movies') || n.contains('maa movies')) return 202;
    if (n.contains('zee telugu')) return 203;
    if (n.contains('sun gemini') || (n.contains('gemini') && !n.contains('music') && !n.contains('comedy'))) return 204;
    if (n.contains('etv cinema')) return 205;
    if (n.contains('etv plus')) return 206;
    if (n.contains('etv comedy')) return 207;
    if (n.contains('etv josh') || n.contains('etv telugu')) return 208;
    if (n.contains('gemini comedy') || n.contains('gemini life')) return 209;

    // 300s: Telugu Devotional
    if (n.contains('bhakthi') || n.contains('bhakti')) return 301;
    if (n.contains('svbc') || n.contains('venkateshwar')) return 302;
    if (n.contains('aastha telugu')) return 303;
    if (n.contains('cvr om')) return 304;
    if (n.contains('subhavartha')) return 305;
    if (n.contains('divyavani') || n.contains('calvary')) return 306;

    // 400s: Sports
    if (n.contains('star sports 2 telugu')) return 401;
    if (n.contains('dd sports')) return 402;
    if (n.contains('star sports')) return 403;

    // 500s: Telugu Kids & Infotainment
    if (n.contains('discovery channel') || n.contains('discovery telugu')) return 501;
    if (n.contains('discovery kids')) return 502;
    if (n.contains('cartoon network')) return 503;
    if (n.contains('nick')) return 504;
    if (n.contains('hungama')) return 505;
    if (n.contains('national geographic')) return 506;
    if (n.contains('sony bbc earth')) return 507;

    // 600s: Telugu Music
    if (n.contains('etv beats')) return 601;
    if (n.contains('raj musi')) return 602;
    if (n.contains('gemini music')) return 603;
    return 0;
  }

  // National Indian channels
  if (n.contains('aaj tak')) return 111;
  if (n.contains('abp news')) return 112;
  if (n.contains('zee news')) return 113;
  if (n.contains('ndtv')) return 114;
  if (n.contains('india tv')) return 115;
  if (n.contains('news18')) return 116;
  if (n.contains('republic')) return 117;
  if (n.contains('dd news')) return 118;
  if (n.contains('wion')) return 119;

  if (n.contains('star plus')) return 211;
  if (n.contains('colors') && !n.contains('cineplex')) return 212;
  if (n.contains('sony entertainment') || n.contains('set india') || n.contains('sony tv')) return 213;
  if (n.contains('zee tv')) return 214;
  if (n.contains('sony sab') || n.contains('sab tv')) return 215;
  if (n.contains('star bharat')) return 216;
  if (n.contains('dd national')) return 217;

  if (n.contains('aastha')) return 311;
  if (n.contains('sanskar')) return 312;
  if (n.contains('sadhna')) return 313;

  if (n.contains('star gold')) return 411;
  if (n.contains('sony max')) return 412;
  if (n.contains('zee cinema')) return 413;
  if (n.contains('colors cineplex')) return 414;
  if (n.contains('b4u movies')) return 415;

  if (n.contains('star sports 1')) return 511;
  if (n.contains('sony sports') || n.contains('sony ten')) return 512;
  if (n.contains('sports18')) return 513;

  if (n.contains('9xm')) return 611;
  if (n.contains('b4u music')) return 612;

  return 0;
}

List<Map<String, dynamic>> _buildChannels(Map<String, dynamic> args) {
  final userFavs = (args['userFavs'] as List).cast<String>().toSet();

  // index: channel id / name -> logo + group
  final logoById = <String, String>{}, logoByName = <String, String>{};
  final groupById = <String, String>{}, groupByName = <String, String>{};
  for (final e in _entries(args['index'] as String)) {
    final id = _baseId(e.attr(_tvgId));
    final key = _nameKey(e.name);
    final logo = e.attr(_tvgLogo);
    final group = e.attr(_group);
    if (logo.startsWith('http')) {
      if (id.isNotEmpty) logoById.putIfAbsent(id, () => logo);
      logoByName.putIfAbsent(key, () => logo);
    }
    if (group.isNotEmpty) {
      if (id.isNotEmpty) groupById.putIfAbsent(id, () => group);
      groupByName.putIfAbsent(key, () => group);
    }
  }

  // merge all playlists; same channel in the same category -> one tile with backup streams
  final byKey = <String, Map<String, dynamic>>{};
  for (final p in (args['playlists'] as List).cast<Map>()) {
    final pName = (p['name'] as String);
    final isTeluguSource = pName.toLowerCase().contains('telugu');
    final sportsList = pName.toLowerCase().contains('sport');
    final isJio = pName.toLowerCase().contains('jio');

    for (final e in _entries(p['body'] as String)) {
      if (!isJio && !isTeluguSource && !e.name.contains('(1080p)') && !e.name.contains('(720p)')) {
        continue;
      }
      final id = e.attr(_tvgId);
      final base = _baseId(id);
      final key = _nameKey(e.name);
      final cleanName = _cleanName(e.name);
      final rawGroup = e.attr(_group).isNotEmpty
          ? e.attr(_group)
          : (groupById[base] ?? groupByName[key] ?? '');
      final rawLang = e.attr(_language);

      final isTelugu = _isTeluguChannel(cleanName, rawGroup, rawLang, pName);
      final category = sportsList ? 'Sports' : _category(rawGroup, isTelugu);

      var logo = e.attr(_tvgLogo);
      if (!logo.startsWith('http')) logo = logoById[base] ?? logoByName[key] ?? '';

      final isFav = userFavs.contains(cleanName) ||
          verifiedFavoriteKeywords.any((kw) => cleanName.toLowerCase().contains(kw));

      final chNo = _assignChannelNumber(cleanName, category, isTelugu);

      final mapKey = '$category|$key';
      final existing = byKey[mapKey];
      if (existing != null) {
        final urls = existing['s'] as List<String>;
        if (!urls.contains(e.url)) urls.add(e.url);
        if (isTelugu) existing['tel'] = true;
        if (isFav) existing['fav'] = true;
        if (chNo > 0 && (existing['no'] as int? ?? 0) == 0) existing['no'] = chNo;
        continue;
      }

      byKey[mapKey] = {
        'n': cleanName,
        'l': logo,
        'c': category,
        'i': id,
        'no': chNo,
        's': <String>[e.url],
        'tel': isTelugu,
        'fav': isFav,
      };
    }
  }

  final list = byKey.values.toList();
  bool indian(Map m) => (m['i'] as String).contains('.in@') || (m['i'] as String).endsWith('.in');

  list.sort((a, b) {
    // 1. Favorites first
    final favA = (a['fav'] as bool? ?? false) ? 0 : 1;
    final favB = (b['fav'] as bool? ?? false) ? 0 : 1;
    if (favA != favB) return favA - favB;

    // 2. Telugu channels prioritized
    final telA = (a['tel'] as bool? ?? false) ? 0 : 1;
    final telB = (b['tel'] as bool? ?? false) ? 0 : 1;
    if (telA != telB) return telA - telB;

    // 3. Indian channels
    final ia = indian(a) ? 0 : 1, ib = indian(b) ? 0 : 1;
    if (ia != ib) return ia - ib;

    // 4. Numbered channels first in numeric order (101, 102, 201...)
    final noA = (a['no'] as int? ?? 0), noB = (b['no'] as int? ?? 0);
    if (noA > 0 && noB > 0) return noA.compareTo(noB);
    if (noA > 0) return -1;
    if (noB > 0) return 1;

    return (a['n'] as String).toLowerCase().compareTo((b['n'] as String).toLowerCase());
  });
  return list;
}
