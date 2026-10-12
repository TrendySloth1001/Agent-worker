import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/connectors.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../settings/widgets/settings_kit.dart';
import '../../../data/connect_api.dart';
import '../../chat/widgets/markdown/app_markdown.dart';
import '../../github/widgets/gh_rows.dart';
import '../connector_actions.dart';

/// What a reader shows: the item as Markdown plus where it lives.
class ReaderContent {
  const ReaderContent({
    required this.title,
    required this.markdown,
    required this.url,
    this.truncated = false,
    this.canAddToKb = true,
    this.note,
  });

  final String title, markdown, url;
  final bool truncated, canAddToKb;

  /// A line above the content (e.g. "only details of this file").
  final String? note;
}

/// A Drive file or Notion page, read live: actions on top (Ask Sparky, add
/// to the knowledge base, open in the app), then the content as Markdown.
class ConnectorReader extends StatefulWidget {
  const ConnectorReader({
    super.key,
    required this.provider,
    required this.id,
    required this.initialTitle,
    required this.load,
    required this.prompt,
    required this.openLabel,
  });

  final String provider, id, initialTitle, openLabel;
  final Future<ReaderContent> Function() load;
  final String Function(String title) prompt;


  @override
  State<ConnectorReader> createState() => _ConnectorReaderState();
}

class _ConnectorReaderState extends State<ConnectorReader> {
  ReaderContent? _content;
  ConnectException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await widget.load();
      if (!mounted) return;
      setState(() => _content = c);
    } on ConnectException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _title {
    final t = _content?.title ?? widget.initialTitle;
    return t.isEmpty ? NotionStrings.untitled : t;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = _content;
    return M3Page(
      title: _title,
      onRefresh: _load,
      slivers: [
        M3Body(
          children: [
            M3Group(
              children: [
                SettingsTile(
                  icon: DriveIcons.ask,
                  title: ConnectorStrings.askSparky,
                  summary: ConnectorStrings.askSparkyHint,
                  onTap: () => askAboutItem(
                    context,
                    provider: widget.provider,
                    id: widget.id,
                    title: _title,
                    prompt: widget.prompt(_title),
                  ),
                ),
                if (c?.canAddToKb ?? true)
                  SettingsTile(
                    icon: AppIcons.knowledge,
                    title: ConnectorStrings.addToKb,
                    summary: ConnectorStrings.addToKbHint,
                    onTap: () => addItemToKnowledge(
                      context,
                      provider: widget.provider,
                      id: widget.id,
                    ),
                  ),
                if ((c?.url ?? '').isNotEmpty)
                  SettingsTile(
                    icon: AppIcons.openExternal,
                    title: widget.openLabel,
                    onTap: () => openExternal(context, c!.url),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loading && c == null)
              const GhSkeletonCells(count: ConnectorSizes.skeletonRows)
            else if (_error != null && c == null)
              M3Empty(
                icon: _error!.offline
                    ? ConnectorIcons.offline
                    : ConnectorIcons.warning,
                title: _error!.offline
                    ? ConnectorStrings.offline
                    : ConnectorStrings.loadFailed,
                hint: _error!.offline ? null : _error!.message,
                action: FilledButton.tonal(
                  onPressed: _load,
                  child: const Text(ConnectorStrings.retry),
                ),
              )
            else if (c != null)
              M3Card(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ConnectorSizes.readerMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final n in [
                        ?c.note,
                        if (c.truncated) ConnectorStrings.truncated,
                      ]) ...[
                        Text(
                          n,
                          style: tt.bodySmall!.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (c.markdown.trim().isEmpty)
                        Text(
                          NotionStrings.empty,
                          style: tt.bodyMedium!.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else
                        AppMarkdown(
                          data: c.markdown,
                          citations: const [],
                          streaming: false,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
