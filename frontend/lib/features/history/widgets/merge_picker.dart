import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/chat_api.dart';
import '../../../data/conversation.dart';

/// Sheet that lists the other chats (searchable) and returns the one picked
/// to merge with [exclude].
Future<ConversationSummary?> showMergePicker(
  BuildContext context, {
  required String exclude,
  required Future<List<ConversationSummary>> Function(String query) search,
}) {
  return showM3Sheet<ConversationSummary>(
    context,
    builder: (_) => _MergePicker(exclude: exclude, search: search),
  );
}

class _MergePicker extends StatefulWidget {
  const _MergePicker({required this.exclude, required this.search});

  final String exclude;
  final Future<List<ConversationSummary>> Function(String query) search;

  @override
  State<_MergePicker> createState() => _MergePickerState();
}

class _MergePickerState extends State<_MergePicker> {
  List<ConversationSummary> _items = [];
  bool _loading = true;
  bool _failed = false;
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final request = ++_request;
    try {
      final items = await widget.search(query);
      if (!mounted || request != _request) return;
      setState(() {
        _items = items.where((c) => c.id != widget.exclude).toList();
        _failed = false;
        _loading = false;
      });
    } on ApiException {
      if (!mounted || request != _request) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(AppDurations.searchDebounce, () => _load(text));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * LineageSizes.pickerHeightFactor,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.lg,
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.merge,
                      size: AppIconSize.sm,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(LineageStrings.pickChat, style: t.caption),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: TextField(
                  onChanged: _onSearch,
                  style: t.body,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: AppStrings.searchChats,
                    prefixIcon: AppIcon(
                      AppIcons.search,
                      size: AppIconSize.md,
                      color: p.textTertiary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: _list(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    if (_loading) {
      return Center(
        child: SizedBox.square(
          dimension: LineageSizes.progress,
          child: CircularProgressIndicator(
            strokeWidth: AppBorder.thin,
            color: p.textSecondary,
          ),
        ),
      );
    }
    if (_failed || _items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Text(
          _failed ? AppStrings.errorNetwork : LineageStrings.noOtherChats,
          textAlign: TextAlign.center,
          style: t.bodySmall,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final chat = _items[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.tap();
            Navigator.pop(context, chat);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat.title ?? AppStrings.untitled,
                  style: t.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (chat.preview.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    chat.preview,
                    style: t.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
