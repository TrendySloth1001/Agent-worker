import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/apps.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';

/// M3 search pill, the same look as the sidebar's "Search chats": a tonal
/// stadium with a small search icon, the hint in the body font, a clear
/// button once there is text, and a thin outline while focused. Changes
/// reach [onChanged] after [debounce] (immediately on submit or clear).
class GhPillSearch extends StatefulWidget {
  const GhPillSearch({
    super.key,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
    this.controller,
    this.debounce = GithubHubDurations.debounce,
    this.onFocusChange,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  /// Lets the screen clear the field (e.g. from an empty state).
  final TextEditingController? controller;
  final Duration debounce;

  /// Lets the screen make room for results while the keyboard is up.
  final ValueChanged<bool>? onFocusChange;

  @override
  State<GhPillSearch> createState() => _GhPillSearchState();
}

class _GhPillSearchState extends State<GhPillSearch> {
  late final TextEditingController _c =
      widget.controller ?? TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  String _sent = '';

  @override
  void initState() {
    super.initState();
    _sent = _c.text;
    _c.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.removeListener(_onText);
    if (widget.controller == null) _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    setState(() {});
    widget.onFocusChange?.call(_focus.hasFocus);
  }

  void _onText() {
    if (!mounted) return;
    setState(() {});
    if (_c.text == _sent) return;
    _timer?.cancel();
    if (_c.text.isEmpty) {
      _flush();
    } else {
      _timer = Timer(widget.debounce, _flush);
    }
  }

  void _flush() {
    _timer?.cancel();
    if (_c.text == _sent) return;
    _sent = _c.text;
    widget.onChanged(_c.text);
  }

  void _clear() {
    Haptics.tap();
    _c.clear();
    _flush();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final p = context.palette;
    final focused = _focus.hasFocus;
    final shape = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      textField: true,
      label: widget.hint,
      child: AnimatedContainer(
        duration: GithubHubDurations.focus,
        height: GithubHubSizes.searchHeight,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: shape,
          border: Border.all(
            color: focused ? p.borderStrong : Colors.transparent,
            width: AppBorder.thin,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: shape,
            onTap: _focus.requestFocus,
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.lg),
                AppIcon(
                  AppIcons.search,
                  size: AppIconSize.sm,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _c,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    textInputAction: TextInputAction.search,
                    textAlignVertical: TextAlignVertical.center,
                    cursorColor: p.accent,
                    style: tt.bodyLarge,
                    maxLines: 1,
                    onSubmitted: (_) {
                      _flush();
                      _focus.unfocus();
                    },
                    onTapOutside: (_) => _focus.unfocus(),
                    // The pill draws the field: no theme fill or borders.
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: widget.hint,
                      hintStyle: tt.bodyLarge!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (_c.text.isNotEmpty)
                  IconButton(
                    tooltip: GithubHubStrings.clearSearch,
                    visualDensity: VisualDensity.compact,
                    onPressed: _clear,
                    icon: AppIcon(
                      AppIcons.close,
                      size: AppIconSize.sm,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  const SizedBox(width: AppSpacing.lg),
                if (_c.text.isNotEmpty) const SizedBox(width: AppSpacing.xs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
