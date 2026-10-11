/// Shared (scaffolding-only) constants for the registry widgets. Builders put
/// their own constants in their own `widget_<name>.dart` file instead.
abstract final class WidgetLang {
  static const chart = 'chart';
  static const html = 'html';
  static const quiz = 'quiz';
  static const flashcards = 'flashcards';
  static const calc = 'calc';
  static const timeline = 'timeline';
  static const stats = 'stats';
  static const checklist = 'checklist';
}

abstract final class WidgetKitStrings {
  static const chart = 'CHART';
  static const html = 'HTML';
  static const quiz = 'QUIZ';
  static const flashcards = 'FLASHCARDS';
  static const calc = 'CALCULATOR';
  static const timeline = 'TIMELINE';
  static const stats = 'STATS';
  static const checklist = 'CHECKLIST';

  /// Streaming placeholder, e.g. `PREPARING CHART…`.
  static String preparing(String name) => 'PREPARING $name…';
}
