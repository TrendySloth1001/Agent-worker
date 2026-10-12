import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/chat_api.dart';
import '../../../../data/github_api.dart';
import '../markdown/inline_icon.dart';
import '../open_url.dart';
import '../rich/diff_block.dart';
import '../rich/playful_common.dart';
import '../rich/rich_frame.dart';
import 'github_connect_card.dart';
import '../../../../core/widgets/m3_kit_extras.dart';

// ---- block parsing -----------------------------------------------------------

/// `owner/repo[@ref][:path]`, also accepted as a github.com URL.
class GhRef {
  const GhRef(this.owner, this.repo, {this.ref, this.path = ''});
  final String owner, repo;
  final String? ref;
  final String path;

  String get full => '$owner/$repo';
  String get url => 'https://github.com/$owner/$repo';
}

final _urlRef = RegExp(
  r'github\.com/([\w-]+)/([\w.-]+?)(?:\.git)?(?:/(?:tree|blob|commits)/([^/\s]+)(?:/(\S*))?)?/?$',
);
final _bareRef = RegExp(r'^([\w-]+)/([\w.-]+?)(?:@([^\s:]+))?(?::(\S*))?$');

/// Parses one spec token; null when it is not `owner/repo…`.
GhRef? parseGhRef(String token) {
  final s = token.trim().replaceAll(RegExp(r'^[`"]+|[`"]+$'), '');
  final m = _urlRef.firstMatch(s) ?? _bareRef.firstMatch(s);
  if (m == null) return null;
  final path = (m[4] ?? '').replaceAll(RegExp(r'^/+|/+$'), '');
  final ref = m[3];
  return GhRef(
    m[1]!,
    m[2]!,
    ref: ref == null || ref.isEmpty ? null : ref,
    path: path,
  );
}

/// First line of a block (ignoring blanks), or `key: value` lines as a map.
List<String> ghLines(String source) => playfulLines(source);

/// `open` / `closed` / `all` found anywhere in the block, else `open`.
String ghState(String source) {
  final s = source.toLowerCase();
  for (final st in [GithubStrings.stateClosed, GithubStrings.stateAll]) {
    if (RegExp('\\b$st\\b').hasMatch(s)) return st;
  }
  return GithubStrings.stateOpen;
}

// ---- small pieces ----------------------------------------------------------

/// A GitHub octicon (Iconify `octicon:` set).
class Octicon extends StatelessWidget {
  const Octicon(
    this.name, {
    super.key,
    this.size = GithubSizes.octicon,
    this.color,
  });

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => InlineIcon(
    set: GithubOcticons.set,
    name: name,
    size: size,
    color: color ?? context.palette.textTertiary,
  );
}

/// Round avatar with a bordered placeholder while loading or on failure.
class GhAvatar extends StatelessWidget {
  const GhAvatar(this.url, {super.key, this.size = GithubSizes.avatar});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final empty = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.surfaceRaised,
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
    );
    if (url.isEmpty) return empty;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => empty,
        frameBuilder: (_, child, frame, sync) =>
            frame == null && !sync ? empty : child,
      ),
    );
  }
}

/// Octicon + mono figure, e.g. a star count.
class GhStat extends StatelessWidget {
  const GhStat(this.icon, this.text, {super.key, this.accent = false});

  final String icon, text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = accent ? p.accent : p.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Octicon(icon, size: GithubSizes.octiconSmall, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(text, style: context.text.caption.copyWith(color: color)),
      ],
    );
  }
}

/// Outlined mono pill (topics, refs, shas).
class GhChip extends StatelessWidget {
  const GhChip(this.text, {super.key, this.icon, this.dot, this.onTap});

  final String text;
  final String? icon;

  /// Small colored dot (GitHub label color).
  final Color? dot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final chip = Container(
      height: GithubSizes.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: GithubSizes.chipPadH),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: GithubSizes.labelDot,
              height: GithubSizes.labelDot,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          if (icon != null) ...[
            Octicon(icon!, size: GithubSizes.octiconSmall),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.caption.copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GhTap(onTap: onTap!, child: chip);
  }
}

/// GitHub label hex (`d73a4a`) to a color; null when invalid.
Color? ghLabelColor(String hex) {
  final v = int.tryParse(hex, radix: 16);
  if (v == null || hex.length != 6) return null;
  return Color(0xFF000000 | v);
}

/// Tap target with the standard haptic.
class GhTap extends StatelessWidget {
  const GhTap({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      Haptics.tap();
      onTap();
    },
    child: child,
  );
}

