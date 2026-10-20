"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { CopyAction, RichFrame } from "./frame";

const CDN_SCRIPT = "https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com";
const CDN_STYLE =
  "https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://fonts.googleapis.com";
const CDN_FONT = "https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://fonts.gstatic.com";
const CSP = `default-src 'none'; img-src data: blob:; media-src data: blob:; style-src 'unsafe-inline' ${CDN_STYLE}; script-src 'unsafe-inline' ${CDN_SCRIPT}; font-src data: ${CDN_FONT}; form-action 'none'; base-uri 'none'`;
const THEME_VARS = [
  "--background",
  "--surface",
  "--surface-raised",
  "--text-primary",
  "--text-secondary",
  "--border",
  "--accent",
] as const;
const MIN_HEIGHT = 80;
const MAX_HEIGHT = 1600;

const REPORTER = `<script>(function(){function r(){parent.postMessage({sparkyHeight:Math.ceil(document.body.getBoundingClientRect().height)},"*")}new ResizeObserver(r).observe(document.body);addEventListener("load",r)})()</script>`;

function buildDocument(html: string, vars: Record<string, string>): string {
  const root = Object.entries(vars)
    .map(([name, value]) => `${name}:${value}`)
    .join(";");
  const base = `:root{${root};color-scheme:light dark}html,body{margin:0;background:transparent;color:${vars["--text-primary"] ?? "inherit"};font-family:system-ui,sans-serif;overflow:hidden}body{padding:12px}`;
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="${CSP}"><style>${base}</style>${html}${REPORTER}`;
}

function readThemeVars(): Record<string, string> {
  const style = getComputedStyle(document.documentElement);
  return Object.fromEntries(THEME_VARS.map((name) => [name, style.getPropertyValue(name).trim()]));
}

export function HtmlCard({ code }: { code: string }) {
  const [view, setView] = useState("preview");
  const [height, setHeight] = useState(240);
  const frame = useRef<HTMLIFrameElement>(null);
  const [vars] = useState(readThemeVars);

  useEffect(() => {
    function onMessage(event: MessageEvent<unknown>) {
      if (event.source !== frame.current?.contentWindow) return;
      const data = event.data;
      if (
        data &&
        typeof data === "object" &&
        "sparkyHeight" in data &&
        typeof data.sparkyHeight === "number"
      ) {
        setHeight(Math.min(Math.max(Math.ceil(data.sparkyHeight), MIN_HEIGHT), MAX_HEIGHT));
      }
    }
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, []);

  const srcDoc = useMemo(() => buildDocument(code, vars), [code, vars]);

  return (
    <RichFrame
      label="HTML"
      flush
      trailing={
        <Tabs value={view} onValueChange={setView}>
          <TabsList className="h-7">
            <TabsTrigger value="preview">Preview</TabsTrigger>
            <TabsTrigger value="source">Source</TabsTrigger>
          </TabsList>
        </Tabs>
      }
      actions={<CopyAction text={code} label="Copy source" />}
    >
      {view === "preview" ? (
        <iframe
          ref={frame}
          title="HTML preview"
          sandbox="allow-scripts"
          referrerPolicy="no-referrer"
          srcDoc={srcDoc}
          style={{ height }}
          className="block w-full border-0 bg-transparent"
        />
      ) : (
        <pre className="max-h-96 overflow-auto p-md font-mono text-label leading-normal whitespace-pre text-syn-plain">
          <code>{code}</code>
        </pre>
      )}
    </RichFrame>
  );
}
