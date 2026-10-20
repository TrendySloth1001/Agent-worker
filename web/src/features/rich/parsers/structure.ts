import { z } from "zod";
import { readKeyed, splitLines, splitPipe, toNumber } from "../lib/text";

const text = (max: number) => z.string().trim().min(1).max(max);

const compareSchema = z.object({
  title: z.string().max(120),
  options: z
    .array(
      z.object({
        name: text(80),
        tagline: z.string().max(160),
        pick: z.boolean(),
        pros: z.array(text(200)).max(6),
        cons: z.array(text(200)).max(6),
      }),
    )
    .min(1)
    .max(5),
});
export type CompareData = z.infer<typeof compareSchema>;

export function parseCompare(code: string): CompareData | null {
  let heading = "";
  const options: Array<{
    name: string;
    tagline: string;
    pick: boolean;
    pros: string[];
    cons: string[];
  }> = [];
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    const option = readKeyed(line, "option");
    const current = options[options.length - 1];
    if (option !== null) {
      const [label = "", tagline = "", pick = ""] = splitPipe(option);
      options.push({
        name: label,
        tagline,
        pick: pick.toLowerCase() === "pick",
        pros: [],
        cons: [],
      });
    } else if (name !== null && !current) heading = name;
    else if (current && /^\s*\+\s*\S/.test(line))
      current.pros.push(line.replace(/^\s*\+\s*/, "").trim());
    else if (current && /^\s*[-–]\s*\S/.test(line))
      current.cons.push(line.replace(/^\s*[-–]\s*/, "").trim());
  }
  const result = compareSchema.safeParse({
    title: heading,
    options: options.map((o) => ({ ...o, pros: o.pros.slice(0, 6), cons: o.cons.slice(0, 6) })),
  });
  return result.success ? result.data : null;
}

const progressSchema = z.object({
  title: z.string().max(120),
  rows: z
    .array(
      z.discriminatedUnion("kind", [
        z.object({
          kind: z.literal("bar"),
          label: text(80),
          value: z.number(),
          max: z.number().positive(),
          note: z.string().max(120),
        }),
        z.object({
          kind: z.literal("rating"),
          label: text(80),
          value: z.number().min(0),
          max: z.number().int().min(1).max(10),
        }),
      ]),
    )
    .min(1)
    .max(16),
});
export type ProgressData = z.infer<typeof progressSchema>;

export function parseProgress(code: string): ProgressData | null {
  let heading = "";
  const rows: unknown[] = [];
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    const bar = readKeyed(line, "bar");
    const rating = readKeyed(line, "rating");
    if (name !== null) heading = name;
    else if (bar !== null) {
      const [label = "", value = "", max = "", note = ""] = splitPipe(bar);
      rows.push({
        kind: "bar",
        label,
        value: toNumber(value) ?? 0,
        max: toNumber(max) ?? 100,
        note,
      });
    } else if (rating !== null) {
      const [label = "", value = "", max = ""] = splitPipe(rating);
      rows.push({
        kind: "rating",
        label,
        value: toNumber(value) ?? 0,
        max: Math.round(toNumber(max) ?? 5),
      });
    }
  }
  const result = progressSchema.safeParse({ title: heading, rows });
  return result.success ? result.data : null;
}

export interface TreeNode {
  label: string;
  children: TreeNode[];
}

const treeNodeSchema: z.ZodType<TreeNode> = z.lazy(() =>
  z.object({ label: text(120), children: z.array(treeNodeSchema) }),
);
const treeSchema = z.object({ title: z.string().max(120), root: treeNodeSchema });
export type TreeData = z.infer<typeof treeSchema>;

const TREE_MAX_NODES = 80;
const TREE_MAX_DEPTH = 6;

export function parseTree(code: string): TreeData | null {
  let heading = "";
  const stack: Array<{ depth: number; node: TreeNode }> = [];
  let root: TreeNode | null = null;
  let count = 0;
  for (const raw of splitLines(code)) {
    if (!raw.trim()) continue;
    const name = root ? null : readKeyed(raw, "title");
    if (name !== null) {
      heading = name;
      continue;
    }
    const indent = (/^[ \t]*/.exec(raw)?.[0] ?? "").replace(/\t/g, "  ").length;
    const depth = Math.floor(indent / 2);
    const node: TreeNode = { label: raw.trim().replace(/^[-*]\s+/, ""), children: [] };
    if (++count > TREE_MAX_NODES || depth >= TREE_MAX_DEPTH) continue;
    while (stack.length && (stack[stack.length - 1]?.depth ?? 0) >= depth) stack.pop();
    const parent = stack[stack.length - 1]?.node;
    if (!root) root = node;
    else if (parent) parent.children.push(node);
    else root.children.push(node);
    stack.push({ depth, node });
  }
  const result = treeSchema.safeParse({ title: heading, root });
  return result.success ? result.data : null;
}

const flowSchema = z.object({
  title: z.string().max(160),
  stages: z
    .array(
      z.discriminatedUnion("kind", [
        z.object({
          kind: z.literal("row"),
          tiles: z
            .array(z.object({ value: z.string().max(40), label: z.string().max(60) }))
            .min(1)
            .max(8),
        }),
        z.object({
          kind: z.literal("box"),
          title: text(120),
          subtitle: z.string().max(200),
          accent: z.boolean(),
        }),
      ]),
    )
    .min(1)
    .max(12),
});
export type FlowData = z.infer<typeof flowSchema>;

export function parseFlow(code: string): FlowData | null {
  let heading = "";
  const stages: unknown[] = [];
  for (const line of splitLines(code)) {
    const name = readKeyed(line, "title");
    const row = readKeyed(line, "row");
    const box = readKeyed(line, "box");
    if (name !== null) heading = name;
    else if (row !== null) {
      const tiles = row
        .split(";")
        .map((cell) => splitPipe(cell))
        .filter((cell) => (cell[0] ?? "") !== "")
        .map(([value = "", label = ""]) => ({ value, label }));
      stages.push({ kind: "row", tiles });
    } else if (box !== null) {
      const [boxTitle = "", subtitle = "", accent = ""] = splitPipe(box);
      stages.push({
        kind: "box",
        title: boxTitle,
        subtitle,
        accent: accent.toLowerCase() === "accent",
      });
    }
  }
  const result = flowSchema.safeParse({ title: heading, stages });
  return result.success ? result.data : null;
}
