import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/share_export.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/model_logo.dart';
import '../../../core/widgets/size_reporter.dart';
import '../../../data/chat_message.dart';
import '../chat_actions.dart';
import '../widgets/markdown/app_markdown.dart';
import '../widgets/source_chips.dart';
import 'chat_export.dart';
import 'share_sheet.dart';

enum _ReplyShare { image, markdown, text }

/// SHARE on a reply: as an image, as markdown on the clipboard, or as text.
/// [model] is the name shown above the reply.
Future<void> showReplyShare(
  BuildContext context, {
  required ChatMessage message,
  required String model,
}) async {
  final choice = await showShareSheet<_ReplyShare>(
    context,
    title: ShareStrings.shareTitle,
    options: const [
      (_ReplyShare.image, ShareIcons.image, ShareStrings.asImage),
      (_ReplyShare.markdown, ShareIcons.markdown, ShareStrings.copyMarkdown),
      (_ReplyShare.text, ShareIcons.text, ShareStrings.shareText),
    ],
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  void toast(String s) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s)));
  switch (choice) {
    case _ReplyShare.markdown:
      await Clipboard.setData(ClipboardData(text: replyMarkdown(message)));
      Haptics.received();
      toast(ShareStrings.copied);
    case _ReplyShare.text:
      await shareText(replyText(message));
    case _ReplyShare.image:
      toast(ShareStrings.rendering);
      final png = await _renderReply(context, message, model);
      messenger.hideCurrentSnackBar();
      if (png == null) {
        Haptics.error();
        toast(ShareStrings.imageFailed);
        return;
      }
      await shareBytes(
        png,
        name: '${ShareStrings.replyFile}.${ShareStrings.pngExtension}',
        mime: ShareStrings.pngMime,
      );
  }
}

/// Lays the reply out off screen at the device width, waits for it to
/// settle, and captures it as PNG bytes.
Future<Uint8List?> _renderReply(
  BuildContext context,
  ChatMessage message,
  String model,
) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final media = MediaQuery.of(context);
  final width = media.size.width;
  final ratio = media.devicePixelRatio.clamp(1.0, ShareSizes.imagePixelRatio);
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Off to the left: laid out and painted, never seen.
      left: -width * 2,
      top: 0,
      width: width,
      child: IgnorePointer(
        child: RepaintBoundary(
          key: key,
          child: _ShareCard(message: message, model: model),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await Future<void>.delayed(ShareSizes.settle);
    await WidgetsBinding.instance.endOfFrame;
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    entry.remove();
  }
}

/// The reply as it reads in the chat, on the app background, with a small
/// footer. Very long replies are cut off with a fade.
class _ShareCard extends StatefulWidget {
  const _ShareCard({required this.message, required this.model});

  final ChatMessage message;
  final String model;

  @override
  State<_ShareCard> createState() => _ShareCardState();
}

class _ShareCardState extends State<_ShareCard> {
  bool _clipped = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final m = widget.message;
    final body = ReplyScope(
      message: m,
      child: AppMarkdown(
        data: m.content,
        citations: m.citations,
        evidence: m.evidence,
        streaming: false,
      ),
    );
    return Material(
      color: p.background,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (m.modelId == null)
                  Container(
                    width: AppSizes.dot,
                    height: AppSizes.dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.textPrimary,
                    ),
                  )
                else
                  ModelLogo(m.modelId, size: AppSizes.modelLabelLogo),
                const SizedBox(width: AppSpacing.sm),
                Text(widget.model.toUpperCase(), style: t.caption),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: ShareSizes.imageMaxHeight,
              ),
              child: ClipRect(
                child: Stack(
                  children: [
                    OverflowBox(
                      fit: OverflowBoxFit.deferToChild,
                      alignment: Alignment.topCenter,
                      maxHeight: double.infinity,
                      child: SizeReporter(
                        onSize: (size) {
                          final clipped =
                              size.height > ShareSizes.imageMaxHeight;
                          if (clipped != _clipped && mounted) {
                            setState(() => _clipped = clipped);
                          }
                        },
                        child: body,
                      ),
                    ),
                    if (_clipped)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: ShareSizes.imageFade,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                p.background.withValues(alpha: 0),
                                p.background,
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_clipped) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(ShareStrings.continues, style: t.caption),
            ],
            if (m.citations.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              SourceChips(citations: m.citations, used: m.usedIds),
            ],
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: p.border, width: AppBorder.thin),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: AppSizes.dot,
                    height: AppSizes.dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(AppStrings.appName.toUpperCase(), style: t.caption),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      widget.model.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
