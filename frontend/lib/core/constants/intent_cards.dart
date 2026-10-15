import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'brand_logos.dart';

/// Action cards (backend src/context/cards.ts, cardLinks.ts): place, event,
/// alarm/timer, contact, product, ride, food, travel and UPI. The server
/// sends a finished card in a ```sparky-card block; each button is an intent
/// the phone runs only when the user taps it, through the `sparky/intents`
/// channel (CardIntents.kt). Both sides check the same allow-lists.
abstract final class IntentCardWire {
  /// The fenced block language.
  static const fence = 'sparky-card';

  /// Channel to CardIntents.kt.
  static const channel = 'sparky/intents';
  static const run = 'run';
  static const installed = 'installed';
  static const packages = 'packages';

  // Results from Kotlin
  static const ok = 'ok';
  static const unavailable = 'unavailable';

  // Card keys
  static const version = 'v';
  static const type = 'type';
  static const title = 'title';
  static const subtitle = 'subtitle';
  static const rows = 'rows';
  static const rowKey = 'k';
  static const rowValue = 'v';
  static const notice = 'notice';
  static const actions = 'actions';

  // Action keys
  static const id = 'id';
  static const label = 'label';
  static const app = 'app';
  static const primary = 'primary';
  static const chip = 'chip';
  static const group = 'group';
  static const appsGroup = 'apps';
  static const intent = 'intent';

  // Intent keys (also the channel's)
  static const action = 'action';
  static const uri = 'uri';
  static const package = 'package';
  static const fallback = 'fallback';
  static const chooser = 'chooser';
  static const extras = 'extras';

  // Event times: the server sends local "YYYY-MM-DDTHH:MM"; Kotlin gets ms.
  static const begin = 'begin';
  static const end = 'end';
  static const beginMs = 'beginMs';
  static const endMs = 'endMs';
}

/// What a button may do. Mirrors IntentAction in cardLinks.ts and the
/// allow-list in CardIntents.kt.
abstract final class IntentCardPolicy {
  static const uriSchemes = <String, List<String>>{
    'view': ['https', 'geo', 'google.navigation', 'upi'],
    'dial': ['tel'],
    'sendto': ['smsto', 'mailto'],
    'send': [],
    'set_alarm': [],
    'set_timer': [],
    'insert_event': [],
    'insert_contact': [],
    'launch': [],
  };

  static const extraKeys = <String, List<String>>{
    'view': [],
    'dial': [],
    'sendto': ['body', 'subject'],
    'send': ['text'],
    'set_alarm': ['hour', 'minutes', 'message'],
    'set_timer': ['length', 'message'],
    'insert_event': [
      'title',
      'begin',
      'end',
      'allDay',
      'location',
      'description',
    ],
    'insert_contact': ['name', 'phone', 'email'],
    'launch': [],
  };

  /// https hosts a card may link to.
  static const hosts = <String>{
    'www.google.com',
    'maps.google.com',
    'google.com',
    'play.google.com',
    'wa.me',
    'www.amazon.in',
    'amazon.in',
    'www.flipkart.com',
    'www.myntra.com',
    'www.swiggy.com',
    'www.zomato.com',
    'm.uber.com',
    'www.uber.com',
    'www.olacabs.com',
    'www.rapido.bike',
    'www.irctc.co.in',
    'www.ixigo.com',
    'www.makemytrip.com',
    'www.openstreetmap.org',
  };

  static final packagePattern = RegExp(
    r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$',
    caseSensitive: false,
  );

  static const maxActions = 8;
  static const maxRows = 6;
  static const maxText = 400;
}

