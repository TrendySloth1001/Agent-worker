"use client";

import { useEffect, useId, useState } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { CodeFallback, CopyAction, RichFrame } from "./frame";

type State = { status: "loading" } | { status: "ready"; svg: string } | { status: "failed" };

function isDark(): boolean {
  const theme = document.documentElement.dataset.theme;
  return (
    theme === "dark" || (theme !== "light" && matchMedia("(prefers-color-scheme: dark)").matches)
  );
}

export function MermaidCard({ code }: { code: string }) {
  const id = `mermaid-${useId().replace(/[^a-z0-9]/gi, "")}`;
  const [state, setState] = useState<State>({ status: "loading" });

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const { default: mermaid } = await import("mermaid");
        mermaid.initialize({
          startOnLoad: false,
          securityLevel: "strict",
          theme: isDark() ? "dark" : "neutral",
          fontFamily: "var(--font-grotesk), system-ui, sans-serif",
        });
        const { svg } = await mermaid.render(id, code);
        if (!cancelled) setState({ status: "ready", svg });
      } catch {
        if (!cancelled) setState({ status: "failed" });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [code, id]);

  if (state.status === "failed") return <CodeFallback code={code} lang="mermaid" />;
  return (
    <RichFrame label="Diagram" actions={<CopyAction text={code} label="Copy source" />}>
      {state.status === "loading" ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div
          className="overflow-x-auto [&_svg]:mx-auto [&_svg]:h-auto [&_svg]:max-w-full"
          dangerouslySetInnerHTML={{ __html: state.svg }}
        />
      )}
    </RichFrame>
  );
}
