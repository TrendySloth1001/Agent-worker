/**
 * Does this message ask for a precise fact about a named person, work, product,
 * place or event (who/when/how many/how much + a proper name or a number), or to
 * describe a named thing? Small free models answer those confidently from
 * memory and get them wrong or invent them, so in Auto the web is searched
 * (and the answer is generated at a lower temperature on a stronger model).
 * Cheap and local: no model call.
 */

/** A factual question word in English or Hinglish. */
const WH = /\b(who|whom|whose|when|which (year|date|day|month|country|city|state|team|company|person|author|book|film|movie)|what (year|date|day|time)|how (many|much|old|tall|long|far|big|large)|where (is|was|are|were|did|does|can i buy)|kab|kaun|kisne|kiska|kitn[aei]|kahan|konsa|kaun ?sa)\b/i;

/** Asks to describe or recall a specific named thing. */
const RECALL =
  /\b(tell me about|summari[sz]e (the )?(plot|book|novel|film|movie|paper|article)|plot of|what (is|was|are|were) (the )?(population|height|price|cost|capital|gdp|salary|net worth|release date|chipset|specs?|launch date)|(api|docs?|documentation|reference) (for|of)|what does the .{1,40} (flag|option|command|function|method|package|library) do|(explain|describe|define) the .{1,40} (theorem|law|principle|effect|paradox|conjecture|lemma|algorithm|doctrine)|biography|research .{0,20}known for|known for)\b/i;

/** Programming/how-to/conceptual asks that are not lookups. */
const NOT_LOOKUP = /\b(write|fix|debug|refactor|implement|translate|rewrite|proofread|brainstorm|poem|story|essay|code|function that|script|regex|my (code|app|file|data|resume|project)|explain (how|why|the concept)|how (do|does|to|can) (i|you|we)|step[- ]by[- ]step|difference between)\b/i;

/** A proper name or a quoted/hyphenated identifier somewhere after the first word. */
function hasNamedThing(q: string): boolean {
  const rest = q;
  if (/["'“‘][^"'”’]{3,60}["'”’]/.test(rest)) return true;
  // Two Capitalised words in a row, or one Capitalised word that is not a sentence-initial or common one.
  if (/\b[A-Z][a-zA-Z.-]{2,}\s+[A-Z][a-zA-Z.-]{2,}\b/.test(rest)) return true;
  const caps = rest.match(/\b[A-Z][a-zA-Z0-9-]{2,}\b/g) ?? [];
  return caps.some((w) => !COMMON_CAPS.has(w.toLowerCase()));
}

const COMMON_CAPS = new Set(["the", "this", "that", "what", "when", "where", "who", "which", "how", "why", "and", "for", "can", "does", "did", "was", "were", "are", "english", "hindi", "hinglish", "please", "tell", "give", "explain", "bhai", "yaar", "can", "could", "would", "will", "should", "is", "do", "has", "have", "name", "list", "show", "write", "find", "hey", "hello", "hi", "sorry", "also"]);

export function isFactualLookup(question: string): boolean {
  const q = question.trim();
  if (q.length < 10 || q.length > 400) return false;
  if (NOT_LOOKUP.test(q)) return false;
  if (RECALL.test(q)) return true;
  return WH.test(q) && (hasNamedThing(q) || /\b(1[0-9]|20)\d{2}\b/.test(q) || /\b(current|now|today|right now|at the moment|abhi|aaj)\b/i.test(q));
}
