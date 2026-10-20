import { z } from "zod";
import { readKeyed, splitLines, splitPipe, toNumber } from "../lib/text";

const text = (max: number) => z.string().trim().min(1).max(max);
const title = (fallback: string) => z.string().trim().max(120).default(fallback);

const quizSchema = z.object({
  title: title("Quiz"),
  questions: z
    .array(
      z.object({
        q: text(400),
        options: z.array(text(200)).min(2).max(6),
        answer: z.number().int().min(0),
        why: z.string().max(600),
      }),
    )
    .min(1)
    .max(12),
});
export type QuizData = z.infer<typeof quizSchema>;

export function parseQuiz(code: string): QuizData | null {
  let heading = "";
  const questions: Array<{ q: string; options: string[]; answer: number; why: string }> = [];
  let current: { q: string; options: string[]; answer: number; why: string } | null = null;
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    const question = readKeyed(line, "q");
    const option = readKeyed(line, "a");
    const why = readKeyed(line, "why");
    if (name !== null && !current) heading = name;
    else if (question !== null) {
      current = { q: question, options: [], answer: -1, why: "" };
      questions.push(current);
    } else if (option !== null && current) {
      const correct = option.startsWith("*");
      if (correct) current.answer = current.options.length;
      current.options.push(option.replace(/^\*\s*/, ""));
    } else if (why !== null && current) current.why = why;
  }
  const valid = questions.filter((item) => item.answer >= 0 && item.options.length >= 2);
  const result = quizSchema.safeParse({ title: heading || undefined, questions: valid });
  const ok = result.success && result.data.questions.every((q) => q.answer < q.options.length);
  return ok ? result.data : null;
}

const flashcardsSchema = z.object({
  title: title("Flashcards"),
  cards: z
    .array(z.object({ front: text(300), back: text(600) }))
    .min(1)
    .max(40),
});
export type FlashcardsData = z.infer<typeof flashcardsSchema>;

export function parseFlashcards(code: string): FlashcardsData | null {
  let heading = "";
  const cards: Array<{ front: string; back: string }> = [];
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    const card = readKeyed(line, "card");
    if (name !== null) heading = name;
    else if (card !== null) {
      const [front = "", ...back] = splitPipe(card);
      cards.push({ front, back: back.join(" | ") });
    }
  }
  const result = flashcardsSchema.safeParse({ title: heading || undefined, cards });
  return result.success ? result.data : null;
}

const calcSchema = z.object({
  title: title("Calculator"),
  inputs: z
    .array(
      z.object({
        id: z.string().regex(/^[a-z_][a-z0-9_]*$/i),
        label: text(80),
        value: z.number(),
        min: z.number(),
        max: z.number(),
        suffix: z.string().max(12),
      }),
    )
    .min(1)
    .max(8),
  outputs: z
    .array(
      z.object({
        label: text(80),
        expression: text(400),
        suffix: z.string().max(12),
        decimals: z.number().int().min(0).max(8),
      }),
    )
    .min(1)
    .max(8),
});
export type CalcData = z.infer<typeof calcSchema>;

export function parseCalc(code: string): CalcData | null {
  let heading = "";
  const inputs: unknown[] = [];
  const outputs: unknown[] = [];
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    const input = readKeyed(line, "input");
    const out = readKeyed(line, "out");
    if (name !== null) heading = name;
    else if (input !== null) {
      const [id = "", label = "", value = "", range = "", suffix = ""] = splitPipe(input);
      const [low, high] = range.split("..");
      const base = toNumber(value) ?? 0;
      const min = toNumber(low) ?? Math.min(0, base);
      const max = toNumber(high) ?? Math.max(100, base);
      inputs.push({ id, label, value: Math.min(Math.max(base, min), max), min, max, suffix });
    } else if (out !== null) {
      const [label = "", expression = "", suffix = "", decimals = ""] = splitPipe(out);
      outputs.push({ label, expression, suffix, decimals: Math.round(toNumber(decimals) ?? 2) });
    }
  }
  const result = calcSchema.safeParse({ title: heading || undefined, inputs, outputs });
  return result.success ? result.data : null;
}

const timelineSchema = z.object({
  title: title("Timeline"),
  events: z
    .array(z.object({ when: text(40), title: text(160), detail: z.string().max(600) }))
    .min(1)
    .max(30),
});
export type TimelineData = z.infer<typeof timelineSchema>;

export function parseTimeline(code: string): TimelineData | null {
  let heading = "";
  const events: unknown[] = [];
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    if (name !== null) heading = name;
    else if (line.includes("|")) {
      const [when = "", head = "", ...detail] = splitPipe(line);
      events.push({ when, title: head, detail: detail.join(" | ") });
    }
  }
  const result = timelineSchema.safeParse({ title: heading || undefined, events });
  return result.success ? result.data : null;
}

const statsSchema = z.object({
  title: title("Stats"),
  stats: z
    .array(
      z.object({
        label: text(60),
        value: text(40),
        delta: z.string().max(30),
        direction: z.enum(["up", "down", "flat"]),
        spark: z.array(z.number()).max(40),
      }),
    )
    .min(1)
    .max(8),
});
export type StatsData = z.infer<typeof statsSchema>;

export function parseStats(code: string): StatsData | null {
  let heading = "";
  const stats: Array<{
    label: string;
    value: string;
    delta: string;
    direction: string;
    spark: number[];
  }> = [];
  const sparks = new Map<string, number[]>();
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    const stat = readKeyed(line, "stat");
    const spark = readKeyed(line, "spark");
    if (name !== null) heading = name;
    else if (stat !== null) {
      const [label = "", value = "", delta = "", direction = ""] = splitPipe(stat);
      const lower = direction.toLowerCase();
      stats.push({
        label,
        value,
        delta,
        direction: lower === "up" || lower === "down" ? lower : "flat",
        spark: [],
      });
    } else if (spark !== null) {
      const [label = "", series = ""] = splitPipe(spark);
      const values = series
        .split(",")
        .map(toNumber)
        .filter((n): n is number => n !== null);
      sparks.set(label.toLowerCase(), values.slice(0, 40));
    }
  }
  for (const item of stats) item.spark = sparks.get(item.label.toLowerCase()) ?? [];
  const result = statsSchema.safeParse({ title: heading || undefined, stats });
  return result.success ? result.data : null;
}

const checklistSchema = z.object({
  title: title("Checklist"),
  items: z
    .array(z.object({ text: text(240), done: z.boolean() }))
    .min(1)
    .max(40),
});
export type ChecklistData = z.infer<typeof checklistSchema>;

export function parseChecklist(code: string): ChecklistData | null {
  let heading = "";
  const items: Array<{ text: string; done: boolean }> = [];
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    const item = /^\s*(?:[-*]\s*)?\[( |x|X)\]\s*(.+)$/.exec(line);
    if (name !== null) heading = name;
    else if (item)
      items.push({ text: (item[2] ?? "").trim(), done: item[1]?.toLowerCase() === "x" });
  }
  const result = checklistSchema.safeParse({ title: heading || undefined, items });
  return result.success ? result.data : null;
}
