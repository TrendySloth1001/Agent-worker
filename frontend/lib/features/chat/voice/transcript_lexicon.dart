/// Word lists for the on-device transcript pass (transcript_normalizer.dart).
/// Kept conservative: every entry must be safe without context.
abstract final class Lexicon {
  /// Said aloud, typed as punctuation. Longest phrases first.
  static const spokenPunctuation = <String, String>{
    'new paragraph': '\n\n',
    'next paragraph': '\n\n',
    'new line': '\n',
    'next line': '\n',
    'question mark': '?',
    'exclamation mark': '!',
    'exclamation point': '!',
    'full stop': '.',
    'fullstop': '.',
    'semicolon': ';',
    'semi colon': ';',
    'comma': ',',
    'पूर्ण विराम': '।',
    'पूर्णविराम': '।',
    'अल्पविराम': ',',
    'अल्प विराम': ',',
    'प्रश्नचिह्न': '?',
    'प्रश्न चिह्न': '?',
    'नई लाइन': '\n',
  };

  /// "period" is punctuation only as the last word ("trial period" stays).
  static const finalOnlyPunctuation = <String, String>{'period': '.'};

  /// Always noise in dictation.
  static const fillers = {
    'um', 'umm', 'ummm', 'uh', 'uhh', 'uhm', 'er', 'erm', 'hmm', 'hmmm', //
    'mm', 'mmm', 'ah', 'ahh', 'उम', 'अं',
  };

  /// "matlab" opening a sentence is a filler unless a question about meaning follows.
  static const matlabKeepBefore = {
    'kya',
    'ki',
    'ke',
    'ka',
    'hai',
    'yeh',
    'ye',
    'nahi',
    'samjhe',
    'samjha',
  };

  /// After "so"/"and"/"but", "like" before these is a filler ("so like we can").
  static const likeFillerBefore = {
    'i', 'we', 'you', 'he', 'she', 'they', 'it', 'the', 'this', 'that', //
    'um', 'uh', 'can', 'could', 'should', 'maybe', 'just', 'basically',
  };
  static const likeFillerAfter = {'so', 'and', 'but', 'um', 'uh'};

  /// Doubled by a stutter, never on purpose ("the the", "I I").
  static const stutterWords = {
    'the', 'a', 'an', 'i', 'to', 'and', 'is', 'it', 'we', 'you', 'of', //
    'in', 'on', 'for', 'my', 'so', 'but', 'this', 'can', 'what', 'with',
    'are', 'was', 'be', 'at', 'me', 'mujhe', 'main', 'hum', 'aap', 'tum',
  };

  /// Misheard or split words, by lowercase phrase. Longest first.
  static const phrases = <String, String>{
    'java script': 'JavaScript',
    'type script': 'TypeScript',
    'git hub': 'GitHub',
    'git lab': 'GitLab',
    'you tube': 'YouTube',
    'whats app': 'WhatsApp',
    "what's app": 'WhatsApp',
    'linked in': 'LinkedIn',
    'chat gpt': 'ChatGPT',
    'chat gbt': 'ChatGPT',
    'chat g p t': 'ChatGPT',
    'open ai': 'OpenAI',
    'data base': 'database',
    'e mail': 'email',
    'web site': 'website',
    'wi fi': 'Wi-Fi',
    'wifi': 'Wi-Fi',
    'i phone': 'iPhone',
    'mac book': 'MacBook',
    'post gres': 'Postgres',
    'kuber netes': 'Kubernetes',
    'next js': 'Next.js',
    'node js': 'Node.js',
    'react js': 'React.js',
    'flutter fire': 'FlutterFire',
    'fire base': 'Firebase',
    'pie thon': 'Python',
    'with out': 'without',
    'some one': 'someone',
    'any one': 'anyone',
    'every one': 'everyone',
    'can not': 'cannot',
    'im': "I'm",
    'ive': "I've",
    'dont': "don't",
    'doesnt': "doesn't",
    'didnt': "didn't",
    'cant': "can't",
    'isnt': "isn't",
    'wasnt': "wasn't",
    'arent': "aren't",
    'couldnt': "couldn't",
    'shouldnt': "shouldn't",
    'wouldnt': "wouldn't",
    'thats': "that's",
    'whats': "what's",
  };

