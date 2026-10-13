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

/// The three-page intro to "Your API keys", shown the first time the page
/// opens and again from "How it works". Pops `true` from the last page's
/// "Add a key" button and `false` when skipped or backed out.
class KeysIntroScreen extends StatefulWidget {
  const KeysIntroScreen({super.key, this.providerIds = defaultProviders});

  /// Providers whose real logos page 1 shows (ids as the server names them).
  final List<String> providerIds;

  static const defaultProviders = ['groq', 'openrouter', 'nvidia', 'ollama'];

  static Future<bool> open(
    BuildContext context, {
    List<String>? providers,
  }) async {
    Haptics.tap();
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => KeysIntroScreen(
          providerIds: providers ?? KeysIntroScreen.defaultProviders,
        ),
      ),
    );
    return added ?? false;
  }

  @override
  State<KeysIntroScreen> createState() => _KeysIntroScreenState();
}

class _KeysIntroScreenState extends State<KeysIntroScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _last = ApiKeysIntroStrings.pages - 1;

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

  void _close(bool addKey) {
    Haptics.tap();
    Navigator.of(context).pop(addKey);
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
                              onPressed: _page == _last
                                  ? null
                                  : () => _close(false),
                              child: const Text(ApiKeysIntroStrings.skip),
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
              TourDots(
                page: _page,
                count: ApiKeysIntroStrings.pages,
                onTap: _go,
              ),
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
                        child: const Text(ApiKeysIntroStrings.back),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: PillButton(
                      label: last
                          ? ApiKeysIntroStrings.done
                          : ApiKeysIntroStrings.next,
                      onPressed: () {
                        Haptics.tap();
                        last ? _close(true) : _go(_page + 1);
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
      total: ApiKeysIntroStrings.pages,
      art: IllustrationKind.homeThink,
      kicker: ApiKeysIntroStrings.useKicker,
      title: ApiKeysIntroStrings.useTitle,
      body: ApiKeysIntroStrings.useBody,
      children: [_Logos(widget.providerIds)],
    ),
    const TourPage(
      index: 1,
      total: ApiKeysIntroStrings.pages,
      art: IllustrationKind.homeRead,
      kicker: ApiKeysIntroStrings.privateKicker,
      title: ApiKeysIntroStrings.privateTitle,
      body: ApiKeysIntroStrings.privateBody,
      children: [TourPoints(ApiKeysIntroStrings.privatePoints)],
    ),
    const TourPage(
      index: 2,
      total: ApiKeysIntroStrings.pages,
      art: IllustrationKind.homeDream,
      kicker: ApiKeysIntroStrings.telemetryKicker,
      title: ApiKeysIntroStrings.telemetryTitle,
      body: ApiKeysIntroStrings.telemetryBody,
      children: [TourPoints(ApiKeysIntroStrings.telemetryPoints)],
    ),
    const TourPage(
      index: 3,
      total: ApiKeysIntroStrings.pages,
      art: IllustrationKind.homeCode,
      kicker: ApiKeysIntroStrings.usageKicker,
      title: ApiKeysIntroStrings.usageTitle,
      body: ApiKeysIntroStrings.usageBody,
      children: [TourPoints(ApiKeysIntroStrings.usagePoints)],
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
