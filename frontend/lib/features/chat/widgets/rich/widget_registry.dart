import 'package:flutter/widgets.dart';

import '../../../../core/constants/widget_kit.dart';
import 'ask_card.dart' show RichPlaceholder;
import 'calc_card.dart';
import 'chart_card.dart';
import 'checklist_card.dart';
import 'flashcards_card.dart';
import 'html_card.dart';
import 'quiz_card.dart';
import 'stats_card.dart';
import 'timeline_card.dart';

typedef RichWidgetFactory = Widget Function(String source);

class _Entry {
  const _Entry(this.label, this.build);
  final String label;
  final RichWidgetFactory build;
}

final Map<String, _Entry> _entries = {
  WidgetLang.chart: _Entry(WidgetKitStrings.chart, (s) => ChartCard(source: s)),
  WidgetLang.html: _Entry(WidgetKitStrings.html, (s) => HtmlCard(source: s)),
  WidgetLang.quiz: _Entry(WidgetKitStrings.quiz, (s) => QuizCard(source: s)),
  WidgetLang.flashcards: _Entry(
    WidgetKitStrings.flashcards,
    (s) => FlashcardsCard(source: s),
  ),
  WidgetLang.calc: _Entry(WidgetKitStrings.calc, (s) => CalcCard(source: s)),
  WidgetLang.timeline: _Entry(
    WidgetKitStrings.timeline,
    (s) => TimelineCard(source: s),
  ),
  WidgetLang.stats: _Entry(WidgetKitStrings.stats, (s) => StatsCard(source: s)),
  WidgetLang.checklist: _Entry(
    WidgetKitStrings.checklist,
    (s) => ChecklistCard(source: s),
  ),
};

/// Maps a fenced language to its rich widget, or null when [language] is not
/// a registry widget (caller falls back to the code block). While [streaming]
/// a lightweight placeholder is returned so partial sources never get parsed.
Widget? buildRichWidget(
  String language,
  String source, {
  required bool streaming,
}) {
  final entry = _entries[language];
  if (entry == null) return null;
  if (streaming) {
    return RichPlaceholder(label: WidgetKitStrings.preparing(entry.label));
  }
  return entry.build(source);
}
