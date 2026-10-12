import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_config.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/chat_event.dart';

/// Host of a citation: its site, else the host of its link.
String citeDomain(Citation c) {
  var host = c.site.trim().toLowerCase();
  if (host.contains('://')) host = Uri.tryParse(host)?.host ?? host;
  if (host.isEmpty || !host.contains('.')) {
    final fromUrl = Uri.tryParse(c.url)?.host ?? '';
    if (fromUrl.isNotEmpty) host = fromUrl.toLowerCase();
  }
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Short label for a source: `developer.mozilla.org` -> `mozilla`.
String citeShortName(Citation c) {
  // The user's own docs and files are named by their title, not a domain.
  if (c.kind == CitationKind.conversation) {
    final name = c.title.trim().isEmpty
        ? AppStrings.chatSourceUntitled
        : c.title.trim();
    final label = '${AppStrings.chatSourcePrefix}$name';
    return label.length <= MdSizes.citeChatNameMaxChars
        ? label
        : label.substring(0, MdSizes.citeChatNameMaxChars);
  }
  final own =
      c.kind == CitationKind.doc ||
      c.kind == CitationKind.file ||
      (c.kind == CitationKind.kb && (c.site == 'doc' || c.site == 'file'));
  if (own && c.title.trim().isNotEmpty) {
    return _clip(c.title.trim());
  }
  final domain = citeDomain(c);
  // GitHub sources all share one domain; name them by repo (or account).
  if (domain == 'github.com') {
    final parts = (Uri.tryParse(c.url)?.pathSegments ?? const <String>[])
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length >= 2) return _clip(parts[1]);
    if (parts.length == 1) return _clip(parts[0]);
  }
  final raw = domain.contains('.')
      ? domain
      : (c.site.trim().isEmpty ? c.title.trim() : c.site.trim());
  if (!domain.contains('.')) return _clip(raw);
  final parts = domain.split('.');
  if (parts.length >= 3 &&
      parts.last.length == 2 &&
      MdSizes.citeTldSecondLevel.contains(parts[parts.length - 2])) {
    parts.length -= 2;
  } else if (parts.length > 1) {
    parts.removeLast();
  }
  return _clip(parts.last);
}

String _clip(String s) => s.length <= MdSizes.citeNameMaxChars
    ? s
    : s.substring(0, MdSizes.citeNameMaxChars);

/// A run of citation tags: `[W1][W3]`, `[W1] [W3]` or `[W1], [W3]`.
final _run = RegExp(
  r'\[[KWDGC]\d{1,3}\](?!\()(?:[ \t,]*\[[KWDGC]\d{1,3}\](?!\())*',
);
final _tag = RegExp(r'\[([KWDGC]\d{1,3})\]');

/// `[W1, W3]` / `[W1; W3]`, a list inside one pair of brackets.
final _listed = RegExp(
  r'\[([KWDGC]\d{1,3}(?:[ \t]*[,;][ \t]*[KWDGC]\d{1,3})+)\](?!\()',
);
final _fence = RegExp(r'^\s*(```|~~~)');

/// Separates the ids of one grouped tag: `[W1+W3]`.
const citeGroupSeparator = '+';

/// A trailing, still-open tag (`[W`, `[W1`) while a reply streams. It is
/// hidden until the closing bracket arrives, so no raw fragment flashes.
final _openTag = RegExp(r'\[(?:[KWDGC]\d{0,3})?$');

String hidePartialCitation(String text) => text.replaceFirst(_openTag, '');

