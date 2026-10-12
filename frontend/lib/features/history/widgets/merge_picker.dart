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
import '../../settings/widgets/settings_kit.dart';

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
              M3SheetTitle(sentenceCase(LineageStrings.pickChat)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: TextField(
                  onChanged: _onSearch,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: AppStrings.searchChats,
                    prefixIcon: AppIcon(
                      AppIcons.search,
                      size: AppIconSize.md,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: _list(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed || _items.isEmpty) {
      return SingleChildScrollView(
        child: SettingsEmptyState(
          _failed ? AppStrings.errorNetwork : LineageStrings.noOtherChats,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.lg,
      ),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final chat = _items[i];
        return M3Cell(
          index: i,
          count: _items.length,
          child: ListTile(
            title: Text(
              chat.title ?? AppStrings.untitled,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: chat.preview.isEmpty
                ? null
                : Text(
                    chat.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: () {
              Haptics.tap();
              Navigator.pop(context, chat);
            },
          ),
        );
      },
    );
  }
}
