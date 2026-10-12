// Does the message refer to an earlier conversation ("did we talk about...",
// "last time", "remember when", Hinglish "pehle humne...")? Pure regexes, so it
// costs nothing and runs before any model call.

export type PastReference = {
  /** The user is explicitly asking about earlier chats: always search them. */
  explicit: boolean;
  /** What they ask about, with the cue phrase removed ("" when only a cue was given). */
  topic: string;
  /** The cue that matched. */
  cue: string;
};

const NONE: PastReference = { explicit: false, topic: "", cue: "" };

// Boundaries that also work next to Devanagari.
const B = String.raw`(?<![\p{L}\p{N}_])`;
const E = String.raw`(?![\p{L}\p{N}_])`;
const rx = (src: string) => new RegExp(`${B}(?:${src})${E}`, "iu");

const TALK = String.raw`(?:talk(?:ed)?|chat(?:ted)?|discuss(?:ed)?|speak|spoke|spoken|go(?:ne)? over|cover(?:ed)?|mention(?:ed)?|brainstorm(?:ed)?|work(?:ed)? on)`;
const PAST_CHAT = String.raw`(?:previous|earlier|prior|past|old|last|other|older)\s+(?:chats?|conversations?|convos?|threads?|sessions?|discussions?)`;

const ENGLISH: RegExp[] = [
  rx(String.raw`(?:did|have|had|do|didn't|haven't)\s+(?:we|i|you and i)\s+(?:ever\s+|already\s+|previously\s+|once\s+)?${TALK}`),
  rx(String.raw`(?:did|have)\s+(?:i|we)\s+(?:ever\s+|already\s+)?(?:ask(?:ed)?|tell|told|show(?:ed)?)\s+(?:you\s+)?(?:about|this|that|something)`),
  rx(String.raw`(?:last|previous|prior)\s+time\s+(?:we|you|i)`),
  rx(String.raw`(?:remember|recall)\s+(?:when|what\s+we|what\s+you\s+(?:said|told)|our|that\s+time|the\s+time|the\s+(?:chat|conversation))`),
  rx(String.raw`do\s+you\s+(?:remember|recall)\s+(?:our|we|when|what|the\s+(?:chat|conversation|time))`),
  rx(String.raw`as\s+(?:we|you|i)\s+(?:discussed|talked|said|mentioned|agreed|decided|covered|went over)`),
  rx(String.raw`(?:earlier|before|previously|yesterday|last (?:week|month|night))\s+(?:you|we|i)\s+(?:said|told|mentioned|suggested|recommended|showed|discussed|talked|decided|agreed|wrote)`),
  rx(String.raw`you\s+(?:said|told me|mentioned|suggested|recommended)\s+(?:earlier|before|previously|yesterday|last\s+\w+|in\s+(?:our|a|another)\s+(?:previous\s+|earlier\s+)?(?:chat|conversation))`),
  rx(String.raw`(?:i|we)\s+(?:talked|spoke|chatted|discussed|asked you|told you)\s+(?:about\s+)?[^.?!\n]{0,60}?\b(?:before|earlier|previously|yesterday|last\s+(?:week|month|time|night)|the other day)`),
  rx(String.raw`(?:my|our)\s+${PAST_CHAT}`),
  rx(String.raw`(?:in|from)\s+(?:a|an|our|my|the)\s+${PAST_CHAT}`),
  rx(String.raw`(?:pick|picking)\s+up\s+where\s+we\s+left\s+off`),
  rx(String.raw`(?:continue|resume)\s+(?:from\s+)?(?:our|where we)\s+(?:last|previous|earlier|old)\b`),
  rx(String.raw`(?:search|look|check)\s+(?:through\s+|in\s+)?(?:my|our)\s+(?:past\s+|old\s+|previous\s+)?(?:chats?|conversations?|history)`),
];

// Hinglish (Roman Hindi) and Devanagari.
const HINGLISH: RegExp[] = [
  rx(String.raw`(?:pehle|pahle|pichli\s+baar|pichle\s+baar|kabhi)\s+(?:humne|hamne|maine|tumne|aapne|hum\s+ne|mene)`),
  rx(String.raw`(?:humne|hamne|hum|maine|mene)\s+(?:pehle|pahle|kal|pichli\s+baar)\s+[^.?!\n]{0,40}?(?:baat|chat|discuss|bataya|kaha|poocha|pucha|puchha)`),
  rx(String.raw`(?:humne|hamne|hum\s+ne)\s+[^.?!\n]{0,50}?(?:baat\s+ki|discuss\s+kiya|chat\s+ki|baat\s+hui)`),
  rx(String.raw`(?:tumne|aapne|tune|aap\s+ne|tu\s+ne)\s+(?:pehle\s+|pahle\s+|kal\s+|pichli\s+baar\s+)?(?:kaha|bataya|bola|bataaya|suggest\s+kiya|btaya)\s+tha`),
  rx(String.raw`(?:pichl[ei]|purani|puraani|pehl[ei]|hamari|hamare|humari)\s+(?:chat|conversation|baat\s*cheet|baatcheet|baat)`),
  rx(String.raw`(?:yaad\s+hai|yaad\s+he|yad\s+hai)\s+(?:jab|humne|hamne|kal|pehle|woh|wo|vo)`),
  /(?:पहले|पिछली\s+बार)\s+(?:हमने|मैंने|तुमने|आपने)|(?:हमारी|पिछली)\s+(?:बातचीत|चैट)/u,
];

/** Words stripped from the front of the topic after removing the cue. */
const TOPIC_NOISE = /^(?:about|on|regarding|re|that|the|a|an|my|our|with|to|of|for|is|was|were|are|kya|ki|ke|ka|ko|baare\s+mein|bare\s+mein|ke\s+baare\s+mein|me|mein|and)\s+/iu;

function topicOf(text: string, cue: string): string {
  let rest = text.replace(cue, " ").replace(/[?!.,;:]+/g, " ").replace(/\s+/g, " ").trim();
  // Leading chatter ("hey, so", "wait,").
  rest = rest.replace(/^(?:hey|hi|hello|ok(?:ay)?|so|wait|btw|also|and|but|please|pls|yaar|bhai)\s+/iu, "");
  for (let i = 0; i < 3; i++) rest = rest.replace(TOPIC_NOISE, "");
  rest = rest.replace(/\s+(?:before|earlier|previously|pehle|yesterday|kal)$/iu, "").trim();
  return rest.slice(0, 200);
}

/** Whether [text] points at an earlier chat, and what it is about. */
export function detectPastReference(text: string): PastReference {
  const t = text.trim();
  if (t.length < 6 || t.length > 1500) return NONE;
  for (const re of [...ENGLISH, ...HINGLISH]) {
    const m = re.exec(t);
    if (m) return { explicit: true, cue: m[0], topic: topicOf(t, m[0]) };
  }
  return NONE;
}
