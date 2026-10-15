import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/intent_cards.dart';
import 'intent_card_model.dart';

/// How a tapped button went.
enum IntentOutcome { done, unavailable, failed }

/// The phone side of an action card: the `sparky/intents` channel
/// (CardIntents.kt). Called only from a button tap.
abstract class IntentRunner {
  /// The runner cards use; tests swap in a fake or a mock channel.
  static IntentRunner instance = ChannelIntentRunner();

  Future<IntentOutcome> run(CardIntent intent);

  /// Which of [packages] are installed (unknown counts as not installed).
  Future<Set<String>> installed(List<String> packages);
}

class ChannelIntentRunner implements IntentRunner {
  ChannelIntentRunner({
    MethodChannel channel = const MethodChannel(IntentCardWire.channel),
    Future<bool> Function(Uri)? openLink,
  }) : _channel = channel,
       _openLink = openLink ?? _launch;

  final MethodChannel _channel;
  final Future<bool> Function(Uri) _openLink;

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<IntentOutcome> run(CardIntent intent) async {
    var outcome = IntentOutcome.failed;
    try {
      final r = await _channel.invokeMethod<String>(
        IntentCardWire.run,
        intent.toChannel(),
      );
      outcome = switch (r) {
        IntentCardWire.ok => IntentOutcome.done,
        IntentCardWire.unavailable => IntentOutcome.unavailable,
        _ => IntentOutcome.failed,
      };
    } on MissingPluginException {
      outcome = IntentOutcome.unavailable;
    } catch (_) {
      outcome = IntentOutcome.failed;
    }
    final fallback = intent.fallback;
    if (outcome == IntentOutcome.unavailable && fallback != null) {
      try {
        if (await _openLink(Uri.parse(fallback))) return IntentOutcome.done;
      } catch (_) {}
    }
    return outcome;
  }

  @override
  Future<Set<String>> installed(List<String> packages) async {
    if (packages.isEmpty) return const {};
    try {
      final r = await _channel.invokeMapMethod<String, bool>(
        IntentCardWire.installed,
        {IntentCardWire.packages: packages},
      );
      return {
        for (final p in packages)
          if (r?[p] ?? false) p,
      };
    } catch (_) {
      return const {};
    }
  }
}

/// Packages checked at most every [IntentCardSizes.installedFresh]; shared by
/// every card so a long chat asks the phone once.
abstract final class InstalledCardApps {
  static final Map<String, bool> _known = {};
  static DateTime? _at;

  @visibleForTesting
  static void reset() {
    _known.clear();
    _at = null;
  }

  static Future<Set<String>> check(
    List<String> packages, {
    IntentRunner? runner,
  }) async {
    final at = _at;
    final fresh =
        at != null &&
        DateTime.now().difference(at) < IntentCardSizes.installedFresh;
    if (!fresh || packages.any((p) => !_known.containsKey(p))) {
      final found = await (runner ?? IntentRunner.instance).installed(packages);
      if (!fresh) _known.clear();
      for (final p in packages) {
        _known[p] = found.contains(p);
      }
      _at = DateTime.now();
    }
    return {
      for (final p in packages)
        if (_known[p] ?? false) p,
    };
  }
}
