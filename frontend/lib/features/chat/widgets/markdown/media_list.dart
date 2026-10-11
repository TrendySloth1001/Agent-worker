import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/appear.dart';
import '../../../../core/widgets/dot_grid_background.dart';
import '../../../../data/chat_event.dart';
import '../image_strip.dart';
import 'inline_image.dart';
import 'md_blocks.dart';
import 'timeline_list.dart';

/// A picture list: each item is a row with a thumbnail on the left and a
/// numbered title, description and example on the right, separated by thin
/// rules. Below [MdSizes.mediaStackBelow] the thumbnail sits above the text.
class MediaList extends StatelessWidget {
  const MediaList({
    super.key,
    required this.block,
    required this.renderText,
    required this.renderLine,
    required this.streaming,
  });

  final MdMediaListBlock block;

  /// Renders block markdown (the description).
  final Widget Function(String text) renderText;

  /// Renders one line of inline markdown in [style] (title, example).
  final Widget Function(String text, TextStyle style) renderLine;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, c) {
        final stacked = c.maxWidth < MdSizes.mediaStackBelow;
        final items = block.items;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: p.border),
              _wrap(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: _MediaRow(
                    item: items[i],
                    earlier: [for (final e in items.take(i)) e.query],
                    stacked: stacked,
                    renderText: renderText,
                    renderLine: renderLine,
                  ),
                ),
                key: ValueKey(i),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Rows fade in while the reply streams; a finished reply shows them as is.
  Widget _wrap(Widget row, {required Key key}) => streaming
      ? Appear(key: key, child: row)
      : KeyedSubtree(key: key, child: row);
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.item,
    required this.earlier,
    required this.stacked,
    required this.renderText,
    required this.renderLine,
  });

  final MdMediaItem item;

  /// Image queries of the rows above, so this row picks a different picture.
  final List<String?> earlier;
  final bool stacked;
  final Widget Function(String) renderText;
  final Widget Function(String, TextStyle) renderLine;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final title = item.title;
    final example = item.example;
    final kids = item.children;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `1\.` so the number is not read as a list marker.
        renderLine(
          title == null ? '${item.number}\\.' : '${item.number}\\. $title',
          t.body.copyWith(fontWeight: FontWeight.w700),
        ),
        if (item.body.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          renderText(item.body),
        ],
        if (example != null) ...[
          const SizedBox(height: AppSpacing.xs),
          renderLine(
            example.isEmpty ? '*Example:*' : '*Example:* $example',
            t.body.copyWith(
              color: p.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (kids != null && kids.items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          TimelineList(list: kids, renderText: renderText),
        ],
      ],
    );

    final thumb = MediaThumb(
      query: item.query,
      caption: item.caption,
      earlier: earlier,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: MdSizes.mediaStackedHeight, child: thumb),
          const SizedBox(height: AppSpacing.md),
          text,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: MdSizes.mediaThumbWidth,
          child: AspectRatio(
            aspectRatio: MdSizes.mediaThumbAspect,
            child: thumb,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: text),
      ],
    );
  }
}

/// A rounded, bordered picture for [query], fitted whole on the image
/// backdrop. A muted box while it loads, a dot grid with an icon when
/// nothing matches. Tapping a found picture opens the full-screen viewer.
class MediaThumb extends StatefulWidget {
  const MediaThumb({
    super.key,
    required this.query,
    this.caption,
    this.earlier = const [],
  });

  final String? query;
  final String? caption;

  /// Queries of earlier rows in the same list; their pictures are skipped.
  final List<String?> earlier;

  @override
  State<MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<MediaThumb> {
  ImageRef? _image;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(MediaThumb old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _resolve();
  }

  void _resolve() {
    final query = widget.query;
    _image = null;
    if (query == null) {
      _done = true;
      return;
    }
    _done = false;
    _pick(query, widget.earlier).then((image) {
      if (!mounted || query != widget.query) return;
      setState(() {
        _image = image;
        _done = true;
      });
    });
  }

  /// First result for [query] that no earlier row already shows. Rows pick
  /// in order (each earlier row takes its own first unused result), so the
  /// choice is the same on every rebuild.
  static Future<ImageRef?> _pick(String query, List<String?> earlier) async {
    final taken = <String>{};
    for (final q in earlier) {
      if (q == null) continue;
      final options = await ImageQueryCache.load(q);
      final pick = options.where((o) => !taken.contains(o.url)).firstOrNull;
      if (pick != null) taken.add(pick.url);
    }
    final options = await ImageQueryCache.load(query);
    return options.where((o) => !taken.contains(o.url)).firstOrNull ??
        options.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final image = _image;
    final Widget content;
    if (image != null) {
      content = ColoredBox(
        color: p.imageBackdrop,
        child: NetImage(url: image.url, fit: BoxFit.contain),
      );
    } else if (!_done) {
      content = ColoredBox(color: p.surfaceHigh);
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: p.surface),
          const DotGridBackground(),
          Center(
            child: AppIcon(
              AppIcons.image,
              size: AppIconSize.md,
              color: p.textTertiary,
              semanticLabel: AppStrings.imageFailed,
            ),
          ),
        ],
      );
    }

    final frame = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      // Drawn over the picture so its edges never cover the border.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: AnimatedSwitcher(
        duration: AppDurations.imageFade,
        child: KeyedSubtree(
          key: ValueKey((image?.url, _done)),
          child: SizedBox.expand(child: content),
        ),
      ),
    );

    if (image == null) return frame;
    return Semantics(
      button: true,
      image: true,
      label: widget.caption ?? image.title,
      child: GestureDetector(
        onTap: () {
          Haptics.tap();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ImageViewer(images: [image], initial: 0),
            ),
          );
        },
        child: frame,
      ),
    );
  }
}
