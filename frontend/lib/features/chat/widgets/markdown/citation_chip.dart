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
  final domain = citeDomain(c);
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

final _run = RegExp(r'\[[KW]\d{1,2}\](?!\()(?:[ \t,]*\[[KW]\d{1,2}\](?!\())*');
final _tag = RegExp(r'\[([KW]\d{1,2})\]');
final _fence = RegExp(r'^\s*(```|~~~)');

/// Collapses runs of citation tags that point at the same site into one tag
/// and drops tags with unknown ids. Fenced code is left alone.
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
    out.add(
      line.replaceAllMapped(_run, (m) {
        final kept = <String>[];
        String? last;
        for (final t in _tag.allMatches(m[0]!)) {
          final c = byId[t[1]];
          if (c == null) continue;
          final key = '${c.isKb}:${citeShortName(c)}';
          if (key == last) continue;
          last = key;
          kept.add('[${c.id}]');
        }
        return kept.join(' ');
      }),
    );
  }
  return out.join('\n');
}

/// Site logo, or a web / knowledge icon when it cannot load.
class SiteFavicon extends StatelessWidget {
  const SiteFavicon({super.key, required this.citation, required this.size});

  final Citation citation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final domain = citeDomain(citation);
    final fallback = AppIcon(
      citation.isKb ? AppIcons.knowledge : AppIcons.web,
      size: size,
      color: p.textTertiary,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox.square(
        dimension: size,
        child: domain.isEmpty
            ? fallback
            : Image.network(
                AppConfig.faviconUrl(domain),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Compact inline pill: favicon + short site name. Tap opens the link,
/// long-press copies it.
class CitationChip extends StatelessWidget {
  const CitationChip({super.key, required this.citation, required this.onTap});

  final Citation citation;
  final VoidCallback onTap;

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: () => _copy(context),
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
                  SiteFavicon(citation: citation, size: MdSizes.citeFavicon),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
