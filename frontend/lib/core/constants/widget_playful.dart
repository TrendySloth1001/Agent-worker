import 'package:hugeicons/hugeicons.dart';

/// Strings, sizes, durations, limits and icons for the playful widgets
/// (quiz, flashcards, calc, timeline, stats, checklist).
abstract final class PlayfulStrings {
  // Shared
  static const next = 'NEXT';
  static const prev = 'PREV';
  static const reset = 'RESET';
  static const restart = 'RESTART';
  static const retry = 'RETRY';
  static const sent = 'SENT';
  static const copyResults = 'COPY RESULTS';

  // Quiz
  static const quizUntitled = 'Quiz';
  static const results = 'RESULTS';
  static String question(int n, int total) => 'Q $n/$total';
  static String streak(int n) => 'STREAK $n';
  static const correct = 'CORRECT';
  static const wrong = 'NOT QUITE';
  static const askHarder = 'ASK FOR HARDER';
  static const sendScore = 'SEND SCORE';
  static String harderPrompt(String title) => 'Give me a harder quiz on $title';
  static String scorePrompt(int score, int total, String title) =>
      'I scored $score/$total on $title';
  static String bestStreak(int n) => 'BEST STREAK $n';
  static const ratings = <(double, String)>[
    (1.0, 'PERFECT'),
    (0.8, 'GREAT'),
    (0.6, 'GOOD'),
    (0.4, 'NOT BAD'),
    (0.0, 'KEEP GOING'),
  ];

  // Flashcards
  static const flashUntitled = 'Flashcards';
  static const knewIt = 'KNEW IT';
  static const again = 'AGAIN';
  static const shuffle = 'SHUFFLE';
  static const studyAgain = 'STUDY AGAIN CARDS ONLY';
  static const tapToFlip = 'TAP TO FLIP';
  static const known = 'KNOWN';
  static const againCount = 'AGAIN';
  static const done = 'DECK DONE';

  // Calc
  static const calcUntitled = 'Calculator';
  static const dash = '—';
  static const editValue = 'SET VALUE';
  static const ok = 'OK';
  static const cancel = 'CANCEL';

  // Timeline
  static const timelineUntitled = 'Timeline';
  static const expandAll = 'EXPAND ALL';
  static const collapseAll = 'COLLAPSE';

  // Stats
  static const statsUntitled = 'Stats';
  static const sparkMin = 'MIN';
  static const sparkMax = 'MAX';
  static const sparkFirst = 'START';
  static const sparkLast = 'NOW';

  // Checklist
  static const checklistUntitled = 'Checklist';
  static const allDone = 'ALL DONE';
  static const sendProgress = 'SEND PROGRESS';
  static String progressPrompt(String title, List<String> left, int total) =>
      left.isEmpty
      ? 'Finished all $total items on "$title".'
      : 'Progress on "$title": ${total - left.length}/$total done. '
            'Still to do: ${left.join(', ')}.';
}

abstract final class PlayfulLimits {
  static const quizQuestions = 12;
  static const quizOptions = 6;
  static const cards = 40;
  static const calcInputs = 8;
  static const calcOutputs = 8;
  static const events = 30;
  static const tiles = 8;
  static const checklistItems = 40;
  static const sparkPoints = 40;
  static const exprMaxLength = 400;
  static const exprMaxDepth = 40;
}

abstract final class PlayfulSizes {
  static const pad = 12.0;
  static const tileMinHeight = 44.0;
  static const barHeight = 2.0;
  static const markSize = 20.0;
  static const scoreFont = 56.0;
  static const bigNumberFont = 30.0;
  static const smallNumberFont = 20.0;
  static const cardHeight = 176.0;
  static const cardFont = 22.0;
  static const flipPerspective = 0.0012;
  static const swipeVelocity = 250.0;
  static const railWidth = 24.0;
  static const dot = 9.0;
  static const timelineWhenWidth = 64.0;
  static const sparkHeight = 22.0;
  static const sparkBigHeight = 72.0;
  static const sparkStroke = 1.5;
  static const sparkDot = 3.0;
  static const statTileMinHeight = 84.0;
  static const statGap = 8.0;
  static const sliderTrack = 2.0;
  static const sliderThumb = 7.0;
  static const sliderOverlay = 14.0;
  static const inputMaxLength = 14;
  static const flashAlpha = 0.12;
  static const btnHeight = 36.0;
  static const checkBox = 18.0;
  static const dimAlpha = 0.6;
  static const sparkWidth = 44.0;
  static const cardTextMax = 280.0;
}

abstract final class PlayfulDurations {
  static const flip = Duration(milliseconds: 380);
  static const swap = Duration(milliseconds: 220);
  static const expand = Duration(milliseconds: 200);
  static const flash = Duration(milliseconds: 700);
  static const bar = Duration(milliseconds: 250);
}

abstract final class PlayfulIcons {
  static const check = HugeIcons.strokeRoundedTick02;
  static const cross = HugeIcons.strokeRoundedCancel01;
  static const next = HugeIcons.strokeRoundedArrowRight01;
  static const prev = HugeIcons.strokeRoundedArrowLeft01;
  static const shuffle = HugeIcons.strokeRoundedShuffle;
  static const restart = HugeIcons.strokeRoundedRefresh;
  static const streak = HugeIcons.strokeRoundedFire;
  static const up = HugeIcons.strokeRoundedArrowUpRight01;
  static const down = HugeIcons.strokeRoundedArrowDownRight01;
  static const expand = HugeIcons.strokeRoundedArrowDown01;
  static const collapse = HugeIcons.strokeRoundedArrowUp01;
  static const send = HugeIcons.strokeRoundedSend;
  static const copy = HugeIcons.strokeRoundedCopy01;
  static const reset = HugeIcons.strokeRoundedUndo;
}
