import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/history.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/doc_models.dart';
import '../../../data/docs_api.dart';
import '../history_grouping.dart';

/// Bottom sheet listing the user's documents, newest first. Pops with the
/// tapped [Doc], or null.
Future<Doc?> showDocsSheet(BuildContext context, {DocsApi? api}) {
  Haptics.tap();
  final p = context.palette;
  return showModalBottomSheet<Doc>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (_) => _DocsSheet(api: api ?? DocsApi()),
  );
}

class _DocsSheet extends StatefulWidget {
  const _DocsSheet({required this.api});

  final DocsApi api;

  @override
  State<_DocsSheet> createState() => _DocsSheetState();
}

class _DocsSheetState extends State<_DocsSheet> {
  late Future<List<Doc>> _docs = _load();

  Future<List<Doc>> _load() async {
    final docs = await widget.api.list();
    docs.sort(
      (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0)).compareTo(
        a.updatedAt ?? a.createdAt ?? DateTime(0),
      ),
    );
    return docs;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.lg,
              AppSpacing.screenPadding,
              AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(HistoryStrings.docsTitle, style: t.caption),
            ),
          ),
          Flexible(
            child: FutureBuilder<List<Doc>>(
              future: _docs,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const _Note(loading: true);
                }
                if (snap.hasError) {
                  return _Note(
                    text: HistoryStrings.docsFailed,
                    onRetry: () => setState(() => _docs = _load()),
                  );
                }
                final docs = snap.data!;
                if (docs.isEmpty) {
                  return const _Note(text: HistoryStrings.docsEmpty);
                }
                final now = DateTime.now();
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final at = d.updatedAt ?? d.createdAt;
                    return InkWell(
                      onTap: () {
                        Haptics.tap();
                        Navigator.pop(context, d);
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: HistorySizes.rowHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.screenPadding,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  d.title.isEmpty
                                      ? HistoryStrings.docUntitled
                                      : d.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.body,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              if (d.isRunning)
                                Text(
                                  HistoryStrings.docWriting,
                                  style: t.caption.copyWith(color: p.accent),
                                )
                              else if (at != null)
                                Text(
                                  historyTime(at.toLocal(), now),
                                  style: t.caption,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({this.text, this.loading = false, this.onRetry});

  final String? text;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: loading
            ? SizedBox.square(
                dimension: AppIconSize.md,
                child: CircularProgressIndicator(
                  strokeWidth: AppBorder.thin,
                  color: p.textTertiary,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text ?? '',
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall,
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: () {
                        Haptics.tap();
                        onRetry!();
                      },
                      child: Text(
                        AppStrings.retry,
                        style: context.text.caption.copyWith(color: p.accent),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