  /// Hinglish words the recognizer spells several ways: one spelling each.
  static const hinglish = <String, String>{
    'nhi': 'nahi',
    'nahin': 'nahi',
    'nahii': 'nahi',
    'kyaa': 'kya',
    'kia': 'kya',
    'kyu': 'kyun',
    'kyon': 'kyun',
    'kiun': 'kyun',
    'acha': 'accha',
    'achha': 'accha',
    'achchha': 'accha',
    'thik': 'theek',
    'bohot': 'bahut',
    'bahot': 'bahut',
    'bhot': 'bahut',
    'boht': 'bahut',
    'kese': 'kaise',
    'kaisay': 'kaise',
    'chaiye': 'chahiye',
    'chahie': 'chahiye',
    'matlb': 'matlab',
    'yar': 'yaar',
    'abi': 'abhi',
    'kuchh': 'kuch',
    'kch': 'kuch',
    'mko': 'mujhe',
    'muje': 'mujhe',
    'mujhko': 'mujhe',
    'krna': 'karna',
    'krke': 'karke',
    'kr': 'kar',
    'hy': 'hai',
  };

  /// Words that mark a transcript as Hinglish (romanized Hindi).
  static const hinglishMarkers = {
    'hai', 'hain', 'kya', 'nahi', 'mujhe', 'mera', 'meri', 'tum', 'aap', //
    'kar', 'karo', 'karna', 'bhai', 'yaar', 'kal', 'aaj', 'kaise', 'kyun',
    'accha', 'theek', 'bahut', 'chahiye', 'batao', 'bata', 'dena', 'hoga',
    'raha', 'rahi', 'rahe', 'gaya', 'gayi', 'tha', 'thi', 'abhi', 'kuch',
    'matlab', 'baje', 'aur', 'lekin', 'kyunki', 'wala', 'wali', 'hum',
  };

  /// Sentence openers that make it a question.
  static const questionStarts = {
    'what', 'why', 'how', 'when', 'where', 'who', 'whom', 'whose', 'which', //
    'can', 'could', 'would', 'should', 'will', 'shall', 'is', 'are', 'was',
    'were', 'do', 'does', 'did', 'have', 'has', 'am', "what's", "where's",
    "who's", "how's", "isn't", "aren't", "don't", "doesn't", "didn't",
    "can't", "won't", "couldn't", "shouldn't", 'kya', 'kaise', 'kyun', 'kab',
    'kahan', 'kaun', 'kitna', 'kitne', 'kitni', 'kidhar', 'क्या', 'कैसे',
    'क्यों', 'कब', 'कहाँ', 'कौन', 'कितना', 'कितने',
  };

  /// Openers that ask only with a subject after them ("Do you", not "Do the dishes").
  static const doWords = {
    'do', 'does', 'did', "don't", "doesn't", "didn't", //
  };
  static const auxiliaries = {
    'can', 'could', 'would', 'should', 'will', 'shall', 'is', 'are', 'was', //
    'were', 'have', 'has', 'am', "isn't", "aren't", "can't", "won't",
    "couldn't", "shouldn't",
  };
  static const pronouns = {
    'i', 'you', 'we', 'they', 'he', 'she', 'it', 'there', 'u', 'people', //
    'anyone', 'someone', 'anybody', 'somebody', 'everyone',
  };
  static const determiners = {
    'the', 'this', 'that', 'these', 'those', 'my', 'your', 'our', 'their', //
    'his', 'her', 'its', 'a', 'an', 'any', 'all', 'some',
  };

  /// Question words that make a Hindi/Hinglish sentence a question anywhere.
  static const questionAnywhere = {
    'kya',
    'kaise',
    'kyun',
    'kab',
    'kahan',
    'kaun',
    'kitna',
    'kitne',
    'kitni', //
    'क्या', 'कैसे', 'क्यों', 'कब', 'कहाँ', 'कौन', 'कितना', 'कितने',
  };

