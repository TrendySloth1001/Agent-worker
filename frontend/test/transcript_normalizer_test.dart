import 'package:app/features/chat/voice/transcript_normalizer.dart';
import 'package:app/features/chat/voice/word_diff.dart';
import 'package:flutter_test/flutter_test.dart';

const _vocab = ['Nikhil', 'Nick', 'Agent-worker', 'keepit'];

/// (heard, expected) — the local pass with no pauses.
const _cases = <(String, String)>[
  // Capitals and end punctuation.
  ('hello how are you doing today', 'Hello how are you doing today.'),
  ('what is the weather in pune', 'What is the weather in pune?'),
  ('can you summarize this article', 'Can you summarize this article?'),
  ('open settings', 'Open settings'),
  ('why', 'Why?'),
  ('i think i need a break', 'I think I need a break.'),
  ("i'm going to the office on monday", "I'm going to the office on Monday."),
  // Spoken punctuation.
  ('hi comma how are you question mark', 'Hi, how are you?'),
  ('done full stop thanks', 'Done. Thanks.'),
  ('first point new line second point', 'First point\nSecond point.'),
  ('that is amazing exclamation mark', 'That is amazing!'),
  ('send it period', 'Send it.'),
  ('the trial period ends soon', 'The trial period ends soon.'),
  ('note semicolon remember this', 'Note; remember this.'),
  // Fillers.
  ('um can you uh check the logs', 'Can you check the logs?'),
  ('so like we can ship it tomorrow', 'So we can ship it tomorrow.'),
  ('i like the new design', 'I like the new design.'),
  ('matlab mujhe kal tak chahiye', 'Mujhe kal tak chahiye.'),
  ('iska matlab kya hai', 'Iska matlab kya hai?'),
  // Stutters.
  ('the the build is broken', 'The build is broken.'),
  ('i i i want to go', 'I want to go.'),
  ('jaldi jaldi karo yaar', 'Jaldi jaldi karo yaar.'),
  ('bye bye see you', 'Bye bye see you.'),
  // Numbers, times, money, dates.
  ('book a table at five thirty pm', 'Book a table at 5:30 PM.'),
  ('wake me at seven am', 'Wake me at 7 AM.'),
  ('remind me at 5 p.m. tomorrow', 'Remind me at 5 PM tomorrow.'),
  ('it costs fifty dollars', r'It costs $50.'),
  ('send five hundred rupees to mom', 'Send ₹500 to mom.'),
  ('battery is at twenty percent', 'Battery is at 20%.'),
  ('we need twenty five thousand users', 'We need 25,000 users.'),
  ('i have three hundred and twelve emails', 'I have 312 emails.'),
  ('give me five minutes', 'Give me 5 minutes.'),
  ('one of them is broken', 'One of them is broken.'),
  ('the meeting is on january fifth', 'The meeting is on January 5.'),
  ('my birthday is the twenty first of march', 'My birthday is the 21 March.'),
  ('you may want to restart it', 'You may want to restart it.'),
  ('the twentieth century was wild', 'The 20th century was wild.'),
  ('meeting at ten o clock', 'Meeting at 10 o clock.'),
  // Common mishearings.
  ('how do i learn java script', 'How do I learn JavaScript?'),
  ('push it to git hub please', 'Push it to GitHub please.'),
  (
    'check the data base with out locking',
    'Check the database without locking.',
  ),
  ('dont forget the wi fi password', "Don't forget the Wi-Fi password."),
  // Hinglish: kept, spelled one way, never translated.
  ('mujhe nhi pata yar', 'Mujhe nahi pata yaar.'),
  ('ye bohot acha hai', 'Ye bahut accha hai.'),
  ('kal do baje meeting hai', 'Kal 2 baje meeting hai.'),
  ('tum kese ho', 'Tum kaise ho?'),
  ('bhai ye kaam kab tak hoga', 'Bhai ye kaam kab tak hoga?'),
  ('do the dishes now', 'Do the dishes now.'),
  // Hindi.
  ('मुझे कल की मीटिंग के बारे में बताओ', 'मुझे कल की मीटिंग के बारे में बताओ।'),
  ('आप कैसे हैं', 'आप कैसे हैं?'),
  // The user's names and repositories.
  ('remind me to call nikil tomorrow', 'Remind me to call Nikhil tomorrow.'),
  ('nick here what is new', 'Nick here what is new.'),
  ('open the agent worker repo', 'Open the Agent-worker repo.'),
  ('the agent worker was slow', 'The agent worker was slow.'),
  ('star keepit for me', 'Star keepit for me.'),
  // Already clean text stays put.
  ('Already fine.', 'Already fine.'),
  ('iPhone sales are up', 'iPhone sales are up.'),
];

void main() {
  group('local pass', () {
    for (final (heard, want) in _cases) {
      test(heard, () {
        expect(normalizeTranscript(heard, vocab: _vocab).text, want);
      });
    }

    test('has at least 40 cases', () => expect(_cases.length, greaterThan(40)));

    test('pauses become commas and full stops', () {
      // "the build failed | can you check | and fix it"
      const heard = 'the build failed can you check and fix it';
      expect(
        normalizeTranscript(heard, pauses: {2, 5}).text,
        'The build failed. Can you check, and fix it?',
      );
    });

    test('a pause after a function word is a hesitation', () {
      expect(
        normalizeTranscript('i want to go home now', pauses: {2}).text,
        'I want to go home now.',
      );
    });

    test('exact mode keeps every word', () {
      final out = normalizeTranscript(
        'um so like the the price is fifty dollars comma ok',
        exact: true,
      );
      expect(out.text, 'Um so like the the price is fifty dollars, ok.');
      expect(out.edits, 0);
    });

    test('confidence: short and sure results skip the model', () {
      expect(
        normalizeTranscript('turn on the lights', confidence: 0.99).confident,
        isTrue,
      );
      expect(
        normalizeTranscript('turn on the lights', confidence: 0.8).confident,
        isFalse,
      );
      expect(normalizeTranscript('turn on the lights').confident, isFalse);
    });

    test('counts word edits, not punctuation', () {
      expect(normalizeTranscript('hello there friend').edits, 0);
      expect(normalizeTranscript('um hello there friend').edits, 1);
      expect(normalizeTranscript('mujhe nhi pata yar').edits, 2);
      expect(normalizeTranscript('mujhe nhi pata').hinglish, isTrue);
    });
  });

  group('word diff', () {
    test('marks replaced words in the fixed text', () {
      const fixed = 'Call Nikhil at 5 PM.';
      final d = diffWords('call nikil at five pm', fixed);
      expect(d.edits, 2);
      expect(d.changed.map((r) => r.textInside(fixed)).toList(), [
        'Nikhil',
        '5',
      ]);
    });

    test('joins a phrase and counts removals', () {
      const fixed = 'learn JavaScript today';
      final d = diffWords('um learn java script today', fixed);
      expect(d.changed.map((r) => r.textInside(fixed)), ['JavaScript']);
      expect(d.edits, 2);
    });

    test('case and punctuation are not changes', () {
      expect(diffWords('hello world', 'Hello, world!').edits, 0);
    });
  });
}
