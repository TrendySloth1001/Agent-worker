import 'dart:async';
import 'dart:convert';

import '../core/constants/app_config.dart';
import '../core/constants/playlist.dart';
import 'api_client.dart';
import 'chat_api.dart';

/// One suggested song as the model wrote it.
class PlaylistSong {
  const PlaylistSong(this.title, this.artist);
  final String title, artist;

  @override
  bool operator ==(Object other) =>
      other is PlaylistSong && other.title == title && other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);
}

/// A parsed ```sparky-playlist block.
class PlaylistSpec {
  const PlaylistSpec(this.title, this.songs, {this.appKey});
  final String title;
  final List<PlaylistSong> songs;

  /// The music app the user named (a MediaApps key), if any.
  final String? appKey;

  /// Parses the block body; null when it holds no song.
  static PlaylistSpec? parse(String source) {
    var title = '';
    String? app;
    final songs = <PlaylistSong>[];
    final row = RegExp(r'^(?:[-*•]|\d{1,2}[.)])?\s*(.+?)\s*\|\s*(.*)$');
    for (final raw in source.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();
      if (lower.startsWith(PlaylistWire.titleKey)) {
        title = line.substring(PlaylistWire.titleKey.length).trim();
        continue;
      }
      if (lower.startsWith(PlaylistWire.appKey)) {
        app = line
            .substring(PlaylistWire.appKey.length)
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '_');
        continue;
      }
      final m = row.firstMatch(line);
      if (m == null) continue;
      songs.add(PlaylistSong(m.group(1)!.trim(), m.group(2)!.trim()));
      if (songs.length >= PlaylistSizes.maxSongs) break;
    }
    if (songs.isEmpty) return null;
    return PlaylistSpec(
      title.isEmpty ? PlaylistStrings.untitled : title,
      songs,
      appKey: app == null || app.isEmpty ? null : app,
    );
  }
}

/// What iTunes knew about a song (all optional: a row works without it).
class PlaylistTrack {
  const PlaylistTrack({
    required this.title,
    required this.artist,
    this.art,
    this.durationMs,
    this.previewUrl,
    this.album,
    this.year,
    this.link,
  });

  final String title, artist;
  final String? art, previewUrl, album, link;
  final int? durationMs, year;

  /// "4:22", or '' when unknown.
  String get duration {
    final ms = durationMs;
    if (ms == null || ms <= 0) return '';
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static PlaylistTrack fromJson(Map<String, dynamic> j, PlaylistSong fallback) {
    String? s(String k) =>
        j[k] is String && (j[k] as String).isNotEmpty ? j[k] as String : null;
    int? n(String k) => j[k] is num ? (j[k] as num).round() : null;
    return PlaylistTrack(
      title: s(PlaylistWire.title) ?? fallback.title,
      artist: s(PlaylistWire.artist) ?? fallback.artist,
      art: s(PlaylistWire.art),
      durationMs: n(PlaylistWire.durationMs),
      previewUrl: s(PlaylistWire.previewUrl),
      album: s(PlaylistWire.album),
      year: n(PlaylistWire.year),
      link: s(PlaylistWire.link),
    );
  }
}

/// "Play all": YouTube's temporary playlist of the resolved videos.
class PlaylistPlayAll {
  const PlaylistPlayAll(this.url);
  final String? url;
}

/// The backend's `/playlist` routes (iTunes covers and previews, YouTube
/// video ids). Tests swap [instance].
class PlaylistApi {
  PlaylistApi();

  static PlaylistApi instance = PlaylistApi();

  final _client = AuthClient();

  static const timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> _post(
    String path,
    List<PlaylistSong> songs,
  ) async {
    final res = await _client
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: apiHeaders(json: true),
          body: jsonEncode({
            PlaylistWire.items: [
              for (final s in songs)
                {PlaylistWire.title: s.title, PlaylistWire.artist: s.artist},
            ],
          }),
        )
        .timeout(timeout);
    if (res.statusCode >= 400) throw Exception('playlist ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// One track per song, in order (a song iTunes does not know keeps its
  /// title and artist only).
  Future<List<PlaylistTrack>> enrich(List<PlaylistSong> songs) async {
    final j = await _post(PlaylistWire.enrichPath, songs);
    final list = j[PlaylistWire.tracks];
    return [
      for (var i = 0; i < songs.length; i++)
        if (list is List && i < list.length && list[i] is Map<String, dynamic>)
          PlaylistTrack.fromJson(list[i] as Map<String, dynamic>, songs[i])
        else
          PlaylistTrack(title: songs[i].title, artist: songs[i].artist),
    ];
  }

  /// The Play all link, or null when too few videos were found.
  Future<PlaylistPlayAll> playAll(List<PlaylistSong> songs) async {
    final j = await _post(PlaylistWire.youtubePath, songs);
    final url = j[PlaylistWire.playAll];
    return PlaylistPlayAll(url is String && url.isNotEmpty ? url : null);
  }
}
