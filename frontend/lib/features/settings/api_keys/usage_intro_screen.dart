import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/api_keys.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/onboarding.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/system_chrome.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/dot_matrix_backdrop.dart';
import '../../../core/widgets/illustration.dart';
import '../../auth/widgets/auth_widgets.dart';
import '../../onboarding/widgets/tour_parts.dart';

/// The three-page intro to "Your usage", shown the first time the view opens
/// and again from "How it works". Pops when skipped, backed out or finished.
class UsageIntroScreen extends StatefulWidget {
  const UsageIntroScreen({super.key, this.providerIds = defaultProviders});

  /// Providers whose real logos page 1 shows (ids as the server names them).
  final List<String> providerIds;

  static const defaultProviders = ['groq', 'openrouter', 'nvidia', 'ollama'];

  static Future<void> open(BuildContext context, {List<String>? providers}) {
    Haptics.tap();
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => UsageIntroScreen(
          providerIds: providers ?? UsageIntroScreen.defaultProviders,
        ),
      ),
    );
  }

  @override
  State<UsageIntroScreen> createState() => _UsageIntroScreenState();
}

class _UsageIntroScreenState extends State<UsageIntroScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _last = UsageIntroStrings.pages - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
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

  void _close() {
    Haptics.tap();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
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
                    SizedBox(
                      height: AppSizes.appBarHeight,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: AnimatedOpacity(
                            opacity: _page == _last ? 0 : 1,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : AppDurations.normal,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: p.textSecondary,
                              ),
                              onPressed: _page == _last ? null : _close,
                              child: const Text(UsageIntroStrings.skip),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pages,
                        onPageChanged: (i) {
                          Haptics.tap();
                          setState(() => _page = i);
                        },
                        children: _buildPages(),
                      ),
                    ),
                    _bottom(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottom(BuildContext context) {
    final p = context.palette;
    final last = _page == _last;
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
              TourDots(page: _page, count: UsageIntroStrings.pages, onTap: _go),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  if (_page > 0) ...[
                    SizedBox(
                      height: AppSizes.buttonHeight,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.textPrimary,
                          side: BorderSide(color: p.borderStrong),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () {
                          Haptics.tap();
                          _go(_page - 1);
                        },
                        child: const Text(UsageIntroStrings.back),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: PillButton(
                      label: last
                          ? UsageIntroStrings.done
                          : UsageIntroStrings.next,
                      onPressed: () {
                        Haptics.tap();
                        last ? _close() : _go(_page + 1);
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

  List<Widget> _buildPages() => [
    TourPage(
      index: 0,
      total: UsageIntroStrings.pages,
      art: IllustrationKind.homeThink,
      kicker: UsageIntroStrings.analyticsKicker,
      title: UsageIntroStrings.analyticsTitle,
      body: UsageIntroStrings.analyticsBody,
      children: [_Logos(widget.providerIds)],
    ),
    const TourPage(
      index: 1,
      total: UsageIntroStrings.pages,
      art: IllustrationKind.homeRead,
      kicker: UsageIntroStrings.onlyYoursKicker,
      title: UsageIntroStrings.onlyYoursTitle,
      body: UsageIntroStrings.onlyYoursBody,
      children: [TourPoints(UsageIntroStrings.onlyYoursPoints)],
    ),
    const TourPage(
      index: 2,
      total: UsageIntroStrings.pages,
      art: IllustrationKind.homeCode,
      kicker: UsageIntroStrings.workKicker,
      title: UsageIntroStrings.workTitle,
      body: UsageIntroStrings.workBody,
      children: [TourPoints(UsageIntroStrings.workPoints)],
    ),
  ];
}

/// The real provider logos, in a row.
class _Logos extends StatelessWidget {
  const _Logos(this.ids);

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      children: [
        for (final id in ids)
          Container(
            width: ApiKeysSizes.introLogoBox,
            height: ApiKeysSizes.introLogoBox,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: p.borderStrong),
            ),
            child: Center(
              child: AppIcon(
                ApiKeysIcons.provider(id),
                size: AppIconSize.lg,
                color: p.textPrimary,
              ),
            ),
          ),
      ],
    );
  }
}
