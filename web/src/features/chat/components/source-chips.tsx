import { Icon } from "@/components/ui/icon";
import { cn } from "@/lib/cn";
import type { Citation } from "../schemas/message";

const MAX_LABEL = 22;

export function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

export function distinctSources(
  citations: readonly Citation[],
  used: ReadonlySet<string>,
): { citation: Citation; cited: boolean }[] {
  const byKey = new Map<string, { citation: Citation; cited: boolean }>();
  for (const c of citations) {
    const host = hostOf(c.url);
    const page = c.url.split("#")[0] || c.title;
    const key =
      c.kind === "web" && host && host !== "github.com" ? `web|${host}` : `${c.kind}|${page}`;
    const hit = byKey.get(key);
    if (hit) hit.cited ||= used.has(c.id);
    else byKey.set(key, { citation: c, cited: used.has(c.id) });
  }
  return [...byKey.values()];
}

const labelOf = (c: Citation): string => {
  const label = c.site || hostOf(c.url) || c.title || c.id;
  return label.length > MAX_LABEL ? `${label.slice(0, MAX_LABEL - 1)}…` : label;
};

interface SourceChipsProps {
  citations: readonly Citation[];
  used: readonly string[];
}

export function SourceChips({ citations, used }: SourceChipsProps) {
  const chips = distinctSources(citations, new Set(used));
  if (chips.length === 0) return null;
  return (
    <ul className="-mx-xs flex gap-xs overflow-x-auto px-xs py-xxs" aria-label="Sources">
      {chips.map(({ citation, cited }) => {
        const external = citation.url.startsWith("http");
        const className = cn(
          "flex h-chip-height items-center gap-xs rounded-pill border px-md font-mono text-caption tracking-[0.04em] whitespace-nowrap",
          cited ? "border-accent text-text-primary" : "border-border-strong text-text-secondary",
          external && "duration-fast transition-colors ease-standard hover:border-text-primary",
        );
        return (
          <li key={citation.id} className="shrink-0">
            {external ? (
              <a
                href={citation.url}
                target="_blank"
                rel="noreferrer noopener"
                title={citation.title}
                className={className}
              >
                <Icon name="web" size="xs" />
                {labelOf(citation)}
              </a>
            ) : (
              <span title={citation.title} className={className}>
                <Icon name={citation.kind === "kb" ? "knowledge" : "file"} size="xs" />
                {labelOf(citation)}
              </span>
            )}
          </li>
        );
      })}
    </ul>
  );
}
