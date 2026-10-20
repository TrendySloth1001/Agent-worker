import { isRichLang, RichBlock } from "@/features/rich";
import { CopyButton } from "../components/copy-button";
import { highlight } from "./highlight";

interface CodeBlockProps {
  lang: string;
  code: string;
}

export function CodeBlock({ lang, code }: CodeBlockProps) {
  if (isRichLang(lang)) return <RichBlock lang={lang} code={code} />;
  return (
    <figure className="my-md overflow-hidden rounded-md bg-code-background">
      <figcaption className="flex h-9 items-center justify-between px-md">
        <span className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
          {lang || "code"}
        </span>
        <CopyButton text={code} />
      </figcaption>
      <pre className="overflow-x-auto px-md pb-md font-mono text-body-small leading-[1.55] text-syn-plain">
        <code>{highlight(code, lang)}</code>
      </pre>
    </figure>
  );
}
