import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/kb_source.dart';
import '../../chat/widgets/markdown/inline_icon.dart';
import '../../apps/apps_registry.dart';
import '../../connectors/connector_brand.dart';

/// The leading tile of a source row: a 40dp rounded tonal square holding the
/// source's stored icon (site favicon, GitHub owner avatar). While it loads, or
/// when it is missing or broken, a monogram of the title stands in; sources
/// without a remote icon (notes, docs, uploaded files) show their type icon.
class SourceIcon extends StatelessWidget {
  const SourceIcon({super.key, required this.source, this.imageFor});

  final KbSource source;

  /// Test seam: how a stored icon URL becomes an image. Defaults to the network
  /// (Flutter's image cache keeps decoded icons across rebuilds).
  final ImageProvider Function(String url)? imageFor;

  bool get _local => const {'note', 'doc', 'file'}.contains(source.type);

  /// Connected-app items show the app's brand mark.
  AppBrand? get _brand => ConnectorBrand.forSourceType(source.type);

  String get _name {
    final t = source.title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    return source.uri.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = AppIcon(
      source.type == 'file'
          ? AppIcons.fileKind(source.title)
          : AppIcons.sourceKind(source.type),
      size: KnowledgeSizes.iconGlyph,
      color: scheme.onSurfaceVariant,
    );
    final monogram = _Monogram(_name);
    final url = source.iconUrl;
    final Widget content;
    final brand = _brand;
    if (brand != null) {
      content = Center(
        child: InlineIcon(
          set: brand.set,
          name: brand.name,
          size: KnowledgeSizes.iconGlyph,
          color: scheme.onSurface,
          fallback: AppIcon(
            brand.fallback,
            size: KnowledgeSizes.iconGlyph,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    } else if (_local) {
      content = Center(child: glyph);
    } else if (url == null || url.isEmpty) {
      content = monogram;
    } else {
      content = Padding(
        padding: const EdgeInsets.all(KnowledgeSizes.iconInset),
        child: Image(
          image: (imageFor ?? NetworkImage.new)(url),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          frameBuilder: (_, child, frame, sync) =>
              sync || frame != null ? child : monogram,
          errorBuilder: (_, _, _) => monogram,
        ),
      );
    }
    return Container(
      width: KnowledgeSizes.iconTile,
      height: KnowledgeSizes.iconTile,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(KnowledgeSizes.iconTileRadius),
      ),
      child: content,
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Center(
      child: Text(
        letter,
        key: const ValueKey('source-monogram'),
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}
