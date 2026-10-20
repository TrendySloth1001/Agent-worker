import type { Element, ElementContent, Root } from "hast";
import { common, createLowlight } from "lowlight";
import type { ReactNode } from "react";

const lowlight = createLowlight(common);

export const MAX_HIGHLIGHT_CHARS = 20_000;

const KEYWORD = ["keyword", "built_in", "literal", "type", "selector-tag", "tag", "name", "meta", "title", "function", "class"];
const STRING = ["string", "regexp", "symbol", "attr", "attribute", "template-variable", "link", "addition"];
const NUMBER = ["number", "bullet", "variable", "params", "deletion"];
const COMMENT = ["comment", "quote", "doctag"];

const TOKEN_CLASS: Record<string, string> = {};
for (const k of KEYWORD) TOKEN_CLASS[k] = "text-syn-keyword";
for (const k of STRING) TOKEN_CLASS[k] = "text-syn-string";
for (const k of NUMBER) TOKEN_CLASS[k] = "text-syn-number";
for (const k of COMMENT) TOKEN_CLASS[k] = "text-syn-comment italic";

function tokenClass(node: Element): string | undefined {
  const classes = node.properties.className;
  if (!Array.isArray(classes)) return undefined;
  for (const c of classes) {
    const hit = TOKEN_CLASS[String(c).replace(/^hljs-/, "").split(".")[0] ?? ""];
    if (hit) return hit;
  }
  return undefined;
}

function render(nodes: readonly ElementContent[], keyPrefix: string): ReactNode[] {
  return nodes.map((node, i) => {
    const key = `${keyPrefix}.${i}`;
    if (node.type === "text") return node.value;
    if (node.type !== "element") return null;
    return (
      <span key={key} className={tokenClass(node)}>
        {render(node.children, key)}
      </span>
    );
  });
}

function parse(code: string, lang: string): Root | null {
  if (code.length > MAX_HIGHLIGHT_CHARS) return null;
  try {
    return lowlight.registered(lang) ? lowlight.highlight(lang, code) : null;
  } catch {
    return null;
  }
}

export function highlight(code: string, lang: string): ReactNode {
  const tree = parse(code, lang.toLowerCase());
  return tree ? render(tree.children as ElementContent[], "h") : code;
}
