import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_keys.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/api_keys_api.dart';
import 'key_copy.dart';

/// Saves [key] for [provider] and tests it; null when it could not be saved.
typedef SaveKey = Future<KeyCheck?> Function(String provider, String key);

/// Add / replace sheet: pick the provider, paste the key (hidden by default),
/// then "Save and test" shows the live result here. Closes on success.
class KeySheet extends StatefulWidget {
  const KeySheet({
    super.key,
    required this.providers,
    required this.initial,
    required this.onSave,
  });

  final List<KeyProviderInfo> providers;

  /// Provider id preselected (replacing a key), or null to pick one.
  final String? initial;
  final SaveKey onSave;

  static Future<bool?> open(
    BuildContext context, {
    required List<KeyProviderInfo> providers,
    String? initial,
    required SaveKey onSave,
  }) {
    Haptics.tap();
    return showM3Sheet<bool>(
      context,
      builder: (_) =>
          KeySheet(providers: providers, initial: initial, onSave: onSave),
    );
  }

  @override
  State<KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<KeySheet> {
  final _field = TextEditingController();
  late String _provider = widget.initial ?? _firstFree();
  bool _hidden = true;
  bool _busy = false;
  String? _message;
  bool _bad = false;

  String _firstFree() {
    for (final p in widget.providers) {
      if (p.key == null) return p.id;
    }
    return widget.providers.isEmpty ? '' : widget.providers.first.id;
  }

  KeyProviderInfo? get _info {
    for (final p in widget.providers) {
      if (p.id == _provider) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    Haptics.tap();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _field.text = text;
      _message = null;
    });
  }

  Future<void> _link() async {
    Haptics.tap();
    final url = _info?.keyUrl ?? '';
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser: the link is also readable on the provider's site.
    }
  }

  Future<void> _save() async {
    final key = _field.text.trim();
    if (key.length < ApiKeysSizes.minKeyLength) {
      setState(() {
        _message = ApiKeysStrings.badFormat;
        _bad = true;
      });
      return;
    }
    Haptics.tap();
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await widget.onSave(_provider, key);
    if (!mounted) return;
    if (result == KeyCheck.valid) {
      Haptics.received();
      Navigator.pop(context, true);
      return;
    }
    Haptics.error();
    setState(() {
      _busy = false;
      _bad = true;
      _message = result == null
          ? ApiKeysStrings.saveFailed
          : keyCheckText(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final info = _info;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              M3SheetTitle(
                widget.initial == null || info == null
                    ? ApiKeysStrings.sheetTitleAdd
                    : ApiKeysStrings.sheetTitleFor(info.name),
                subtitle: ApiKeysStrings.sheetSubtitle,
              ),
              if (widget.initial == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.md,
                  ),
                  child: Wrap(
                    spacing: ApiKeysSizes.providerChipGap,
                    runSpacing: ApiKeysSizes.providerChipGap,
                    children: [
                      for (final x in widget.providers)
                        ChoiceChip(
                          key: ValueKey('provider-${x.id}'),
                          avatar: AppIcon(
                            ApiKeysIcons.provider(x.id),
                            size: AppIconSize.sm,
                            color: x.id == _provider
                                ? p.textInverse
                                : p.textPrimary,
                          ),
                          label: Text(x.name),
                          selected: x.id == _provider,
                          showCheckmark: false,
                          selectedColor: p.textPrimary,
                          labelStyle: TextStyle(
                            color: x.id == _provider
                                ? p.textInverse
                                : p.textPrimary,
                          ),
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: x.id == _provider
                                  ? p.textPrimary
                                  : p.borderStrong,
                            ),
                          ),
                          onSelected: _busy
                              ? null
                              : (_) {
                                  Haptics.tap();
                                  setState(() {
                                    _provider = x.id;
                                    _message = null;
                                  });
                                },
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: TextField(
                  key: const ValueKey('key-field'),
                  controller: _field,
                  enabled: !_busy,
                  obscureText: _hidden,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: ApiKeysSizes.sheetFieldLines,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: ApiKeysStrings.fieldLabel,
                    hintText: info?.placeholder,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _hidden
                              ? ApiKeysStrings.show
                              : ApiKeysStrings.hide,
                          icon: AppIcon(
                            _hidden ? ApiKeysIcons.show : ApiKeysIcons.hide,
                            size: AppIconSize.md,
                          ),
                          onPressed: () {
                            Haptics.tap();
                            setState(() => _hidden = !_hidden);
                          },
                        ),
                        IconButton(
                          key: const ValueKey('key-paste'),
                          tooltip: ApiKeysStrings.paste,
                          icon: const AppIcon(
                            ApiKeysIcons.paste,
                            size: AppIconSize.md,
                          ),
                          onPressed: _busy ? null : _paste,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    0,
                  ),
                  child: Text(
                    _message!,
                    key: const ValueKey('key-message'),
                    style: context.text.bodySmall.copyWith(
                      color: _bad ? p.error : p.textSecondary,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    if ((info?.keyUrl ?? '').isNotEmpty)
                      TextButton.icon(
                        key: const ValueKey('key-link'),
                        onPressed: _link,
                        icon: const AppIcon(
                          ApiKeysIcons.link,
                          size: AppIconSize.md,
                        ),
                        label: const Text(ApiKeysStrings.getKey),
                      ),
                    const Spacer(),
                    FilledButton(
                      key: const ValueKey('key-save'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(
                          ApiKeysSizes.saveMinWidth,
                          AppSizes.buttonHeight,
                        ),
                      ),
                      onPressed: _busy ? null : _save,
                      child: Text(
                        _busy ? ApiKeysStrings.saving : ApiKeysStrings.save,
                      ),
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
}
