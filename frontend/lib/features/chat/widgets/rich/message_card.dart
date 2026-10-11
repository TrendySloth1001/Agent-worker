import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/rich_cards.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../markdown/inline_icon.dart';
import 'rich_frame.dart';
import 'rich_parsers.dart';

/// ```message block: platform header, recipient, text in a flat bubble.
class MessageCard extends StatelessWidget {
  const MessageCard({super.key, required this.draft});

  final MessageDraft draft;

  static final _phone = RegExp(r'^\+?[0-9][0-9 ()\-]{2,}$');

  Widget? _action() {
    final text = Uri.encodeComponent(draft.text);
    switch (draft.platform) {
      case RichPlatforms.sms:
        final to = _phone.hasMatch(draft.to)
            ? draft.to.replaceAll(RegExp(r'[ ()\-]'), '')
            : '';
        return RichAction.open(
          icon: RichIcons.send,
          label: RichStrings.sendSms,
          uri: Uri.parse('${RichLinks.sms}:$to?body=$text'),
        );
      case RichPlatforms.whatsapp:
        return RichAction.open(
          icon: RichIcons.send,
          label: RichStrings.sendWhatsapp,
          uri: Uri.parse('${RichLinks.whatsapp}?${RichLinks.textParam}=$text'),
        );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final brand = RichPlatforms.brandIcons[draft.platform];
    final name = RichPlatforms.names[draft.platform] ?? RichStrings.message;
    final Widget leading = brand != null
        ? InlineIcon(set: brand.$1, name: brand.$2, size: RichSizes.brandIcon)
        : AppIcon(
            draft.platform == RichPlatforms.sms
                ? RichIcons.sms
                : RichIcons.chat,
            size: AppIconSize.sm,
            color: p.textTertiary,
          );
    final send = _action();
    return RichCard(
      title: name,
      leading: leading,
      actions: [
        RichAction.copy(text: draft.text),
        ?send,
      ],
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (draft.to.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Text(RichStrings.to, style: t.caption),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        draft.to,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption.copyWith(color: p.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: p.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: p.border, width: AppBorder.thin),
              ),
              child: SelectableText(
                draft.text,
                style: t.bodySmall.copyWith(color: p.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
