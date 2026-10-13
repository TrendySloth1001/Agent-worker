import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../assist/assistant_setup.dart';
import '../../core/app_scope.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/assist.dart';
import '../../core/constants/onboarding.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/dot_matrix_backdrop.dart';
import '../../core/widgets/illustration.dart';
import '../auth/auth_controller.dart';
import '../auth/widgets/auth_widgets.dart';
import '../chat/chat_launch.dart';
import '../settings/settings_controller.dart';
import '../settings/widgets/reply_style_cards.dart';
import 'onboarding_store.dart';
import 'widgets/tour_parts.dart';

/// The first-run tour: six short pages on what sparky does, an optional
/// "set as assistant" step and two quick personal picks.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.setup = const AssistantSetup(),
    this.showAssistantSetup,
  });

  /// Finished or skipped; the caller then shows a fresh chat.
  final Future<void> Function() onDone;

  final AssistantSetup setup;

  /// The "Set sparky as your assistant" card; defaults to Android only.
  final bool? showAssistantSetup;

  /// Settings → About → Take the tour: the same pages over the app, ending
  /// on a new chat.
  static Future<void> open(BuildContext context) {
    Haptics.tap();
    final navigator = Navigator.of(context);
    return navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingScreen(
          onDone: () async {
            final user = AuthController.instance.user;
            if (user != null) await OnboardingStore.instance.markDone(user);
            navigator.popUntil((r) => r.isFirst);
            ChatLaunch.instance.newChat();
          },
        ),
      ),
    );
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final _pages = PageController();
  final _name = TextEditingController();
  int _page = 0;
  bool _finishing = false;
  String _style = replyPresets.first.id;
  AssistantStatus? _assistant;
  bool _started = false;

  static const _last = OnboardingSizes.pages - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_showAssistant) _refreshAssistant();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final s = _settings;
    if (s == null) return;
    _name.text = s.name.trim().isNotEmpty ? s.name.trim() : _firstName;
    _style = (presetFor(s.tone, s.length) ?? replyPresets.first).id;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  // Back from the system's Default apps page: show the new state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _showAssistant) {
      _refreshAssistant();
    }
  }

  bool get _showAssistant =>
      widget.showAssistantSetup ?? AssistantSetup.supported;

  SettingsController? get _settings =>
      context.getInheritedWidgetOfExactType<AppScope>()?.settings;

  String get _firstName {
    final name = AuthController.instance.user?.name.trim() ?? '';
    final fallback = name.isNotEmpty ? name : (_settings?.name.trim() ?? '');
    return fallback.split(RegExp(r'\s+')).first;
  }

  Future<void> _refreshAssistant() async {
    final s = await widget.setup.status();
    if (mounted) setState(() => _assistant = s);
  }

  Future<void> _setAssistant() async {
    Haptics.tap();
    final result = await widget.setup.request();
    if (result == AssistSetupChannel.granted) Haptics.received();
    await _refreshAssistant();
  }

  void _go(int page) {
    final target = page.clamp(0, _last);
    if (target == _page) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(
        target,
        duration: OnboardingDurations.page,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onPage(int page) {
    Haptics.tap();
    FocusScope.of(context).unfocus();
    setState(() => _page = page);
  }

  Future<void> _skip() async {
    Haptics.tap();
    await _finish(save: false);
  }

  Future<void> _finish({bool save = true}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final s = _settings;
    if (save && s != null) {
      Haptics.received();
      final name = _name.text.trim();
      if (name.isNotEmpty) s.setName(name);
      final preset = replyPresets.firstWhere((p) => p.id == _style);
      s.applyReplyStyle(preset.tone, preset.length);
    }
    await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
      // Back steps through the pages; on the first one it leaves as usual.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_page - 1);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemOverlayFor(context),
        child: Scaffold(
          backgroundColor: p.background,
          body: Stack(
            children: [
              const Positioned.fill(child: DotMatrixBackdrop.page()),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      onSkip: _page == _last || _finishing ? null : _skip,
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pages,
                        onPageChanged: _onPage,
                        children: _buildPages(),
                      ),
                    ),
                    _BottomBar(
                      page: _page,
                      busy: _finishing,
                      onDot: _go,
                      onBack: () {
                        Haptics.tap();
                        _go(_page - 1);
                      },
                      onNext: _page == _last ? _finish : () => _go(_page + 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPages() => [
    TourPage(
      index: 0,
      art: IllustrationKind.hello,
      hero: true,
      kicker: OnboardingStrings.welcomeKicker,
      title: OnboardingStrings.hello(_firstName),
      body: OnboardingStrings.welcomeBody,
      children: [
        const _Tags(),
        const SizedBox(height: AppSpacing.lg),
        Text(OnboardingStrings.welcomeNote, style: context.text.bodySmall),
      ],
    ),
    const TourPage(
      index: 1,
      art: IllustrationKind.homeChat,
      kicker: OnboardingStrings.askKicker,
      title: OnboardingStrings.askTitle,
      body: OnboardingStrings.askBody,
      children: [TourPoints(OnboardingStrings.askPoints)],
    ),
    const TourPage(
      index: 2,
      art: IllustrationKind.homeRead,
      kicker: OnboardingStrings.knowKicker,
      title: OnboardingStrings.knowTitle,
      body: OnboardingStrings.knowBody,
      children: [TourPoints(OnboardingStrings.knowPoints)],
    ),
    TourPage(
      index: 3,
      art: IllustrationKind.github,
      kicker: OnboardingStrings.appsKicker,
      title: OnboardingStrings.appsTitle,
      body: OnboardingStrings.appsBody,
      children: [
        const TourPoints(OnboardingStrings.appsPoints),
        const SizedBox(height: AppSpacing.md),
        Text(
          OnboardingStrings.appsNote,
          textAlign: TextAlign.center,
          style: context.text.bodySmall,
        ),
      ],
    ),
    TourPage(
      index: 4,
      art: IllustrationKind.homeDream,
      kicker: OnboardingStrings.assistKicker,
      title: OnboardingStrings.assistTitle,
      body: OnboardingStrings.assistBody,
      children: [
        const TourPoints(OnboardingStrings.assistPoints),
        if (_showAssistant) ...[
          const SizedBox(height: AppSpacing.lg),
          _AssistantCta(status: _assistant, onSet: _setAssistant),
        ],
      ],
    ),
    TourPage(
      index: 5,
      art: IllustrationKind.homeCoffee,
      kicker: OnboardingStrings.yoursKicker,
      title: OnboardingStrings.yoursTitle,
      body: OnboardingStrings.yoursBody,
      children: [
        _Personalize(
          name: _name,
          style: _style,
          onStyle: (id) => setState(() => _style = id),
          onSubmitted: _finish,
        ),
      ],
    ),
  ];
}

/// Wordmark on the left, Skip on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSkip});

  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.appBarHeight,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.xl,
          right: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Wordmark(size: AppFontSize.title, compact: true),
            const Spacer(),
            AnimatedOpacity(
              opacity: onSkip == null ? 0 : 1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppDurations.normal,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.textSecondary,
                ),
                onPressed: onSkip,
                child: const Text(OnboardingStrings.skip),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glyph dots over Back / Next (Start chatting on the last page).
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.page,
    required this.busy,
    required this.onDot,
    required this.onBack,
    required this.onNext,
  });

  final int page;
  final bool busy;
  final ValueChanged<int> onDot;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final last = page == OnboardingSizes.pages - 1;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: OnboardingSizes.maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TourDots(page: page, count: OnboardingSizes.pages, onTap: onDot),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  AnimatedSize(
                    duration: reduce ? Duration.zero : AppDurations.normal,
                    curve: Curves.easeOutCubic,
                    child: page == 0
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.md,
                            ),
                            child: SizedBox(
                              height: AppSizes.buttonHeight,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: p.textPrimary,
                                  side: BorderSide(color: p.borderStrong),
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: busy ? null : onBack,
                                child: const Text(OnboardingStrings.back),
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: PillButton(
                      label: last
                          ? OnboardingStrings.start
                          : OnboardingStrings.next,
                      loading: busy,
                      onPressed: () {
                        Haptics.tap();
                        onNext();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The welcome page's feature tags.
class _Tags extends StatelessWidget {
  const _Tags();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final tag in OnboardingStrings.welcomeTags)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs + AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: p.borderStrong),
            ),
            child: Text(
              tag,
              style: context.text.caption.copyWith(color: p.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// "Set sparky as your assistant", or a check once it is.
class _AssistantCta extends StatelessWidget {
  const _AssistantCta({required this.status, required this.onSet});

  final AssistantStatus? status;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final done = status?.isDefault ?? false;
    if (done) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(OnboardingIcons.check, size: AppIconSize.md, color: p.accent),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(OnboardingStrings.assistDone, style: context.text.body),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: AppSizes.buttonHeight,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: onSet,
            icon: const AppIcon(
              OnboardingIcons.assistant,
              size: AppIconSize.md,
            ),
            label: const Text(OnboardingStrings.assistCta),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          OnboardingStrings.assistLater,
          textAlign: TextAlign.center,
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

/// Name to call you and a reply style.
class _Personalize extends StatelessWidget {
  const _Personalize({
    required this.name,
    required this.style,
    required this.onStyle,
    required this.onSubmitted,
  });

  final TextEditingController name;
  final String style;
  final ValueChanged<String> onStyle;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final preset = replyPresets.firstWhere((x) => x.id == style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthField(
          label: OnboardingStrings.nameLabel,
          hint: OnboardingStrings.nameHint,
          controller: name,
          icon: OnboardingIcons.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
        ),
        Text(
          OnboardingStrings.styleLabel,
          style: Theme.of(
            context,
          ).textTheme.labelLarge!.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final x in replyPresets)
              TourChoice(
                label: x.title,
                selected: x.id == style,
                onTap: () => onStyle(x.id),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          preset.sample,
          style: context.text.bodySmall.copyWith(
            fontStyle: FontStyle.italic,
            color: p.textSecondary,
          ),
        ),
      ],
    );
  }
}
