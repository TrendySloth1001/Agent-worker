import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/device_actions.dart';
import '../../core/constants/media_apps.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/chat_event.dart';
import 'device_action.dart';
import 'device_action_runner.dart';

/// "Open in YouTube Music" chips under an answer whose sources link to a
/// known media, shopping or maps app (chat and overlay). A tap opens the
/// link straight away (no model round trip, no confirm: the user chose the
/// link): in the app when it is installed, else in the browser. An app the
/// answer already has an action card for (a ```sparky-action "Open in
/// YouTube Music") gets no chip: the card is that button.
class OpenInChips extends StatefulWidget {
  const OpenInChips({
    super.key,
    required this.citations,
    this.content = '',
    this.runner,
  });

  final List<Citation> citations;

  /// The answer's text, for its action cards' apps.
  final String content;

  /// Defaults to [DeviceActionRunner.instance].
  final DeviceActionRunner? runner;

  /// The links worth a chip, or none (then the widget draws nothing): one
  /// per app, minus apps an action card in [content] already opens.
  static List<(MediaApp, String)> linksOf(
    List<Citation> citations, {
    String content = '',
  }) {
    final links = MediaApps.openLinks(citations.map((c) => c.url));
    if (links.isEmpty) return links;
    final carded = cardApps(content);
    if (carded.isEmpty) return links;
    return [
      for (final l in links)
        if (!carded.contains(l.$1)) l,
    ];
  }

  static final _actionBlock = RegExp(
    '```${RegExp.escape(DeviceActionWire.fence)}[^\\n]*\\n([\\s\\S]*?)```',
  );

  /// The apps the action cards (```sparky-action blocks) in [content] open.
  static Set<MediaApp> cardApps(String content) {
    if (!content.contains(DeviceActionWire.fence)) return const {};
    return {
      for (final m in _actionBlock.allMatches(content))
        ?DeviceAction.parse(m.group(1)!)?.mediaApp,
    };
  }

  /// The chips to draw once [installed] is known (empty: not yet): installed
  /// apps first, no "{app} in browser" when an installed app of the same
  /// kind is offered, at most [MediaAppSizes.shownChips].
  static List<(MediaApp, String)> visible(
    List<(MediaApp, String)> links,
    Map<String, bool> installed,
  ) {
    if (installed.isEmpty) return links;
    bool has(MediaApp a) => installed[a.package] ?? false;
    final kinds = {
      for (final (app, _) in links)
        if (has(app)) app.category,
    };
    return [
      for (final l in links)
        if (has(l.$1)) l,
      for (final l in links)
        if (!has(l.$1) && !kinds.contains(l.$1.category)) l,
    ].take(MediaAppSizes.shownChips).toList();
  }

  @override
  State<OpenInChips> createState() => _OpenInChipsState();
}

class _OpenInChipsState extends State<OpenInChips> {
  late List<(MediaApp, String)> _links = _linksOf(widget);

  static List<(MediaApp, String)> _linksOf(OpenInChips w) =>
      OpenInChips.linksOf(w.citations, content: w.content);

  /// Installed apps by package; empty until the phone answered.
  Map<String, bool> _installed = const {};

  DeviceActionRunner get _runner =>
      widget.runner ?? DeviceActionRunner.instance;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(OpenInChips old) {
    super.didUpdateWidget(old);
    if (old.citations != widget.citations || old.content != widget.content) {
      _links = _linksOf(widget);
      _check();
    }
  }

  Future<void> _check() async {
    if (_links.isEmpty || !DeviceActionRunner.supported) return;
    final r = await _runner.appAvailability([
      for (final (app, _) in _links) app.package,
    ]);
    if (mounted) setState(() => _installed = r);
  }

  Future<void> _open(MediaApp app, String url) async {
    Haptics.tap();
    final inApp = _installed[app.package] ?? false;
    final outcome = await _runner.run(
      DeviceAction.link(url, app: inApp ? app : null),
    );
    if (outcome != ActionOutcome.done) Haptics.error();
  }

  @override
  Widget build(BuildContext context) {
    if (_links.isEmpty || !DeviceActionRunner.supported) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final (app, url) in OpenInChips.visible(_links, _installed))
          _OpenChip(
            app: app,
            // Not installed (once known): the page opens in the browser.
            label: _installed[app.package] == false
                ? MediaAppStrings.inBrowser(app.label)
                : MediaAppStrings.openIn(app.label),
            onTap: () => _open(app, url),
          ),
      ],
    );
  }
}

class _OpenChip extends StatelessWidget {
  const _OpenChip({
    required this.app,
    required this.label,
    required this.onTap,
  });

  final MediaApp app;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: MediaAppSizes.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: p.borderStrong, width: AppBorder.thin),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                app.logo,
                size: MediaAppSizes.chipLogo,
                color: p.textPrimary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
