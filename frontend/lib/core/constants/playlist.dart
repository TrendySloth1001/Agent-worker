import 'app_icons.dart';

/// The ```sparky-playlist card (backend src/context/playlist.ts): several
/// suggested songs with covers, 30 s previews, "open in app" and Play all.
abstract final class PlaylistWire {
  /// The fenced block language.
  static const fence = 'sparky-playlist';

  /// Backend routes (under the API base URL).
  static const enrichPath = '/playlist/enrich';
  static const youtubePath = '/playlist/youtube';

  // Request / response keys
  static const items = 'items';
  static const title = 'title';
  static const artist = 'artist';
  static const tracks = 'tracks';
  static const art = 'art';
  static const durationMs = 'durationMs';
  static const previewUrl = 'previewUrl';
  static const album = 'album';
  static const year = 'year';
  static const link = 'link';
  static const ids = 'ids';
  static const playAll = 'playAll';

  /// Music apps by preference (MediaApps keys) when the user named none:
  /// the first one installed opens each song.
  static const appOrder = [
    'youtube_music',
    'spotify',
    'jiosaavn',
    'gaana',
    'apple_music',
    'youtube',
  ];

  // Block keys
  static const titleKey = 'title:';
  static const appKey = 'app:';
}

abstract final class PlaylistStrings {
  static const label = 'PLAYLIST';
  static const untitled = 'Playlist';
  static const playAll = 'Play all';
  static const copyAll = 'COPY LIST';
  static const copied = 'COPIED';
  static String count(int n) => n == 1 ? '1 SONG' : '$n SONGS';
  static String minutes(int m) => '$m MIN';
  static String header(int n, int minutes) => minutes > 0
      ? '${count(n)} · ${PlaylistStrings.minutes(minutes)}'
      : count(n);
  static String copyLine(String title, String artist) =>
      artist.isEmpty ? title : '$title — $artist';

  // Accessibility
  static String preview(String title) => 'Play 30 second preview of $title';
  static String stopPreview(String title) => 'Stop preview of $title';
  static String loadingPreview(String title) => 'Loading preview of $title';
  static String openIn(String app, String title) => 'Open $title in $app';
  static String row(String title, String artist, String duration) => [
    title,
    if (artist.isNotEmpty) artist,
    if (duration.isNotEmpty) duration,
  ].join(', ');
  static const rowHint = 'Long press to copy';
  static String playAllIn(String app) => 'Play all songs in $app';
}

abstract final class PlaylistSizes {
  /// Songs per card (the server caps lookups at the same number).
  static const maxSongs = 12;

  static const pad = 12.0;
  static const rowHeight = 60.0;
  static const cover = 44.0;
  static const coverRadius = 8.0;
  static const coverIcon = 20.0;
  static const previewButton = 36.0;
  static const previewIcon = 16.0;
  static const ringStroke = 2.0;
  static const openButton = 36.0;
  static const openLogo = 20.0;
  static const durationWidth = 36.0;
  static const playAllHeight = 36.0;
  static const playAllLogo = 16.0;
  static const headerGap = 2.0;
  static const skeletonAlpha = 0.5;

  /// Preview position is reported at this granularity (ring smoothness).
  static const tickMs = 200;
}

abstract final class PlaylistIcons {
  static const play = AppIcons.playPlain;
  static const pause = AppIcons.pause;
  static const music = AppIcons.audio;
  static const playAll = AppIcons.play;
}
