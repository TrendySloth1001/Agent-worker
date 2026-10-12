import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/m3_copy.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/time_ago.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/doc_models.dart';
import '../../data/docs_api.dart';
import '../settings/widgets/settings_kit.dart';

/// Opens the full-page documents list. Pops with the tapped [Doc], or null.
Future<Doc?> showDocsList(BuildContext context, {DocsApi? api}) {
  Haptics.tap();
  return Navigator.of(
    context,
  ).push<Doc>(settingsRoute(DocsListScreen(api: api ?? DocsApi())));
}

/// All documents, newest first, as one grouped list under a large app bar
/// with a search field. A full page rather than a sheet because there can be
/// many documents.
class DocsListScreen extends StatefulWidget {
  const DocsListScreen({super.key, required this.api, this.now});

  final DocsApi api;

  /// Test seam for the relative times.
  final DateTime? now;

  @override
  State<DocsListScreen> createState() => _DocsListScreenState();
}

class _DocsListScreenState extends State<DocsListScreen> {
  late Future<List<Doc>> _docs = _load();
  final _search = TextEditingController();
  String _query = '';

  Future<List<Doc>> _load() async {
    final docs = await widget.api.list();
    docs.sort(
      (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0)).compareTo(
        a.updatedAt ?? a.createdAt ?? DateTime(0),
      ),
    );
    return docs;
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() => _docs = next);
    await next.catchError((_) => <Doc>[]);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Doc>>(
      future: _docs,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        return M3Page(
          title: DocsCopy.title,
          onRefresh: _reload,
          slivers: [M3Body(children: _body(snap, done))],
        );
      },
    );
  }

  List<Widget> _body(AsyncSnapshot<List<Doc>> snap, bool done) {
    if (!done) {
      return [
        const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (snap.hasError) {
      return [
        M3Empty(
          icon: AppIcons.alert,
          title: DocsCopy.loadFailed,
          action: FilledButton.tonal(
            onPressed: () {
              Haptics.tap();
              _reload();
            },
            child: const Text(DocsCopy.retry),
          ),
        ),
      ];
    }
    final docs = snap.data!;
    if (docs.isEmpty) {
      return [M3Empty(icon: AppIcons.doc, title: DocsCopy.empty)];
    }
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final d in docs)
        if (q.isEmpty ||
            d.title.toLowerCase().contains(q) ||
            d.subtitle.toLowerCase().contains(q))
          d,
    ];
    final now = widget.now ?? DateTime.now();
    return [
      _DocSearch(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
      ),
      if (shown.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.xl),
          child: M3Empty(
            icon: AppIcons.search,
            title: DocsCopy.noMatches,
            hint: DocsCopy.noMatchesHint,
          ),
        )
      else
        SettingsGroup(
          entries: [
            for (final d in shown) GroupEntry(DocListTile(doc: d, now: now)),
          ],
        ),
    ];
  }
}

/// One document row: doc icon, title (up to two lines), status / sections /
/// time line and, while writing, a thin progress line.
class DocListTile extends StatelessWidget {
  const DocListTile({super.key, required this.doc, required this.now});

  final Doc doc;
  final DateTime now;

  int get _total => doc.sections.length;

  int get _written =>
      doc.sections.where((s) => s.status == DocSectionStatus.done).length;

  /// Human status for the secondary line, or null when the doc is fine.
  String? get _status {
    if (doc.isRunning) {
      if (doc.status == DocStatus.writing && _total > 0) {
        return '${DocsCopy.writing} $_written/$_total';
      }
      return doc.status == DocStatus.planning
          ? DocsCopy.planning
          : DocsCopy.writing;
    }
    return switch (doc.status) {
      DocStatus.failed => DocsCopy.failed,
      DocStatus.interrupted || DocStatus.partial => DocsCopy.stopped,
      DocStatus.outlineReady => DocsCopy.outline,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant);
    final status = _status;
    final hot = doc.isRunning;
    final bad = doc.status == DocStatus.failed;
    final at = doc.updatedAt ?? doc.createdAt;
    final rest = [
      if (_total > 0) DocsCopy.sections(_total),
      if (at != null) timeAgo(at.toLocal(), now),
    ].join(' · ');
    final statusColor = bad
        ? p.error
        : hot
        ? p.accent
        : scheme.onSurfaceVariant;
    return ListTile(
      onTap: () {
        Haptics.tap();
        Navigator.pop(context, doc);
      },
      leading: const SettingsIconCircle(AppIcons.doc),
      title: Text(
        doc.title.isEmpty ? DocsCopy.untitled : doc.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                if (status != null)
                  TextSpan(
                    text: status,
                    style: TextStyle(color: statusColor),
                  ),
                if (status != null && rest.isNotEmpty)
                  const TextSpan(text: ' · '),
                TextSpan(text: rest),
              ],
            ),
            style: muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hot && doc.status == DocStatus.writing && _total > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              minHeight: DocsListSizes.progressHeight,
              value: _written / _total,
              color: p.accent,
              backgroundColor: scheme.surfaceContainerHighest,
              stopIndicatorColor: Colors.transparent,
            ),
          ],
        ],
      ),
    );
  }
}

class _DocSearch extends StatelessWidget {
  const _DocSearch({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      borderSide: BorderSide.none,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SizedBox(
        height: DocsListSizes.searchHeight,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: DocsCopy.searchHint,
            filled: true,
            fillColor: scheme.surfaceContainerHigh,
            contentPadding: EdgeInsets.zero,
            prefixIcon: AppIcon(
              AppIcons.search,
              size: AppIconSize.md,
              color: scheme.onSurfaceVariant,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, v, _) => v.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const AppIcon(AppIcons.close, size: AppIconSize.md),
                      onPressed: () {
                        Haptics.tap();
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
            border: pill,
            enabledBorder: pill,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              borderSide: BorderSide(
                color: context.palette.accent,
                width: AppBorder.thick,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
