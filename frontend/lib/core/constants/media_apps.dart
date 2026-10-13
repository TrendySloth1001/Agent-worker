import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'brand_logos.dart';

/// A media, shopping or maps app whose links the phone can open in the app
/// itself ("Open in YouTube Music"). Mirrors MEDIA_APPS in the backend's
/// `src/context/openIntent.ts`; the package is what Android opens the link
/// with when the app is installed (`<queries>` in AndroidManifest.xml).
class MediaApp {
  const MediaApp({
    required this.label,
    required this.package,
    required this.hosts,
    required this.logo,
  });

  /// "YouTube Music": the chip and card say "Open in {label}".
  final String label;

  /// Android package, e.g. `com.google.android.apps.youtube.music`.
  final String package;

  /// Hosts of its links; an entry with a slash also matches the path
  /// (`google.com/maps`).
  final List<String> hosts;

  /// The real logo ([BrandLogos]).
  final AppIconData logo;

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
    label: 'YouTube Music',
    package: 'com.google.android.apps.youtube.music',
    hosts: ['music.youtube.com'],
    logo: BrandLogos.youtubeMusic,
  );
  static const youtube = MediaApp(
    label: 'YouTube',
    package: 'com.google.android.youtube',
    hosts: ['youtube.com', 'youtu.be'],
    logo: BrandLogos.youtube,
  );
  static const spotify = MediaApp(
    label: 'Spotify',
    package: 'com.spotify.music',
    hosts: ['open.spotify.com'],
    logo: BrandLogos.spotify,
  );
  static const jiosaavn = MediaApp(
    label: 'JioSaavn',
    package: 'com.jio.media.jiobeats',
    hosts: ['jiosaavn.com'],
    logo: BrandLogos.jiosaavn,
  );
  static const gaana = MediaApp(
    label: 'Gaana',
    package: 'com.gaana',
    hosts: ['gaana.com'],
    logo: BrandLogos.gaana,
  );
  static const appleMusic = MediaApp(
    label: 'Apple Music',
    package: 'com.apple.android.music',
    hosts: ['music.apple.com'],
    logo: BrandLogos.appleMusic,
  );
  static const amazon = MediaApp(
    label: 'Amazon',
    package: 'in.amazon.mShop.android.shopping',
    hosts: ['amazon.in', 'amazon.com', 'amazon.co.uk', 'amzn.in', 'amzn.to'],
    logo: BrandLogos.amazon,
  );
  static const flipkart = MediaApp(
    label: 'Flipkart',
    package: 'com.flipkart.android',
    hosts: ['flipkart.com'],
    logo: BrandLogos.flipkart,
  );
  static const maps = MediaApp(
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
  static const chipHeight = 32.0;
  static const chipLogo = 16.0;
  static const cardLogo = 22.0;
}

abstract final class MediaAppIcons {
  static const browser = HugeIcons.strokeRoundedGlobe02;
  static const store = HugeIcons.strokeRoundedDownload04;
}