/// `+12 −3` in mono, added in text color, removed in accent.
class GhDelta extends StatelessWidget {
  const GhDelta({super.key, required this.add, required this.del});

  final int add, del;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text.caption;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(GithubStrings.plus(add), style: t.copyWith(color: p.textPrimary)),
        const SizedBox(width: AppSpacing.xs),
        Text(GithubStrings.minus(del), style: t.copyWith(color: p.accent)),
      ],
    );
  }
}

/// Thin divider between rows.
class GhDivider extends StatelessWidget {
  const GhDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: AppBorder.thin, color: context.palette.border);
}

/// Mono caps section label.
class GhSection extends StatelessWidget {
  const GhSection(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: GithubSizes.rowGap,
      bottom: AppSpacing.xs,
    ),
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.text.caption)),
        ?trailing,
      ],
    ),
  );
}

/// VISIT: the remembered browser, else asks which one.
Future<void> ghVisit(BuildContext context, String url) =>
    visitUrl(context, url);

/// Copies [text] and confirms with a short notice.
Future<void> ghCopy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: AppDurations.copiedFeedback,
      content: Text(AppStrings.copied),
    ),
  );
}

/// VISIT action: asks which browser (or uses the remembered one).
RichAction ghVisitAction(BuildContext context, String url) => RichAction(
  icon: GithubIcons.visit,
  label: GithubStrings.visit,
  onTap: () async {
    await visitUrl(context, url);
    return true;
  },
);

// ---- loading / error -----------------------------------------------------------

