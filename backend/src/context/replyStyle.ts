/**
 * Small server post-passes that enforce reply rules the models keep breaking:
 *  - no emoji in Markdown headings or as decorative bullet markers (unless the user used emoji / asked for them)
 *  - an "ask" widget is never repeated, and never follows the user choosing "I'll type it" / "Other"
 */

const EMOJI = /(?![©®™])[\p{Extended_Pictographic}\u{1F1E6}-\u{1F1FF}]/gu;
const EMOJI_JUNK = /[️‍⃣]/g;
const HEADING_RE = /^(\s{0,3}#{1,6}\s+)(.*)$/;
const BULLET_EMOJI_RE = /^(\s*(?:[-*+]|\d+[.)])\s+)((?:(?:[\p{Extended_Pictographic}\u{1F1E6}-\u{1F1FF}][️‍⃣]*)\s*)+)(?=\S)/u;

/** The user used emoji or asked for them: leave the reply's emoji alone. */
export const userWantsEmoji = (userText: string): boolean => /\p{Extended_Pictographic}/u.test(userText) || /\bemojis?\b/i.test(userText);

/** [text] without emoji in headings and without emoji bullet markers; fenced blocks are untouched. */
export function stripDecorativeEmoji(text: string, userText = ""): string {
  if (userWantsEmoji(userText)) return text;
  let fence: string | null = null;
  return text
    .split("\n")
    .map((line) => {
      const f = /^\s*(`{3,}|~{3,})/.exec(line);
      if (fence) {
        if (f && f[1][0] === fence[0] && f[1].length >= fence.length) fence = null;
        return line;
      }
      if (f) {
        fence = f[1];
        return line;
      }
      const h = HEADING_RE.exec(line);
      if (h) {
        const body = h[2].replace(EMOJI, "").replace(EMOJI_JUNK, "").replace(/\s{2,}/g, " ").trim();
        return body ? `${h[1]}${body}` : null;
      }
      const b = BULLET_EMOJI_RE.exec(line);
      if (b) return line.replace(BULLET_EMOJI_RE, "$1").replace(EMOJI_JUNK, "");
      return line;
    })
    .filter((l): l is string => l !== null)
    .join("\n");
}

// ---- ask widgets -------------------------------------------------------------

const ASK_RE = /```ask[ \t]*\n([\s\S]*?)```/g;
/** The user picked the "type it myself" option (or "Other"). */
const TYPE_IT_RE = /^\s*(?:other|others|something else|somewhere else|custom|type (?:it|my own)|i(?:'|’)?ll type(?: it)?|none of (?:these|the above))\b/i;
const normalize = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();

export const questionOf = (askBody: string): string => normalize(/^\s*question:\s*(.+)$/im.exec(askBody)?.[1] ?? askBody.split("\n")[0] ?? "");

export const hasAsk = (text: string): boolean => /```ask[ \t]*\n/.test(text);

/** The user chose "I'll type it" / "Other": the next message is free text. */
export const choseTypeIt = (userText: string): boolean => userText.trim().length <= 60 && TYPE_IT_RE.test(userText);

export const TYPE_IT_REPLY = "Go ahead and type it below.";

/**
 * [text] without ask widgets that must not appear: right after the user chose "I'll type it" / "Other" (nothing is
 * asked again, we wait for their words), or when the previous assistant message asked the same question.
 */
export function guardAsk(text: string, o: { userText: string; prevAssistant?: string }): string {
  if (!hasAsk(text)) return text;
  const prevQuestions = new Set([...(o.prevAssistant ?? "").matchAll(ASK_RE)].map((m) => questionOf(m[1])).filter(Boolean));
  const typeIt = choseTypeIt(o.userText) && hasAsk(o.prevAssistant ?? "");
  let out = text.replace(ASK_RE, (whole, body: string) => (typeIt || prevQuestions.has(questionOf(body)) ? "" : whole));
  out = out.replace(/\n{3,}/g, "\n\n").trim();
  if (out === text.trim()) return text;
  return out || TYPE_IT_REPLY;
}
