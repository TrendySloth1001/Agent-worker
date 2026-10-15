import 'package:hugeicons/hugeicons.dart';

/// Approximate location (Settings → Privacy): the phone sends coarse hints
/// that need no permission, the server works out a rough city / country only
/// for questions that need it. Nothing here asks for the location permission.

abstract final class LocationConfig {
  /// Native channel ([PhoneHintsHandler] in Kotlin).
  static const channel = 'app/phone_hints';
  static const hintsMethod = 'hints';

  /// Keys of the hints map, shared with the server's `locationHints`.
  static const simCountry = 'simCountry';
  static const networkCountry = 'networkCountry';
  static const timeZone = 'timeZone';
  static const locale = 'locale';

  /// The phone answers in milliseconds; past this the request goes without.
  static const readTimeout = Duration(milliseconds: 400);
}

abstract final class LocationStrings {
  static const section = 'Location';
  static const approxTitle = 'Use approximate location';
  static const approxHelp =
      'For weather, nearby places and local prices, sparky may use your '
      'country and rough city, guessed from your network and phone settings '
      '(never GPS). Nothing is saved.';
  static const approxKeywords =
      'location city country weather near me nearby gps network sim '
      'approximate';
  static const cityLabel = 'My city';
  static const cityHint = 'Optional. Used instead of the guess';
  static const cityKeywords = 'my city town location override home place';
}

abstract final class LocationIcons {
  static const approx = HugeIcons.strokeRoundedMapsLocation01;
  static const city = HugeIcons.strokeRoundedCity01;
}
