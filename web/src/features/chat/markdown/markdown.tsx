"use client";

import {
  Children,
  createContext,
  isValidElement,
  memo,
  useContext,
  type ComponentProps,
  type ReactElement,
  type ReactNode,
} from "react";
import ReactMarkdown, { defaultUrlTransform, type Components } from "react-markdown";
import remarkGfm from "remark-gfm";
import { cn } from "@/lib/cn";
import type { Citation } from "../schemas/message";
import { CodeBlock } from "./code-block";
import { CITE_SCHEME, remarkCitations } from "./remark-citations";

interface CitationContextValue {
  citations: readonly Citation[];
  used: ReadonlySet<string>;
}

const CitationContext = createContext<CitationContextValue>({ citations: [], used: new Set() });

function CitationChip({ id }: { id: string }) {
  const { citations, used } = useContext(CitationContext);
  const source = citations.find((c) => c.id === id);
  const label = source?.site || id;
  const className = cn(
    "mx-xxs inline-flex h-[18px] max-w-[140px] items-center rounded-pill px-[6px] align-baseline",
    "font-mono text-[10px] leading-none tracking-[0.04em] uppercase no-underline",
    used.has(id) ? "bg-accent/12 text-accent-text" : "bg-surface-high text-text-secondary",
  );
  if (source?.url.startsWith("http")) {
    return (
      <a
        href={source.url}
        target="_blank"
        rel="noreferrer noopener"
        title={source.title}
        className={className}
      >
        <span className="truncate">{label}</span>
      </a>
    );
  }
  return <span className={className}>{label}</span>;
}

const textOf = (node: ReactNode): string =>
  Children.toArray(node)
    .map((c) =>
      typeof c === "string" || typeof c === "number"
        ? String(c)
        : isValidElement(c)
          ? textOf((c as ReactElement<{ children?: ReactNode }>).props.children)
          : "",
    )
    .join("");

function Pre({ children }: ComponentProps<"pre">) {
  const child = Children.toArray(children)[0];
  if (!isValidElement(child)) return <pre>{children}</pre>;
  const props = (child as ReactElement<{ className?: string; children?: ReactNode }>).props;
  const lang = /language-([\w+#-]+)/.exec(props.className ?? "")?.[1] ?? "";
  return <CodeBlock lang={lang} code={textOf(props.children).replace(/\n$/, "")} />;
}

const HEADING = "mt-xl mb-sm font-bold tracking-[-0.01em] first:mt-0";

const components: Components = {
  p: ({ children }) => <p className="my-sm first:mt-0 last:mb-0">{children}</p>,
  h1: ({ children }) => (
    <h2 className={cn(HEADING, "border-t border-border pt-lg text-title")}>{children}</h2>
  ),
  h2: ({ children }) => (
    <h2 className={cn(HEADING, "border-t border-border pt-lg text-title")}>{children}</h2>
  ),
  h3: ({ children }) => <h3 className={cn(HEADING, "text-[18px]")}>{children}</h3>,
  h4: ({ children }) => <h4 className={cn(HEADING, "text-body")}>{children}</h4>,
  h5: ({ children }) => <h4 className={cn(HEADING, "text-body")}>{children}</h4>,
  h6: ({ children }) => <h4 className={cn(HEADING, "text-body")}>{children}</h4>,
  ul: ({ children }) => (
    <ul className="my-sm list-disc space-y-xs pl-xl marker:text-text-tertiary">{children}</ul>
  ),
  ol: ({ children, start }) => (
    <ol
      start={start ?? undefined}
      className="my-sm list-decimal space-y-xs pl-xl marker:font-mono marker:text-text-tertiary"
    >
      {children}
    </ol>
  ),
  blockquote: ({ children }) => (
    <blockquote className="my-md border-l-2 border-accent pl-md text-text-secondary">
      {children}
    </blockquote>
  ),
  hr: () => <hr className="my-lg border-border" />,
  strong: ({ children }) => <strong className="font-bold">{children}</strong>,
  a: ({ href, children }) =>
    href?.startsWith(CITE_SCHEME) ? (
      <CitationChip id={href.slice(CITE_SCHEME.length)} />
    ) : (
      <a
        href={href}
        target="_blank"
        rel="noreferrer noopener"
        className="text-accent-text underline underline-offset-2 hover:text-text-primary"
      >
        {children}
      </a>
    ),
  pre: ({ children }) => <Pre>{children}</Pre>,
  code: ({ className, children }) => (
    <code
      className={cn(
        "rounded-sm bg-code-background px-[5px] py-[1px] font-mono text-[0.9em]",
        className,
      )}
    >
      {children}
    </code>
  ),
  table: ({ children }) => (
    <div className="my-md overflow-x-auto rounded-md border border-border">
      <table className="w-full border-collapse text-body-small">{children}</table>
    </div>
  ),
  th: ({ children }) => (
    <th className="border-b border-border bg-surface-raised px-md py-sm text-left font-mono text-caption tracking-[0.06em] uppercase">
      {children}
    </th>
  ),
  td: ({ children }) => (
    <td className="border-b border-border px-md py-sm align-top last:border-b-0">{children}</td>
  ),
  img: ({ alt, src }) => (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={typeof src === "string" ? src : undefined}
      alt={alt ?? ""}
      className="my-md max-h-60 rounded-md"
    />
  ),
};

const urlTransform = (url: string): string =>
  url.startsWith(CITE_SCHEME) ? url : defaultUrlTransform(url);

interface MarkdownProps {
  content: string;
  citations?: readonly Citation[];
  used?: readonly string[];
}

const EMPTY: readonly Citation[] = [];

function MarkdownImpl({ content, citations = EMPTY, used = [] }: MarkdownProps) {
  return (
    <CitationContext value={{ citations, used: new Set(used) }}>
      <div className="min-w-0 text-body break-words">
        <ReactMarkdown
          remarkPlugins={[remarkGfm, remarkCitations]}
          components={components}
          urlTransform={urlTransform}
        >
          {content}
        </ReactMarkdown>
      </div>
    </CitationContext>
  );
}

export const Markdown = memo(MarkdownImpl);
