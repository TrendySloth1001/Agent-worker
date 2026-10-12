import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/history.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/doc_models.dart';
import '../../../data/docs_api.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../settings/widgets/settings_kit.dart';
import '../history_grouping.dart';

/// Bottom sheet listing the user's documents, newest first. Pops with the
/// tapped [Doc], or null.
Future<Doc?> showDocsSheet(BuildContext context, {DocsApi? api}) {
  Haptics.tap();
  return showM3Sheet<Doc>(
    context,
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
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const M3SheetTitle(DocsCopy.title)),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final at = d.updatedAt ?? d.createdAt;
                    return M3Cell(
                      index: i,
                      count: docs.length,
                      child: ListTile(
                        onTap: () {
                          Haptics.tap();
                          Navigator.pop(context, d);
                        },
                        leading: const SettingsIconCircle(AppIcons.doc),
                        title: Text(
                          d.title.isEmpty
                              ? HistoryStrings.docUntitled
                              : d.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: d.isRunning
                            ? const M3Tag(
                                HistoryStrings.docWriting,
                                accent: true,
                              )
                            : at == null
                            ? null
                            : M3Tag(historyTime(at.toLocal(), now)),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: loading
            ? SizedBox.square(
                dimension: AppIconSize.md,
                child: CircularProgressIndicator(
                  strokeWidth: AppBorder.thick,
                  color: p.accent,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text ?? '',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: () {
                        Haptics.tap();
                        onRetry!();
                      },
                      child: const Text(AppStrings.retry),
                    ),
                ],
              ),
      ),
    );
  }
}
