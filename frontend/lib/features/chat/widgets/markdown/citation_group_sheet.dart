import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../data/chat_event.dart';
import 'citation_chip.dart';
import 'evidence_sheet.dart';

/// The sources behind one grouped chip (`github +2`): a row each with logo,
/// name, title and domain. Tapping a row opens that source's sheet.
Future<void> showCitationGroupSheet(
  BuildContext context,
  List<Citation> group,
  List<Evidence> evidence,
) {
  Haptics.tap();
  final p = context.palette;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.85,
        ),
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
              child: Text(AppStrings.sources, style: sheet.text.caption),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in group)
                    InkWell(
                      onTap: () {
                        Navigator.pop(sheet);
                        showEvidenceSheet(context, c, evidence);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding,
                          vertical: AppSpacing.md,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SiteFavicon(
                              citation: c,
                              size: AppSizes.sourceCardFavicon,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    citeShortName(c),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sheet.text.label,
                                  ),
                                  Text(
                                    c.title.isEmpty ? c.url : c.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: sheet.text.bodySmall,
                                  ),
                                  if (citeDomain(c).isNotEmpty)
                                    Text(
                                      citeDomain(c),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: sheet.text.caption,
                                    ),
                                ],
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
    ),
  );
}
