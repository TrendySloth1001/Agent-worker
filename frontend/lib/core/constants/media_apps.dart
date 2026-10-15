import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'brand_logos.dart';

/// A media, shopping or maps app whose links the phone can open in the app
/// itself ("Open in YouTube Music"). Mirrors MEDIA_APPS in the backend's
/// `src/context/openIntent.ts`; the package is what Android opens the link
/// with when the app is installed (`<queries>` in AndroidManifest.xml).
/// What kind of app it is: "play it in my music app" picks one of the kind.
enum MediaCategory { music, video, shopping, maps }

class MediaApp {
  const MediaApp({
    required this.key,
    required this.category,
    required this.label,
    required this.package,
    required this.hosts,
    required this.logo,
    this.searchTemplate = '',
  });

  /// The backend's MEDIA_APPS key ("youtube_music"): sent as installedApps.
  final String key;

  final MediaCategory category;

  /// "YouTube Music": the chip and card say "Open in {label}".
  final String label;

  /// Android package, e.g. `com.google.android.apps.youtube.music`.
  final String package;

  /// Hosts of its links; an entry with a slash also matches the path
  /// (`google.com/maps`).
  final List<String> hosts;

  /// The real logo ([BrandLogos]).
  final AppIconData logo;

  /// The app's search page with `{q}` for the query (mirrors `search` in the
  /// backend's MEDIA_APPS); empty when the app has none here.
  final String searchTemplate;

  /// The app's search page for [query] (what a song's "open in app" opens).
  String searchUrl(String query) =>
      searchTemplate.replaceFirst('{q}', Uri.encodeComponent(query));

  /// Whether [url] is one of this app's links (not just its home page).
  bool owns(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !(u.scheme == 'https' || u.scheme == 'http')) {
      return false;
    }
    final host = u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final full = '$host${u.path}';
    final onHost = hosts.any(
      (h) => h.contains('/')
          ? full.startsWith(h)
          : host == h || host.endsWith('.$h'),
    );
    if (!onHost) return false;
    final rest = u.path.replaceAll('/', '');
    return rest.isNotEmpty || u.query.isNotEmpty;
  }
}

abstract final class MediaApps {
  static const youtubeMusic = MediaApp(
    key: 'youtube_music',
    category: MediaCategory.music,
    label: 'YouTube Music',
    package: 'com.google.android.apps.youtube.music',
    hosts: ['music.youtube.com'],
    logo: BrandLogos.youtubeMusic,
    searchTemplate: 'https://music.youtube.com/search?q={q}',
  );
  static const youtube = MediaApp(
    key: 'youtube',
    category: MediaCategory.video,
    label: 'YouTube',
    package: 'com.google.android.youtube',
    hosts: ['youtube.com', 'youtu.be'],
    logo: BrandLogos.youtube,
    searchTemplate: 'https://www.youtube.com/results?search_query={q}',
  );
  static const spotify = MediaApp(
    key: 'spotify',
    category: MediaCategory.music,
    label: 'Spotify',
    package: 'com.spotify.music',
    hosts: ['open.spotify.com'],
    logo: BrandLogos.spotify,
    searchTemplate: 'https://open.spotify.com/search/{q}',
  );
  static const jiosaavn = MediaApp(
    key: 'jiosaavn',
    category: MediaCategory.music,
    label: 'JioSaavn',
    package: 'com.jio.media.jiobeats',
    hosts: ['jiosaavn.com'],
    logo: BrandLogos.jiosaavn,
    searchTemplate: 'https://www.jiosaavn.com/search/{q}',
  );
  static const gaana = MediaApp(
    key: 'gaana',
    category: MediaCategory.music,
    label: 'Gaana',
    package: 'com.gaana',
    hosts: ['gaana.com'],
    logo: BrandLogos.gaana,
    searchTemplate: 'https://gaana.com/search/{q}',
  );
  static const appleMusic = MediaApp(
    key: 'apple_music',
    category: MediaCategory.music,
    label: 'Apple Music',
    package: 'com.apple.android.music',
    hosts: ['music.apple.com'],
    logo: BrandLogos.appleMusic,
    searchTemplate: 'https://music.apple.com/search?term={q}',
  );
  static const amazon = MediaApp(
    key: 'amazon',
    category: MediaCategory.shopping,
    label: 'Amazon',
    package: 'in.amazon.mShop.android.shopping',
    hosts: ['amazon.in', 'amazon.com', 'amazon.co.uk', 'amzn.in', 'amzn.to'],
    logo: BrandLogos.amazon,
  );
  static const flipkart = MediaApp(
    key: 'flipkart',
    category: MediaCategory.shopping,
    label: 'Flipkart',
    package: 'com.flipkart.android',
    hosts: ['flipkart.com'],
    logo: BrandLogos.flipkart,
  );
  static const maps = MediaApp(
    key: 'maps',
    category: MediaCategory.maps,
    label: 'Google Maps',
    package: 'com.google.android.apps.maps',
    hosts: [
      'google.com/maps',
      'maps.google.com',
      'maps.app.goo.gl',
      'goo.gl/maps',
    ],
    logo: BrandLogos.googleMaps,
  );

