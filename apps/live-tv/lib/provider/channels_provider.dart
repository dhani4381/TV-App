import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../model/channel.dart';

/// Sidebar order. Categories with no channels are hidden.
const categoryOrder = [
  'Devotional',
  'News',
  'Entertainment',
  'Movies',
  'Sports',
  'Music',
  'Kids',
  'Infotainment',
  'Business',
  'Other',
];

/// Loads every playlist in the catalog, keeps HD streams, adds logos and
/// categories from the iptv-org India index, supports JioTV-Go, and caches the result on disk.
class ChannelsProvider {
  static const streamsCatalogUrl =
      'https://raw.githubusercontent.com/kananinirav/Indian-IPTV-App/refs/heads/master/data/streams.csv';

  /// Carries logos and group-titles (categories) for Indian channels.
  static const logoIndexUrl = 'https://iptv-org.github.io/iptv/countries/in.m3u';

  static const _cacheFile = 'channels_v2.json';
  static const _timeout = Duration(seconds: 20);

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

  /// Downloads everything in parallel, parses off the UI thread, saves the cache.
  Future<List<Channel>> refresh() async {
    final catalog = await http.get(Uri.parse(streamsCatalogUrl)).timeout(_timeout);
    if (catalog.statusCode != 200) throw Exception('Failed to load stream sources');
    final sources = _parseCatalog(catalog.body);

    // Check if JioTV-Go local server is running on the TV (default port 5350, fallback 5001)
    for (final port in [5350, 5001]) {
      try {
        final jioRes = await http.get(Uri.parse('http://127.0.0.1:$port/playlist.m3u')).timeout(const Duration(seconds: 3));
        if (jioRes.statusCode == 200 && jioRes.body.contains('#EXTINF')) {
          sources.add(MapEntry('JioTV', 'http://127.0.0.1:$port/playlist.m3u'));
          break;
        }
      } catch (_) {}
    }

    final responses = await Future.wait([
      http.get(Uri.parse(logoIndexUrl)).timeout(_timeout).then((r) => r.statusCode == 200 ? r.body : '',
          onError: (_) => ''),
      for (final s in sources)
        http.get(Uri.parse(s.value)).timeout(_timeout).then((r) => r.statusCode == 200 ? r.body : '',
            onError: (_) => ''),
    ]);

    final args = <String, dynamic>{
      'index': responses.first,
      'playlists': [
        for (var i = 0; i < sources.length; i++) {'name': sources[i].key, 'body': responses[i + 1]},
      ],
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

/// "AajTak.in@HD" -> "aajtak.in": logos and categories are shared by every feed.
String _baseId(String id) => id.split('@').first.toLowerCase();

/// "Aaj Tak HD (1080p) [Geo-blocked]" -> "aajtak"
String _nameKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
    .replaceAll(RegExp(r'\bhd\b'), '')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// "Aaj Tak HD (1080p) [Geo-blocked]" -> "Aaj Tak HD"
String _cleanName(String name) =>
    name.replaceAll(RegExp(r'\s*\(\d+[pi]\)'), '').replaceAll(RegExp(r'\s*\[.*?\]'), '').trim();

String _category(String group) {
  switch (group.split(';').first.trim().toLowerCase()) {
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
      return 'Devotional';
    default:
      return 'Other';
  }
}

int _assignChannelNumber(String name, String category) {
  final n = name.toLowerCase();
  if (n.contains('aaj tak')) return 101;
  if (n.contains('abp news')) return 102;
  if (n.contains('zee news')) return 103;
  if (n.contains('ndtv')) return 104;
  if (n.contains('india tv')) return 105;
  if (n.contains('news18')) return 106;
  if (n.contains('republic')) return 107;
  if (n.contains('dd news')) return 108;
  if (n.contains('wion')) return 109;

  if (n.contains('star plus')) return 201;
  if (n.contains('colors') && !n.contains('cineplex')) return 202;
  if (n.contains('sony entertainment') || n.contains('set india') || n.contains('sony tv')) return 203;
  if (n.contains('zee tv')) return 204;
  if (n.contains('sony sab') || n.contains('sab tv')) return 205;
  if (n.contains('&tv') || n.contains('and tv')) return 206;
  if (n.contains('star bharat')) return 207;
  if (n.contains('dangal')) return 208;
  if (n.contains('dd national')) return 209;

  if (n.contains('aastha')) return 301;
  if (n.contains('sanskar')) return 302;
  if (n.contains('sadhna')) return 303;
  if (n.contains('peace of mind')) return 304;
  if (n.contains('arihant')) return 305;
  if (n.contains('bhakti')) return 306;
  if (n.contains('divya')) return 307;
  if (n.contains('ishwar')) return 308;
  if (n.contains('hare krishna')) return 309;

  if (n.contains('star gold')) return 401;
  if (n.contains('sony max')) return 402;
  if (n.contains('zee cinema')) return 403;
  if (n.contains('colors cineplex')) return 404;
  if (n.contains('b4u movies')) return 405;
  if (n.contains('cinema tv')) return 406;
  if (n.contains('&pictures') || n.contains('and pictures')) return 407;

  if (n.contains('star sports 1')) return 501;
  if (n.contains('star sports hindi')) return 502;
  if (n.contains('sony sports') || n.contains('sony ten')) return 503;
  if (n.contains('sports18')) return 504;
  if (n.contains('dd sports')) return 505;

  if (n.contains('9xm')) return 601;
  if (n.contains('9x jalwa')) return 602;
  if (n.contains('9x tashan')) return 603;
  if (n.contains('9x jhakaas')) return 604;
  if (n.contains('b4u music')) return 605;
  if (n.contains('mtv beats')) return 606;

  return 0;
}

List<Map<String, dynamic>> _buildChannels(Map<String, dynamic> args) {
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
    final sportsList = (p['name'] as String).toLowerCase().contains('sport');
    final isJio = (p['name'] as String).toLowerCase().contains('jio');
    for (final e in _entries(p['body'] as String)) {
      if (!isJio && !e.name.contains('(1080p)') && !e.name.contains('(720p)')) continue;
      final id = e.attr(_tvgId);
      final base = _baseId(id);
      final key = _nameKey(e.name);
      final category = sportsList
          ? 'Sports'
          : _category(e.attr(_group).isNotEmpty ? e.attr(_group) : (groupById[base] ?? groupByName[key] ?? ''));
      var logo = e.attr(_tvgLogo);
      if (!logo.startsWith('http')) logo = logoById[base] ?? logoByName[key] ?? '';
      final existing = byKey['$category|$key'];
      if (existing != null) {
        final urls = existing['s'] as List<String>;
        if (!urls.contains(e.url)) urls.add(e.url);
        continue;
      }
      final cleanName = _cleanName(e.name);
      final chNo = _assignChannelNumber(cleanName, category);
      byKey['$category|$key'] = {
        'n': cleanName,
        'l': logo,
        'c': category,
        'i': id,
        'no': chNo,
        's': <String>[e.url],
      };
    }
  }

  final list = byKey.values.toList();
  bool indian(Map m) => (m['i'] as String).contains('.in@') || (m['i'] as String).endsWith('.in');
  list.sort((a, b) {
    // Indian channels first (matters for the mostly international Sports list)
    final ia = indian(a) ? 0 : 1, ib = indian(b) ? 0 : 1;
    if (ia != ib) return ia - ib;
    // Numbered channels first in numeric order (101, 102, 201...)
    final noA = (a['no'] as int? ?? 0), noB = (b['no'] as int? ?? 0);
    if (noA > 0 && noB > 0) return noA.compareTo(noB);
    if (noA > 0) return -1;
    if (noB > 0) return 1;
    return (a['n'] as String).toLowerCase().compareTo((b['n'] as String).toLowerCase());
  });
  return list;
}
