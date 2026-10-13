import 'package:hugeicons/hugeicons.dart';

/// Device actions the model proposes (backend src/context/deviceActions.ts)
/// and the phone runs after Confirm (DeviceActions.kt).
abstract final class DeviceActionWire {
  /// The fenced block language of a proposed action.
  static const fence = 'sparky-action';

  /// The `deviceActions` object of POST /chat.
  static const request = 'deviceActions';
  static const localTime = 'localTime';
  static const installedApps = 'installedApps';

  /// Channel to DeviceActions.kt (both engines).
  static const channel = 'app/actions';
  static const run = 'run';

  // Model JSON keys
  static const type = 'type';
  static const time = 'time';
  static const label = 'label';
  static const seconds = 'seconds';
  static const text = 'text';
  static const at = 'at';
  static const title = 'title';
  static const start = 'start';
  static const end = 'end';
  static const allDay = 'allDay';
  static const location = 'location';
  static const notes = 'notes';
  static const name = 'name';
  static const url = 'url';
  static const number = 'number';
  static const body = 'body';
  static const to = 'to';
  static const subject = 'subject';
  static const destination = 'destination';
  static const travel = 'travel';

  /// url / app actions: the app the link opens in and its Android package.
  static const app = 'app';
  static const package = 'package';

  /// url action: open this package's store page (`market://` first).
  static const store = 'store';

  /// url action, rich card only (never sent to Kotlin): who made the item,
  /// its cover image and the site name ([title] is the item's name).
  static const subtitle = 'subtitle';
  static const image = 'image';
  static const site = 'site';

  // Channel keys that differ from the model's (normalised in Dart)
  static const hour = 'hour';
  static const minute = 'minute';
  static const beginMs = 'beginMs';
  static const endMs = 'endMs';

  // Results from Kotlin
  static const ok = 'ok';
  static const notFound = 'not_found';
  static const unavailable = 'unavailable';
}

abstract final class DeviceActionStrings {
  static const confirm = 'Confirm';
  static const cancel = 'Cancel';
  static const running = 'Working…';
  static const cancelled = 'Cancelled';
  static const failed = 'That did not work on this phone.';
  static const unavailable = 'No app on this phone can do that.';
  static const notFound = 'No app with that name is installed.';
  static const notifyOff =
      'Notifications are off for sparky. Turn them on to get reminders.';
  static const off = 'Actions are off. Turn them on in Settings > Assistant.';
  static const notHere = 'Actions run on the Android app.';

  /// The card's name while the answer streams ("PREPARING ACTION…").
  static const cardLabel = 'ACTION';

  // Card kicker (Space Mono caps) per type
  static const alarm = 'ALARM';
  static const timer = 'TIMER';
  static const reminder = 'REMINDER';
  static const event = 'CALENDAR';
  static const app = 'OPEN APP';
  static const url = 'OPEN LINK';
  static const dial = 'CALL';
  static const sms = 'TEXT MESSAGE';
  static const email = 'EMAIL';
  static const whatsapp = 'WHATSAPP';
  static const share = 'SHARE';
  static const navigate = 'DIRECTIONS';

  // Titles
  static String alarmTitle(String time) => 'Set an alarm for $time';
  static String timerTitle(String length) => 'Start a $length timer';
  static const reminderTitle = 'Remind me';
  static String appTitle(String name) => 'Open $name';
  static const urlTitle = 'Open this page';
  static String dialTitle(String number) => 'Call $number';
  static const dialHint = 'Opens the dialer. You place the call.';
  static const smsTitle = 'Write a text';
  static const emailTitle = 'Write an email';
  static const whatsappTitle = 'Write on WhatsApp';
  static const shareTitle = 'Share text';
  static String navigateTitle(String place) => 'Directions to $place';
  static const sendHint = 'Opens the app with this filled in. You press send.';

  // Detail labels
  static const labelLabel = 'Label';
  static const whenLabel = 'When';
  static const startLabel = 'Starts';
  static const endLabel = 'Ends';
  static const allDayValue = 'All day';
  static const whereLabel = 'Where';
  static const notesLabel = 'Notes';
  static const toLabel = 'To';
  static const subjectLabel = 'Subject';
  static const messageLabel = 'Message';
  static const linkLabel = 'Link';
  static const travelLabel = 'By';

  // Done
  static const alarmDone = 'Alarm set';
  static const timerDone = 'Timer started';
  static const reminderDone = 'Reminder set';
  static const opened = 'Opened';

  static String duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final parts = [
      if (h > 0) '$h h',
      if (m > 0) '$m min',
      if (s > 0 && h == 0) '$s s',
    ];
    return parts.isEmpty ? '0 s' : parts.join(' ');
  }
}

/// Day and month names for the card (the app has no intl dependency).
abstract final class DeviceActionDates {
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

abstract final class DeviceActionSizes {
  static const iconCircle = 36.0;
  static const labelWidth = 72.0;
  static const buttonHeight = 40.0;
  static const maxDetailLines = 4;

  /// Recent card outcomes kept so a card scrolled away and back keeps its state.
  static const rememberedOutcomes = 64;

  /// Longest timer the card accepts (24 h).
  static const maxTimerSeconds = 24 * 3600;

  /// Installed media apps are asked again after this long.
  static const installedFresh = Duration(minutes: 2);
}

abstract final class DeviceActionIcons {
  static const alarm = HugeIcons.strokeRoundedAlarmClock;
  static const timer = HugeIcons.strokeRoundedTimer02;
  static const reminder = HugeIcons.strokeRoundedNotification03;
  static const event = HugeIcons.strokeRoundedCalendar03;
  static const app = HugeIcons.strokeRoundedDashboardSquare01;
  static const url = HugeIcons.strokeRoundedLink01;
  static const dial = HugeIcons.strokeRoundedCall;
  static const sms = HugeIcons.strokeRoundedMessage01;
  static const email = HugeIcons.strokeRoundedMail01;
  static const whatsapp = HugeIcons.strokeRoundedWhatsapp;
  static const share = HugeIcons.strokeRoundedShare08;
  static const navigate = HugeIcons.strokeRoundedNavigation03;
  static const done = HugeIcons.strokeRoundedTick02;
  static const cancelled = HugeIcons.strokeRoundedCancel01;
  static const failed = HugeIcons.strokeRoundedAlertCircle;
}
