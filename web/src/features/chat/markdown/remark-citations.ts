import type { Parent, PhrasingContent, Root, RootContent } from "mdast";

export const CITE_SCHEME = "cite:";

const MARKER = /\[([KWDC]\d{1,3})\]/g;

function split(value: string): PhrasingContent[] {
  const out: PhrasingContent[] = [];
  let last = 0;
  for (const match of value.matchAll(MARKER)) {
    const id = match[1] as string;
    if (match.index > last) out.push({ type: "text", value: value.slice(last, match.index) });
    out.push({ type: "link", url: `${CITE_SCHEME}${id}`, children: [{ type: "text", value: id }] });
    last = match.index + match[0].length;
  }
  if (out.length === 0) return [{ type: "text", value }];
  if (last < value.length) out.push({ type: "text", value: value.slice(last) });
  return out;
}

const isParent = (node: RootContent | Root): node is Parent & (RootContent | Root) =>
  "children" in node && Array.isArray(node.children);

function walk(node: Root | RootContent): void {
  if (!isParent(node) || node.type === "link" || node.type === "linkReference") return;
  const next: RootContent[] = [];
  for (const child of node.children as RootContent[]) {
    if (child.type === "text") next.push(...split(child.value));
    else {
      walk(child);
      next.push(child);
    }
  }
  node.children = next as typeof node.children;
}

export function remarkCitations() {
  return (tree: Root) => walk(tree);
}
