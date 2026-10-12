import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../features/settings/widgets/settings_kit.dart';
import '../app_scope.dart';
import '../constants/app_icons.dart';
import '../constants/app_sizes.dart';
import '../constants/app_strings.dart';
import '../haptics.dart';
import '../platform/browsers.dart';
import '../theme/app_palette.dart';
import 'app_icon.dart';
import 'm3_kit_extras.dart';

/// Bottom sheet listing the browsers on the device. Returns the chosen
/// package; '' means "system default" (settings mode only); null is dismissed.
/// With [forSettings] a pick is saved straight away, otherwise the
/// ALWAYS USE THIS BROWSER box decides whether it is remembered.
Future<String?> showBrowserPicker(
  BuildContext context, {
  bool forSettings = false,
}) {
  Haptics.tap();
  return showM3Sheet<String>(
    context,
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
    final saved = AppScope.of(context).settings.browserPackage;
    final items = _items;
    final rows = <Widget>[
      if (items != null) ...[
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
    ];
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            M3SheetTitle(sentenceCase(BrowserStrings.title)),
            if (items == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  color: p.accent,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              )
            else if (items.isEmpty && !widget.forSettings)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  sentenceCase(BrowserStrings.none),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) =>
                      M3Cell(index: i, count: rows.length, child: rows[i]),
                ),
              ),
            if (!widget.forSettings)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.sm,
                  AppSpacing.screenPadding,
                  0,
                ),
                child: SettingsGroup(
                  entries: [
                    GroupEntry(
                      CheckboxListTile(
                        value: _always,
                        title: Text(sentenceCase(BrowserStrings.always)),
                        onChanged: (v) {
                          Haptics.tap();
                          setState(() => _always = v ?? false);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
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
    return ListTile(
      onTap: onTap,
      selected: selected,
      leading: SizedBox(
        width: AppSizes.browserIcon,
        height: AppSizes.browserIcon,
        child: icon == null
            ? AppIcon(
                AppIcons.browser,
                size: AppIconSize.md,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )
            : Image.memory(icon!, gaplessPlayback: true),
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: selected
          ? AppIcon(AppIcons.check, size: AppIconSize.sm, color: p.accent)
          : isDefault
          ? M3Tag(BrowserStrings.defaultTag)
          : null,
    );
  }
}