  /// A pause after these is a hesitation, not the end of a thought.
  static const noBreakAfter = {
    'the', 'a', 'an', 'to', 'and', 'or', 'but', 'of', 'for', 'with', 'in', //
    'on', 'at', 'by', 'from', 'my', 'your', 'our', 'their', 'his', 'her',
    'is', 'are', 'was', 'were', 'be', 'i', 'we', 'you', 'that', 'this',
    'if', 'because', 'so', 'ki', 'ka', 'ke', 'ko', 'se', 'me', 'mein', 'aur',
    'ya', 'jo', 'ek', 'mujhe', 'main', 'agar', 'toh',
  };

  /// After a pause these continue the sentence: a comma, not a full stop.
  static const continuers = {
    'and', 'but', 'or', 'so', 'because', 'then', 'which', 'that', 'aur', //
    'lekin', 'par', 'toh', 'kyunki', 'phir', 'ki',
  };

  static const months = {
    'january': 'January', 'february': 'February', 'march': 'March', //
    'april': 'April', 'may': 'May', 'june': 'June', 'july': 'July',
    'august': 'August', 'september': 'September', 'october': 'October',
    'november': 'November', 'december': 'December',
  };

  static const weekdays = {
    'monday': 'Monday', 'tuesday': 'Tuesday', 'wednesday': 'Wednesday', //
    'thursday': 'Thursday', 'friday': 'Friday', 'saturday': 'Saturday',
    'sunday': 'Sunday',
  };

  static const units = {
    'zero': 0, 'oh': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, //
    'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19,
  };

  static const tens = {
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fourty': 40, 'fifty': 50, //
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  static const scales = {
    'hundred': 100, 'thousand': 1000, 'lakh': 100000, 'lakhs': 100000, //
    'million': 1000000, 'crore': 10000000, 'crores': 10000000,
    'billion': 1000000000,
  };

  static const ordinals = {
    'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, //
    'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10,
    'eleventh': 11, 'twelfth': 12, 'thirteenth': 13, 'fourteenth': 14,
    'fifteenth': 15, 'sixteenth': 16, 'seventeenth': 17, 'eighteenth': 18,
    'nineteenth': 19, 'twentieth': 20, 'thirtieth': 30,
  };

  /// Romanized Hindi numbers, converted only before a unit ("do baje").
  static const hindiNumbers = {
    'ek': 1, 'do': 2, 'teen': 3, 'char': 4, 'chaar': 4, 'paanch': 5, //
    'panch': 5, 'chhe': 6, 'chhah': 6, 'saat': 7, 'aath': 8, 'nau': 9,
    'das': 10, 'gyarah': 11, 'barah': 12, 'baarah': 12, 'pandrah': 15,
    'bees': 20, 'tees': 30, 'pachas': 50, 'sau': 100,
  };
  static const hindiUnits = {
    'baje', 'bje', 'minute', 'minat', 'ghante', 'ghanta', 'din', 'saal', //
    'mahine', 'hafte', 'rupaye', 'rupay', 'rupees', 'hazaar', 'hazar', 'log',
    'baar',
  };

  /// Words after a number that make it a quantity (written in digits).
  static const quantityUnits = {
    'percent', 'per', 'minutes', 'minute', 'mins', 'min', 'hours', 'hour', //
    'hrs', 'seconds', 'second', 'secs', 'days', 'day', 'weeks', 'week',
    'months', 'month', 'years', 'year', 'kg', 'kgs', 'km', 'kms', 'gb', 'mb',
    'tb', 'kb', 'times', 'people', 'items', 'pages', 'lines', 'words',
    'steps', 'o\'clock', 'oclock', 'baje', 'am', 'pm', 'a.m.', 'p.m.',
    'dollars', 'dollar', 'bucks', 'rupees', 'rupee', 'rs', 'rupaye',
    'euros', 'euro', 'k', 'x',
  };

  static const currencies = {
    'dollars': r'$', 'dollar': r'$', 'rupees': '₹', 'rupee': '₹', //
    'rs': '₹', 'euros': '€', 'euro': '€',
  };
}