/// The kinds of card and what each looks like.
enum IntentCardType {
  place('place', 'PLACE', _Glyphs.place),
  event('event', 'EVENT', _Glyphs.event),
  clock('clock', 'ALARM AND TIMER', _Glyphs.clock),
  contact('contact', 'CONTACT', _Glyphs.contact),
  product('product', 'PRODUCT', _Glyphs.product),
  ride('ride', 'RIDE', _Glyphs.ride),
  food('food', 'FOOD', _Glyphs.food),
  travel('travel', 'TRAVEL', _Glyphs.travel),
  upi('upi', 'PAY BY UPI', _Glyphs.upi);

  const IntentCardType(this.wire, this.kicker, this.icon);

  final String wire;
  final String kicker;
  final AppIconData icon;

  static IntentCardType? byWire(Object? raw) =>
      values.where((t) => t.wire == raw).firstOrNull;
}

abstract final class _Glyphs {
  static const place = HugeIcons.strokeRoundedLocation01;
  static const event = HugeIcons.strokeRoundedCalendar03;
  static const clock = HugeIcons.strokeRoundedAlarmClock;
  static const contact = HugeIcons.strokeRoundedUser;
  static const product = HugeIcons.strokeRoundedShoppingBag01;
  static const ride = HugeIcons.strokeRoundedCar01;
  static const food = HugeIcons.strokeRoundedRestaurant01;
  static const travel = HugeIcons.strokeRoundedAirplane01;
  static const upi = HugeIcons.strokeRoundedWallet01;
}

/// A button's app, named by the server (`app`): its real logo when the brand
/// set has one, else a plain glyph for the thing it does (never a made-up
/// logo).
abstract final class IntentCardIcons {
  static const _glyphs = <String, AppIconData>{
    'call': HugeIcons.strokeRoundedCall,
    'sms': HugeIcons.strokeRoundedMessage01,
    'whatsapp': HugeIcons.strokeRoundedWhatsapp,
    'share': HugeIcons.strokeRoundedShare08,
    'contact': HugeIcons.strokeRoundedUserAdd01,
    'alarm': HugeIcons.strokeRoundedAlarmClock,
    'timer': HugeIcons.strokeRoundedTimer02,
    'upi': HugeIcons.strokeRoundedWallet01,
    'google': HugeIcons.strokeRoundedGlobe02,
    'myntra': HugeIcons.strokeRoundedShoppingBag01,
    'swiggy': HugeIcons.strokeRoundedRestaurant01,
    'zomato': HugeIcons.strokeRoundedRestaurant01,
    'uber': HugeIcons.strokeRoundedCar01,
    'ola': HugeIcons.strokeRoundedCar01,
    'rapido': HugeIcons.strokeRoundedMotorbike01,
    'irctc': HugeIcons.strokeRoundedTrain01,
    'ixigo': HugeIcons.strokeRoundedTicket01,
    'makemytrip': HugeIcons.strokeRoundedAirplane01,
  };

  static const _logos = <String, AppIconData>{
    'maps': BrandLogos.googleMaps,
    'calendar': BrandLogos.googleCalendar,
    'amazon': BrandLogos.amazon,
    'flipkart': BrandLogos.flipkart,
  };

  static AppIconData forApp(String key) =>
      _logos[key] ?? _glyphs[key] ?? AppIcons.link;

  /// Whether [key] is drawn as the brand's real logo.
  static bool isLogo(String key) => _logos.containsKey(key);
}

abstract final class IntentCardStrings {
  static const failed = 'That did not work on this phone.';
  static const unavailable = 'No app on this phone can do that.';
  static const hint = 'Nothing happens until you tap a button.';
  static String button(String label, String card) => '$label, $card';
  static const notHere = 'Cards run on the Android app.';
}

abstract final class IntentCardSizes {
  static const iconCircle = 36.0;
  static const labelWidth = 64.0;
  static const buttonHeight = 40.0;
  static const chipHeight = 32.0;
  static const buttonLogo = 18.0;
  static const chipLogo = 16.0;
  static const maxRowLines = 3;

  /// Installed-app checks are repeated no sooner than this.
  static const installedFresh = Duration(minutes: 2);
}