  /// YouTube Music before YouTube: its host is a subdomain of YouTube's.
  static const all = [
    youtubeMusic,
    youtube,
    spotify,
    jiosaavn,
    gaana,
    appleMusic,
    amazon,
    flipkart,
    maps,
  ];

  static MediaApp? forPackage(String? package) => package == null
      ? null
      : all.where((a) => a.package == package).firstOrNull;

  static MediaApp? forUrl(String url) =>
      all.where((a) => a.owns(url)).firstOrNull;

  /// By the name the model wrote ("YouTube Music", "spotify").
  static MediaApp? forName(String? name) {
    final n = name?.trim().toLowerCase();
    if (n == null || n.isEmpty) return null;
    return all.where((a) => a.label.toLowerCase() == n).firstOrNull;
  }

  /// One link per app among [urls] (first wins), in the order found, at
  /// most [MediaAppSizes.maxChips]: the "Open in {app}" chips of an answer.
  static List<(MediaApp, String)> openLinks(Iterable<String> urls) {
    final out = <(MediaApp, String)>[];
    for (final url in urls) {
      final app = forUrl(url);
      if (app == null || out.any((e) => e.$1 == app)) continue;
      out.add((app, url));
      if (out.length >= MediaAppSizes.maxChips) break;
    }
    return out;
  }
}

/// The `app/actions` channel's app checks and store links.
abstract final class MediaAppWire {
  static const availability = 'appAvailability';
  static const packages = 'packages';

  /// The Play Store page of an app (Kotlin tries `market://` first).
  static String storePage(String package) =>
      'https://play.google.com/store/apps/details?id=$package';

  /// A YouTube video's thumbnail (the card's cover when none was sent).
  static String youtubeThumb(String id) =>
      'https://${MediaAppSizes.youtubeThumbHost}/vi/$id/hqdefault.jpg';

  /// The video id of a youtube.com / music.youtube.com / youtu.be link,
  /// including live streams (`watch?v=` or `/live/<id>`) and embeds.
  static final youtubeId = RegExp(
    r'(?:[?&]v=|youtu\.be\/|\/shorts\/|\/embed\/|\/live\/)([\w-]{6,})',
  );
}

abstract final class MediaAppStrings {
  static const kicker = 'OPEN IN APP';
  static String openIn(String app) => 'Open in $app';
  static const open = 'Open';
  static const openInBrowser = 'Open in browser';
  static const getApp = 'Get the app';
  static String inBrowser(String app) => '$app in browser';
  static String notInstalled(String app) =>
      '$app is not installed. Open it in the browser or get the app.';
  static String appNotInstalled(String app) => '$app is not installed.';
}

abstract final class MediaAppSizes {
  /// "Open in {app}" chips under one answer.
  static const maxChips = 3;

  /// "Open in {app}" chips shown once the phone said which apps it has.
  static const shownChips = 2;
  static const chipHeight = 32.0;
  static const chipLogo = 16.0;
  static const cardLogo = 22.0;

  /// Rich link card: the cover (or the app logo when there is none).
  static const cover = 72.0;
  static const coverLogo = 36.0;
  static const badgeLogo = 14.0;

  /// YouTube thumbnails (hqdefault) are 4:3 with black bars around the
  /// 16:9 picture: zoomed by this much, the bars fall outside the cover.
  static const youtubeZoom = 4 / 3;
  static const youtubeThumbHost = 'i.ytimg.com';
}

abstract final class MediaAppIcons {
  static const browser = HugeIcons.strokeRoundedGlobe02;
  static const store = HugeIcons.strokeRoundedDownload04;
}