/// Turns each run of citation tags into ONE grouped tag, `[W1+W3]`, which
/// renders as a single chip with stacked logos. Tags of the same site fold
/// into one, unknown ids drop. Fenced code is left alone.
String prepareCitations(String text, List<Citation> citations) {
  if (!text.contains('[')) return text;
  final byId = {for (final c in citations) c.id: c};
  final out = <String>[];
  var inFence = false;
  for (final line in text.split('\n')) {
    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      out.add(line);
      continue;
    }
    if (inFence) {
      out.add(line);
      continue;
    }
    final split = line.replaceAllMapped(
      _listed,
      (m) => m[1]!.split(RegExp(r'[,;]')).map((t) => '[${t.trim()}]').join(),
    );
    out.add(
      split.replaceAllMapped(_run, (m) {
        final kept = <String>[];
        final seen = <String>{};
        for (final t in _tag.allMatches(m[0]!)) {
          final c = byId[t[1]];
          if (c == null) continue;
          if (seen.add('${c.kind.name}:${citeShortName(c)}')) kept.add(c.id);
        }
        return kept.isEmpty ? '' : '[${kept.join(citeGroupSeparator)}]';
      }),
    );
  }
  return out.join('\n');
}

/// Site logo. While it loads, or when it cannot (offline, no icon), a
/// monogram of the site name stands in. Logos are cached by Flutter's image
/// cache, so one site's icon is fetched once however often it is cited.
class SiteFavicon extends StatelessWidget {
  const SiteFavicon({super.key, required this.citation, required this.size});

  final Citation citation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final domain = citeDomain(citation);
    if (citation.kind == CitationKind.conversation) {
      return AppIcon(AppIcons.chat, size: size, color: p.textTertiary);
    }
    final fallback = domain.isEmpty
        ? AppIcon(
            citation.isKb ? AppIcons.knowledge : AppIcons.web,
            size: size,
            color: p.textTertiary,
          )
        : _Monogram(name: citeShortName(citation), size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox.square(
        dimension: size,
        child: domain.isEmpty
            ? fallback
            : Image.network(
                AppConfig.faviconUrl(domain),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (_, child, frame, sync) =>
                    sync || frame != null ? child : fallback,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// First letter of a site on a tinted tile.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return ColoredBox(
      color: p.surfaceHigh,
      child: Center(
        child: Text(
          letter,
          style: context.text.caption.copyWith(
            color: p.textSecondary,
            fontSize: size * MdSizes.monogramScale,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Compact inline pill: favicon + short site name. Several sources cited
/// together ([more]) show stacked logos and "+N". Tap opens the source,
/// long-press copies its link.
class CitationChip extends StatelessWidget {
  const CitationChip({
    super.key,
    required this.citation,
    required this.onTap,
    this.more = const [],
  });

  final Citation citation;
  final VoidCallback onTap;

  /// Other sources cited at the same spot.
  final List<Citation> more;

  Future<void> _copy(BuildContext context) async {
    Haptics.tap();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final p = context.palette;
    final style = context.text.label;
    await Clipboard.setData(ClipboardData(text: citation.url));
    messenger?.showSnackBar(
      SnackBar(
        backgroundColor: p.surfaceHigh,
        content: Text(AppStrings.copyLink, style: style),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final shown = [citation, ...more].take(MdSizes.citeStackMax).toList();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: more.isEmpty ? () => _copy(context) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.citeMinTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: MdSizes.citeChipHeight,
              constraints: const BoxConstraints(
                maxWidth: MdSizes.citeChipMaxWidth,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: p.border, width: AppBorder.thin),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width:
                        MdSizes.citeFavicon +
                        (shown.length - 1) * MdSizes.citeStackStep,
                    height: MdSizes.citeFavicon,
                    child: Stack(
                      children: [
                        // The first source sits on top of the stack.
                        for (var i = shown.length - 1; i >= 0; i--)
                          Positioned(
                            left: i * MdSizes.citeStackStep,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                border: more.isEmpty
                                    ? null
                                    : Border.all(
                                        color: p.surface,
                                        width: AppBorder.thin,
                                      ),
                              ),
                              child: SiteFavicon(
                                citation: shown[i],
                                size: MdSizes.citeFavicon,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      citeShortName(citation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(
                        color: p.textSecondary,
                        height: 1,
                      ),
                    ),
                  ),
                  if (more.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '+${more.length}',
                      style: t.caption.copyWith(
                        color: p.textTertiary,
                        height: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
