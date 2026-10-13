import 'package:flutter/material.dart';

import '../../../core/constants/api_keys.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/api_keys_api.dart';
import '../../storage/storage_actions.dart';
import '../widgets/settings_kit.dart';
import 'api_keys_controller.dart';
import 'key_copy.dart';
import 'key_sheet.dart';
import 'key_usage_screen.dart';
import 'keys_intro_screen.dart';

/// Settings → Your API keys. Open to every signed-in user (not owner-only).
class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key, this.controller});

  /// Test seam; defaults to a controller on the real API.
  final ApiKeysController? controller;

  static Future<void> open(BuildContext context) {
    Haptics.tap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ApiKeysScreen()));
  }

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  late final _c = widget.controller ?? ApiKeysController();

  @override
  void initState() {
    super.initState();
    _c.reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstOpen());
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  /// The intro shows the first time this page opens.
  Future<void> _firstOpen() async {
    if (await _c.introSeen() || !mounted) return;
    await _c.markIntroSeen();
    if (mounted) await _intro();
  }

  Future<void> _intro() async {
    final add = await KeysIntroScreen.open(
      context,
      providers: _c.providers.isEmpty
          ? null
          : [for (final p in _c.providers) p.id],
    );
    if (add && mounted) await _add();
  }

  Future<void> _add([String? provider]) async {
    if (!_c.loaded) await _c.reload();
    if (!mounted || _c.providers.isEmpty) return;
    final saved = await KeySheet.open(
      context,
      providers: _c.providers,
      initial: provider,
      onSave: _c.save,
    );
    if (saved == true && mounted) {
      storageNotice(context, ApiKeysStrings.savedWorks);
    }
  }

  Future<void> _test(String id) async {
    Haptics.tap();
    final r = await _c.test(id);
    if (r == KeyCheck.valid) {
      Haptics.received();
    } else {
      Haptics.error();
    }
  }

  Future<void> _remove(KeyProviderInfo p) async {
    Haptics.tap();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StorageDialog(
        title: ApiKeysStrings.removeTitle,
        confirm: ApiKeysStrings.remove,
        destructive: true,
        onConfirm: () => Navigator.pop(dialog, true),
        child: Text(
          ApiKeysStrings.removeBody(p.name),
          style: Theme.of(dialog).textTheme.bodyMedium,
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final done = await _c.remove(p.id);
    if (!mounted) return;
    storageNotice(
      context,
      done ? ApiKeysStrings.removed : ApiKeysStrings.removeFailed,
      error: !done,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => M3Page(
        title: ApiKeysStrings.title,
        onRefresh: _c.reload,
        actions: [
          IconButton(
            key: const ValueKey('how-it-works'),
            tooltip: ApiKeysStrings.howItWorks,
            icon: const AppIcon(ApiKeysIcons.info, size: AppIconSize.md),
            onPressed: _intro,
          ),
        ],
        slivers: [
          M3Body(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SettingsSizes.headerInset,
                  0,
                  SettingsSizes.headerInset,
                  AppSpacing.md,
                ),
                child: Text.rich(
                  TextSpan(
                    text: '${ApiKeysStrings.lead} ',
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          key: const ValueKey('how-link'),
                          onTap: _intro,
                          child: Text(
                            ApiKeysStrings.howItWorks,
                            style: context.text.bodySmall.copyWith(
                              color: context.palette.accent,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  style: context.text.bodySmall.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              ),
              if (_c.hasValidKey) ...[
                SettingsGroup(
                  entries: [
                    GroupEntry(
                      SettingsTile(
                        icon: ApiKeysIcons.usage,
                        title: ApiKeysStrings.usageTitle,
                        summary: ApiKeysStrings.usageHelp,
                        onTap: () => KeyUsageScreen.open(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (_c.providers.isNotEmpty) ...[
                SettingsGroupHeader(ApiKeysStrings.providersHeader),
                SettingsGroup(
                  entries: [
                    for (final p in _c.providers)
                      GroupEntry(
                        _ProviderCell(
                          key: ValueKey('cell-${p.id}'),
                          provider: p,
                          busy: _c.busy.contains(p.id),
                          result: _c.results[p.id],
                          onAdd: () => _add(p.id),
                          onTest: () => _test(p.id),
                          onRemove: () => _remove(p),
                        ),
                      ),
                  ],
                ),
              ],
              Builder(builder: _footer),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    if (_c.providers.isNotEmpty) return const SizedBox.shrink();
    if (_c.loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Text(
            _c.error ?? ApiKeysStrings.loadFailed,
            textAlign: TextAlign.center,
            style: context.text.body.copyWith(color: context.palette.error),
          ),
          TextButton(
            onPressed: () {
              Haptics.tap();
              _c.reload();
            },
            child: const Text(AppStrings.retry),
          ),
        ],
      ),
    );
  }
}

/// One provider: logo, name, status chip and key hint, with Test / Replace /
/// Remove under it (or Add key when there is none) and the live test result.
class _ProviderCell extends StatelessWidget {
  const _ProviderCell({
    super.key,
    required this.provider,
    required this.busy,
    required this.result,
    required this.onAdd,
    required this.onTest,
    required this.onRemove,
  });

  final KeyProviderInfo provider;
  final bool busy;
  final KeyCheck? result;
  final VoidCallback onAdd, onTest, onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final key = provider.key;
    final bad =
        key != null &&
        (key.status == KeyStatus.invalid || key.status == KeyStatus.quota);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: SettingsIconCircle(
            ApiKeysIcons.provider(provider.id),
            color: p.textPrimary,
          ),
          title: Text(provider.name),
          subtitle: Text(
            key == null ? provider.blurb : ApiKeysStrings.endsWith(key.hint),
          ),
          trailing: key == null
              ? null
              : M3Tag(keyStatusText(key.status), accent: bad),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SettingsSizes.headerInset,
            0,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            children: [
              if (key == null)
                TextButton.icon(
                  key: ValueKey('add-${provider.id}'),
                  style: TextButton.styleFrom(foregroundColor: p.textPrimary),
                  onPressed: onAdd,
                  icon: const AppIcon(ApiKeysIcons.key, size: AppIconSize.md),
                  label: const Text(ApiKeysStrings.add),
                )
              else ...[
                TextButton(
                  key: ValueKey('test-${provider.id}'),
                  style: TextButton.styleFrom(foregroundColor: p.textPrimary),
                  onPressed: busy ? null : onTest,
                  child: Text(
                    busy ? ApiKeysStrings.testing : ApiKeysStrings.test,
                  ),
                ),
                TextButton(
                  key: ValueKey('replace-${provider.id}'),
                  style: TextButton.styleFrom(foregroundColor: p.textPrimary),
                  onPressed: busy ? null : onAdd,
                  child: const Text(ApiKeysStrings.replace),
                ),
                TextButton(
                  key: ValueKey('remove-${provider.id}'),
                  style: TextButton.styleFrom(foregroundColor: p.error),
                  onPressed: busy ? null : onRemove,
                  child: const Text(ApiKeysStrings.remove),
                ),
              ],
              if (result != null)
                Text(
                  keyCheckText(result!),
                  key: ValueKey('result-${provider.id}'),
                  style: context.text.bodySmall.copyWith(
                    color: result == KeyCheck.valid
                        ? p.textPrimary
                        : result == KeyCheck.network
                        ? p.textSecondary
                        : p.error,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
