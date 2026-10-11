import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../constants/app_icons.dart';
import '../constants/app_sizes.dart';
import '../constants/app_strings.dart';
import '../haptics.dart';
import '../platform/browsers.dart';
import '../theme/app_palette.dart';
import 'app_icon.dart';

/// Bottom sheet listing the browsers on the device. Returns the chosen
/// package; '' means "system default" (settings mode only); null is dismissed.
/// With [forSettings] a pick is saved straight away, otherwise the
/// ALWAYS USE THIS BROWSER box decides whether it is remembered.
Future<String?> showBrowserPicker(
  BuildContext context, {
  bool forSettings = false,
}) {
  Haptics.tap();
  final p = context.palette;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (_) => _BrowserSheet(forSettings: forSettings),
  );
}

/// The remembered browser, else the picker. Null when dismissed.
Future<String?> pickOrRemembered(BuildContext context) async {
  final saved = AppScope.of(context).settings.browserPackage;
  if (saved.isNotEmpty) return saved;
  if (!Browsers.supported) return '';
  return showBrowserPicker(context);
}

class _BrowserSheet extends StatefulWidget {
  const _BrowserSheet({required this.forSettings});

  final bool forSettings;

  @override
  State<_BrowserSheet> createState() => _BrowserSheetState();
}

class _BrowserSheetState extends State<_BrowserSheet> {
  List<InstalledBrowser>? _items;
  bool _always = false;

  @override
  void initState() {
    super.initState();
    Browsers.list().then((v) {
      if (mounted) setState(() => _items = v);
    });
  }

  void _pick(InstalledBrowser? b) {
    Haptics.tap();
    final settings = AppScope.of(context).settings;
    if (widget.forSettings || (_always && b != null)) {
      settings.setBrowser(b?.package ?? '', b?.label ?? '');
    }
    Navigator.pop(context, b?.package ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final saved = AppScope.of(context).settings.browserPackage;
    final items = _items;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.lg,
                AppSpacing.screenPadding,
                AppSpacing.sm,
              ),
              child: Text(BrowserStrings.title, style: t.label),
            ),
            Divider(color: p.border, height: AppBorder.thin),
            if (items == null)
              LinearProgressIndicator(
                minHeight: 2,
                color: p.accent,
                backgroundColor: p.border,
              )
            else if (items.isEmpty && !widget.forSettings)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(BrowserStrings.none, style: t.caption),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (widget.forSettings)
                      _Row(
                        label: BrowserStrings.systemDefault,
                        selected: saved.isEmpty,
                        onTap: () => _pick(null),
                      ),
                    for (final b in items)
                      _Row(
                        label: b.label,
                        icon: b.icon,
                        isDefault: b.isDefault,
                        selected: saved == b.package,
                        onTap: () => _pick(b),
                      ),
                  ],
                ),
              ),
            if (!widget.forSettings) ...[
              Divider(color: p.border, height: AppBorder.thin),
              InkWell(
                onTap: () {
                  Haptics.tap();
                  setState(() => _always = !_always);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: AppSizes.checkBox,
                        height: AppSizes.checkBox,
                        decoration: BoxDecoration(
                          color: _always ? p.accent : Colors.transparent,
                          border: Border.all(
                            color: _always ? p.accent : p.borderStrong,
                            width: AppBorder.thin,
                          ),
                        ),
                        child: _always
                            ? AppIcon(
                                AppIcons.check,
                                size: AppIconSize.xs,
                                color: p.textInverse,
                              )
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(BrowserStrings.always, style: t.label),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.onTap,
    this.icon,
    this.isDefault = false,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final Uint8List? icon;
  final bool isDefault, selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: AppSizes.browserRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: Row(
            children: [
              SizedBox(
                width: AppSizes.browserIcon,
                height: AppSizes.browserIcon,
                child: icon == null
                    ? AppIcon(
                        AppIcons.browser,
                        size: AppIconSize.md,
                        color: p.textSecondary,
                      )
                    : Image.memory(icon!, gaplessPlayback: true),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body,
                ),
              ),
              if (isDefault) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs + AppSpacing.xxs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: p.borderStrong,
                      width: AppBorder.thin,
                    ),
                  ),
                  child: Text(BrowserStrings.defaultTag, style: t.caption),
                ),
              ],
              const Spacer(),
              if (selected)
                AppIcon(AppIcons.check, size: AppIconSize.sm, color: p.accent),
            ],
          ),
        ),
      ),
    );
  }
}
