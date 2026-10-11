import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;

import '../../../../core/constants/app_config.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../data/chat_api.dart';
import '../../../../data/chat_event.dart';
import '../image_strip.dart';

/// A picture the model placed on its own line with `{{image:QUERY|CAPTION}}`.
/// The backend finds it (Wikipedia, Wikimedia Commons); nothing shows if no
/// match exists.
class InlineImageBlock extends StatefulWidget {
  const InlineImageBlock({super.key, required this.query, this.caption});

  final String query;
  final String? caption;

  @override
  State<InlineImageBlock> createState() => _InlineImageBlockState();
}

class _InlineImageBlockState extends State<InlineImageBlock> {
  ImageRef? _image;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(InlineImageBlock old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _resolve();
  }

  void _resolve() {
    final query = widget.query;
    final cached = ImageQueryCache.peek(query);
    if (cached != null) {
      _image = cached.firstOrNull;
      _done = true;
      return;
    }
    _done = false;
    ImageQueryCache.load(query).then((images) {
      if (!mounted || query != widget.query) return;
      setState(() {
        _image = images.firstOrNull;
        _done = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final image = _image;
    if (_done && image == null) return const SizedBox.shrink();

    final frame = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: p.imageBackdrop,
            constraints: const BoxConstraints(
              maxHeight: MdSizes.imageMaxHeight,
            ),
            height: image == null ? MdSizes.imagePlaceholderHeight : null,
            child: image == null
                ? null
                : NetImage(url: image.url, fit: BoxFit.contain),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.caption ?? image?.title ?? widget.query,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall.copyWith(color: p.textPrimary),
                ),
                if (image != null)
                  Text(image.site.toUpperCase(), style: t.caption),
              ],
            ),
          ),
        ],
      ),
    );

    if (image == null) return frame;
    return GestureDetector(
      onTap: () {
        Haptics.tap();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImageViewer(images: [image], initial: 0),
          ),
        );
      },
      child: frame,
    );
  }
}

/// `{{image:...}}` written inside a sentence instead of on its own line is
/// dropped rather than shown as raw text.
class StrayImageSyntax extends md.InlineSyntax {
  StrayImageSyntax() : super(r'\{\{image:[^}]{1,200}\}\}');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(''));
    return true;
  }
}

/// Results per description, fetched once from GET /images/search.
abstract final class ImageQueryCache {
  static final _results = <String, List<ImageRef>>{};
  static final _pending = <String, Future<List<ImageRef>>>{};

  static List<ImageRef>? peek(String query) => _results[query.toLowerCase()];

  static Future<List<ImageRef>> load(String query) {
    final key = query.toLowerCase();
    final hit = _results[key];
    if (hit != null) return Future.value(hit);
    return _pending[key] ??= _fetch(query).whenComplete(() {
      _pending.remove(key);
    });
  }

  static Future<List<ImageRef>> _fetch(String query) async {
    final key = query.toLowerCase();
    try {
      final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/images/search',
      ).replace(queryParameters: {'q': query, 'n': '1'});
      final res = await http
          .get(uri, headers: apiHeaders())
          .timeout(AppDurations.iconFetchTimeout);
      if (res.statusCode != 200) return const [];
      final list = (jsonDecode(res.body) as Map<String, dynamic>)['images'];
      final images = [
        for (final i in list as List)
          ImageRef.fromJson(i as Map<String, dynamic>),
      ];
      _results[key] = images;
      return images;
    } catch (_) {
      // Offline: try again next time the block is built.
      return const [];
    }
  }
}
