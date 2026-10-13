/// Word banks and rules for the playful "thinking" line shown while a reply
/// has no specific phase to report. Lines are built (stem + "ing", with an
/// optional adverb or object), never a fixed list only. See `ThinkingWords`.
abstract final class ThinkingBank {
  /// The whole line, ellipsis included, never gets longer than this.
  static const maxLength = 22;
  static const ellipsis = '…';
  static const suffix = 'ing';

  /// The topic used when nothing in the prompt matches; always in the pool.
  static const general = 'general';

  /// Keyword prefixes per topic, matched against the words of the prompt.
  static const keywords = <String, List<String>>{
    'code': [
      'code',
      'bug',
      'function',
      'flutter',
      'dart',
      'python',
      'java',
      'script',
      'api',
      'error',
      'compile',
      'debug',
      'sql',
      'regex',
      'app',
      'class',
      'git',
      'html',
      'css',
      'react',
      'server',
    ],
    'math': [
      'math',
      'calcul',
      'equation',
      'solve',
      'number',
      'sum',
      'percent',
      'algebra',
      'integral',
      'derivative',
      'probab',
      'statistic',
      'average',
      'formula',
      'geometry',
    ],
    'travel': [
      'travel',
      'trip',
      'flight',
      'hotel',
      'visit',
      'itinerary',
      'tour',
      'vacation',
      'holiday',
      'train',
      'route',
      'city',
      'country',
      'beach',
    ],
    'food': [
      'recipe',
      'cook',
      'food',
      'eat',
      'dinner',
      'lunch',
      'breakfast',
      'bake',
      'meal',
      'ingredient',
      'restaurant',
      'diet',
      'snack',
      'curry',
    ],
    'writing': [
      'write',
      'essay',
      'email',
      'story',
      'poem',
      'letter',
      'draft',
      'summar',
      'rewrite',
      'blog',
      'caption',
      'article',
      'translate',
      'speech',
      'resume',
      'outline',
    ],
  };

  /// Verb stems, written so that stem + [suffix] is correct English
  /// ("Debugg" + "ing", "Rout" + "ing").
  static const stems = <String, List<String>>{
    'general': [
      'Ponder',
      'Untangl',
      'Mull',
      'Mus',
      'Weigh',
      'Connect',
      'Gather',
      'Sift',
      'Brew',
      'Chas',
      'Piec',
      'Hatch',
      'Simmer',
      'Ruminat',
      'Percolat',
      'Cogitat',
      'Daydream',
      'Wonder',
    ],
    'code': [
      'Debugg',
      'Compil',
      'Pars',
      'Refactor',
      'Trac',
      'Stitch',
      'Lint',
      'Hack',
      'Unravel',
      'Patch',
    ],
    'math': [
      'Crunch',
      'Comput',
      'Add',
      'Factor',
      'Deriv',
      'Graph',
      'Solv',
      'Estimat',
      'Tally',
    ],
    'travel': [
      'Mapp',
      'Rout',
      'Wander',
      'Scout',
      'Pack',
      'Chart',
      'Explor',
      'Navigat',
    ],
    'food': ['Season', 'Stirr', 'Whisk', 'Tast', 'Marinat', 'Sizzl', 'Simmer'],
    'writing': [
      'Draft',
      'Sketch',
      'Polish',
      'Phras',
      'Word',
      'Shap',
      'Edit',
      'Outlin',
    ],
  };

  /// Things the verb can act on, per topic ("Crunching numbers").
  static const objects = <String, List<String>>{
    'general': ['ideas', 'thoughts', 'it over', 'the angles', 'options'],
    'code': ['the logic', 'the stack', 'some code', 'the bits'],
    'math': ['numbers', 'the maths', 'the figures'],
    'travel': ['a route', 'the map', 'the options'],
    'food': ['a flavour', 'the recipe', 'ideas'],
    'writing': ['an outline', 'some words', 'a draft', 'the tone'],
  };

  /// Light adverbs that go in front of the verb ("Gently untangling").
  static const adverbs = [
    'Gently',
    'Carefully',
    'Quietly',
    'Happily',
    'Slowly',
    'Briefly',
    'Warmly',
    'Keenly',
  ];

  /// Short lines the generator may use as they are.
  static const fixed = ['Thinking', 'One moment', 'On it', 'Hmm'];
}
