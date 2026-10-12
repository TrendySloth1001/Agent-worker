import 'dart:math' as math;

/// The message over a new chat: one is picked at random each time an empty
/// chat opens (app start, new chat), never the same one twice in a row.
typedef Greeting = ({String title, String subtitle});

abstract final class Greetings {
  static final _random = math.Random();
  static String? _last;

  /// Pins the greeting (tests, screenshots).
  static Greeting? debugFixed;

  // Hours (local time) where each part of the day starts.
  static const morningFrom = 5;
  static const afternoonFrom = 12;
  static const eveningFrom = 17;
  static const nightFrom = 22;

  static String _forTime(int hour) {
    if (hour >= morningFrom && hour < afternoonFrom) return 'Good morning';
    if (hour >= afternoonFrom && hour < eveningFrom) return 'Good afternoon';
    if (hour >= eveningFrom && hour < nightFrom) return 'Good evening';
    return 'Up late?';
  }

  static List<Greeting> _all(String? name, int hour) {
    final n = (name ?? '').trim().split(RegExp(r'\s+')).first;
    final hi = n.isEmpty ? '' : ', $n';
    final timely = _forTime(hour);
    return [
      (
        title: timely.endsWith('?') ? timely : '$timely$hi',
        subtitle: 'What are we working on?',
      ),
      (
        title: n.isEmpty ? 'Hey there' : 'Hey $n',
        subtitle: "What's on your mind?",
      ),
      (
        title: 'Ask me anything',
        subtitle: 'Code, ideas, plans, or just curious.',
      ),
      (title: 'Ready when you are', subtitle: 'Start a conversation.'),
      (title: "Let's build", subtitle: 'Bring a bug, an idea or a repo.'),
      (title: 'Curious today?', subtitle: 'Ask, explore, or think out loud.'),
      (title: 'Fresh page', subtitle: 'Where should we start?'),
      (title: 'Hello', subtitle: 'Start a conversation.'),
    ];
  }

  /// A random greeting for [name] at [now], different from the last pick.
  static Greeting pick({String? name, DateTime? now}) {
    final fixed = debugFixed;
    if (fixed != null) return fixed;
    final all = _all(name, (now ?? DateTime.now()).hour);
    final options = all.where((g) => g.title != _last).toList();
    final g = options[_random.nextInt(options.length)];
    _last = g.title;
    return g;
  }
}