/// Pulsing-free skeleton: a few muted bars.
class GhSkeleton extends StatelessWidget {
  const GhSkeleton({super.key, this.rows = GithubSizes.skeletonRows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(GithubSizes.pad),
      child: LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) const SizedBox(height: GithubSizes.rowGap),
              Container(
                height: GithubSizes.skeletonBar,
                width:
                    c.maxWidth *
                    GithubSizes.skeletonWidths[i %
                        GithubSizes.skeletonWidths.length],
                decoration: BoxDecoration(
                  color: p.border.withValues(alpha: GithubSizes.skeletonAlpha),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error line with a RETRY button.
class GhError extends StatelessWidget {
  const GhError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(GithubSizes.pad),
      child: Row(
        children: [
          Octicon(GithubOcticons.mark, color: p.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall.copyWith(color: p.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PlayfulButton(
            label: GithubStrings.retry,
            icon: GithubIcons.retry,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Runs [load] once (and again on retry), showing a skeleton, the error with
/// RETRY, or [builder] with the data.
class GhFuture<T> extends StatefulWidget {
  const GhFuture({
    super.key,
    required this.load,
    required this.builder,
    this.skeletonRows = GithubSizes.skeletonRows,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final int skeletonRows;

  @override
  State<GhFuture<T>> createState() => _GhFutureState<T>();
}

class _GhFutureState<T> extends State<GhFuture<T>> {
  late Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          // A personal card (my repos) before GitHub is connected.
          if (e is ApiException && e.status == 409) {
            return GithubConnectPanel(paper: context.palette.codeBackground);
          }
          return GhError(
            message: e is ApiException ? e.message : GithubStrings.loadFailed,
            onRetry: () => setState(() => _future = widget.load()),
          );
        }
        if (!snap.hasData) return GhSkeleton(rows: widget.skeletonRows);
        return widget.builder(context, snap.data as T);
      },
    );
  }
}

/// Card shown when the block itself cannot be understood.
class GhBadBlock extends StatelessWidget {
  const GhBadBlock({
    super.key,
    required this.title,
    required this.source,
    required this.hint,
  });

  final String title, source, hint;

  @override
  Widget build(BuildContext context) => RichCard(
    title: title,
    leading: const Octicon(GithubOcticons.mark),
    child: Padding(
      padding: const EdgeInsets.all(GithubSizes.pad),
      child: Text(
        '$hint: ${source.trim()}',
        style: context.text.bodySmall.copyWith(
          color: context.palette.textSecondary,
        ),
      ),
    ),
  );
}

// ---- issues / PR state ---------------------------------------------------------

/// Octicon and color for an issue / PR state.
(String, Color) ghStateIcon(BuildContext context, GhIssue i) {
  final p = context.palette;
  if (i.isPr) {
    return switch (i.state) {
      GithubStrings.stateMerged => (GithubOcticons.merged, p.accent),
      GithubStrings.stateDraft => (GithubOcticons.prDraft, p.textTertiary),
      GithubStrings.stateClosed => (GithubOcticons.prClosed, p.textTertiary),
      _ => (GithubOcticons.pr, p.textPrimary),
    };
  }
  if (i.state == GithubStrings.stateClosed) {
    return i.stateReason == 'not_planned'
        ? (GithubOcticons.issueSkipped, p.textTertiary)
        : (GithubOcticons.issueClosed, p.accent);
  }
  return (GithubOcticons.issueOpen, p.textPrimary);
}

// ---- changed files ---------------------------------------------------------------

String _fileIcon(String status) => switch (status) {
  'added' => GithubOcticons.added,
  'removed' => GithubOcticons.removed,
  'renamed' => GithubOcticons.renamed,
  _ => GithubOcticons.modified,
};

/// Changed files; each row expands into its diff.
class GhFilesList extends StatefulWidget {
  const GhFilesList({
    super.key,
    required this.files,
    this.truncated = false,
    this.moreUrl,
  });

  final List<GhFile> files;
  final bool truncated;
  final String? moreUrl;

  @override
  State<GhFilesList> createState() => _GhFilesListState();
}

class _GhFilesListState extends State<GhFilesList> {
  final _open = <int>{};
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final files = widget.files;
    final shown = _all
        ? files.length
        : files.length.clamp(0, GithubLimits.filesVisible);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown; i++) ...[
          GhTap(
            onTap: () => setState(() {
              if (!_open.remove(i)) _open.add(i);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Octicon(
                    _fileIcon(files[i].status),
                    size: GithubSizes.octiconSmall,
                    color: files[i].status == 'removed'
                        ? p.accent
                        : p.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      files[i].filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: t.code.copyWith(color: p.textPrimary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GhDelta(add: files[i].additions, del: files[i].deletions),
                  const SizedBox(width: AppSpacing.xs),
                  AppIcon(
                    _open.contains(i)
                        ? GithubIcons.collapse
                        : GithubIcons.expand,
                    size: AppIconSize.sm,
                    color: p.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: GithubDurations.expand,
            alignment: Alignment.topCenter,
            child: _open.contains(i)
                ? _Patch(file: files[i])
                : const SizedBox(width: double.infinity),
          ),
        ],
        if (files.length > GithubLimits.filesVisible)
          Align(
            alignment: Alignment.centerLeft,
            child: GhTap(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  _all ? GithubStrings.showLess : GithubStrings.loadMore,
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
              ),
            ),
          ),
        if (widget.truncated)
          GhTap(
            onTap: () {
              if (widget.moreUrl != null) openUrl(context, widget.moreUrl!);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(GithubStrings.filesTruncated, style: t.caption),
            ),
          ),
      ],
    );
  }
}

class _Patch extends StatelessWidget {
  const _Patch({required this.file});

  final GhFile file;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final patch = file.patch;
    if (patch == null || patch.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(GithubStrings.noPatch, style: context.text.caption),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxHeight: GithubSizes.codeMaxHeight),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DiffLines(code: patch),
            if (file.patchTruncated)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  GithubStrings.patchTruncated,
                  style: context.text.caption,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- paging and filtering pieces ---------------------------------------------

/// Outlined search / filter field with a clear button.
class GhSearchField extends StatefulWidget {
  const GhSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<GhSearchField> createState() => _GhSearchFieldState();
}

class _GhSearchFieldState extends State<GhSearchField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    // A tonal pill like the app's other search bars: no outline at rest, a
    // thin one while typing.
    final shape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: GithubPagingSizes.fieldHeight,
      child: TextField(
        controller: _c,
        autofocus: widget.autofocus,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        cursorColor: p.accent,
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: t.bodySmall.copyWith(color: p.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: p.surfaceHigh,
          hintText: widget.hint,
          hintMaxLines: 1,
          hintStyle: t.bodySmall.copyWith(color: p.textTertiary),
          contentPadding: EdgeInsets.zero,
          prefixIcon: AppIcon(
            AppIcons.search,
            size: AppIconSize.sm,
            color: p.textTertiary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: GithubPagingSizes.fieldHeight,
            minHeight: GithubPagingSizes.fieldHeight,
          ),
          suffixIcon: _c.text.isEmpty
              ? null
              : GhTap(
                  onTap: () {
                    _c.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                  child: AppIcon(
                    GithubPagingIcons.clear,
                    size: AppIconSize.sm,
                    color: p.textTertiary,
                    semanticLabel: GithubPagingStrings.clear,
                  ),
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: GithubPagingSizes.fieldHeight,
            minHeight: GithubPagingSizes.fieldHeight,
          ),
          border: shape,
          enabledBorder: shape,
          focusedBorder: shape.copyWith(
            borderSide: BorderSide(
              color: p.borderStrong,
              width: AppBorder.thin,
            ),
          ),
        ),
      ),
    );
  }
}

/// Square check mark for multi-select rows.
class GhCheck extends StatelessWidget {
  const GhCheck({super.key, required this.on, this.muted = false});

  final bool on;

  /// Checked but fixed (the default branch).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = muted ? p.textTertiary : p.textPrimary;
    return Container(
      width: GithubPagingSizes.checkBox,
      height: GithubPagingSizes.checkBox,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? color : null,
        borderRadius: BorderRadius.circular(AppRadius.sm / 2),
        border: Border.all(
          color: on ? color : p.borderStrong,
          width: AppBorder.thin,
        ),
      ),
      child: on
          ? AppIcon(
              GithubPagingIcons.check,
              size: GithubPagingSizes.checkIcon,
              color: p.background,
            )
          : null,
    );
  }
}

/// Small spinner row at the end of an infinite list.
class GhLoadingRow extends StatelessWidget {
  const GhLoadingRow({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: GithubPagingSizes.spinner,
            child: CircularProgressIndicator(
              strokeWidth: AppBorder.thin,
              color: p.textSecondary,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(label!, style: context.text.caption),
          ],
        ],
      ),
    );
  }
}

/// Toggle / picker chip of filter bars.
class GhFilterChip extends StatelessWidget {
  const GhFilterChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.picker = false,
    this.height = GithubSizes.chipHeight,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  /// Row height; next to a [GhSearchField] use [GithubPagingSizes.fieldHeight].
  final double height;

  /// Opens a choice (shows a chevron).
  final bool picker;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GhTap(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: GithubSizes.chipPadH),
        decoration: BoxDecoration(
          color: on ? p.textPrimary : null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: on ? p.textPrimary : p.border,
            width: AppBorder.thin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.text.caption.copyWith(
                color: on ? p.background : p.textSecondary,
              ),
            ),
            if (picker) ...[
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                GithubPagingIcons.picker,
                size: GithubPagingSizes.checkIcon,
                color: on ? p.background : p.textTertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [text] with the words matching [tokens] (case-insensitive) in accent.
class GhHighlight extends StatelessWidget {
  const GhHighlight(
    this.text, {
    super.key,
    required this.tokens,
    required this.style,
    this.maxLines,
  });

  final String text;
  final List<String> tokens;
  final TextStyle style;
  final int? maxLines;

  /// `(start, end)` ranges of [text] to highlight.
  static List<(int, int)> ranges(String text, List<String> tokens) {
    final lower = text.toLowerCase();
    final marks = List<bool>.filled(text.length, false);
    for (final tok in tokens) {
      final q = tok.toLowerCase();
      if (q.length < 2) continue;
      var i = lower.indexOf(q);
      while (i >= 0) {
        for (var k = i; k < i + q.length; k++) {
          marks[k] = true;
        }
        i = lower.indexOf(q, i + q.length);
      }
    }
    final out = <(int, int)>[];
    var start = -1;
    for (var i = 0; i <= marks.length; i++) {
      final on = i < marks.length && marks[i];
      if (on && start < 0) start = i;
      if (!on && start >= 0) {
        out.add((start, i));
        start = -1;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final marks = ranges(text, tokens);
    final hi = style.copyWith(
      color: context.palette.accent,
      fontWeight: FontWeight.w700,
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final (s, e) in marks) {
      if (s > at) spans.add(TextSpan(text: text.substring(at, s)));
      spans.add(TextSpan(text: text.substring(s, e), style: hi));
      at = e;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// Bottom sheet listing [options]; returns the one tapped.
Future<String?> ghPickOne(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? selected,
}) {
  final p = context.palette;
  return showM3Sheet<String>(
    context,
    builder: (context) {
      final t = context.text;
      final media = MediaQuery.of(context);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height * GithubPagingSizes.sheetHeightFactor,
        ),
        child: SafeArea(
          top: false,
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
                child: Text(title, style: t.caption),
              ),
              const GhDivider(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                  ),
                  children: [
                    for (final o in options)
                      GhTap(
                        onTap: () => Navigator.pop(context, o),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: p.border)),
                          ),
                          child: Row(
                            children: [
                              GhCheck(on: o == selected),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  o,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall.copyWith(
                                    color: p.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
