import 'package:flutter/painting.dart';

import '../../core/constants/app_fonts.dart';
import '../../core/constants/docs.dart';
import '../../core/theme/app_text_styles.dart';

/// Secondary text of the reader: Space Grotesk, sentence case, no tracking.
/// Replaces the mono caption for labels, meta lines and counts so the
/// reader chrome has no mono caps leftovers.
extension DocTextStyles on AppTextTheme {
  TextStyle get meta => caption.copyWith(
    fontFamily: AppFonts.body,
    fontSize: DocSizes.metaSize,
    letterSpacing: 0,
    height: 1.35,
  );
}
