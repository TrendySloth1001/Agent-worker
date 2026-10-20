"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/cn";
import { safeActionUrl, safeWebUrl } from "../lib/safe-url";
import { useRichActions } from "../rich-actions";
import {
  emailAsText,
  type AskData,
  type EmailDraft,
  type MessageDraft,
  type SpecData,
} from "../parsers/drafts";
import { CopyAction, RichFrame } from "./frame";

function LinkAction({ href, label }: { href: string | null; label: string }) {
  if (!href) return null;
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="inline-flex min-h-8 items-center gap-xs font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase hover:text-text-primary"
    >
      {label}
    </a>
  );
}

function Field({ name, value }: { name: string; value: string }) {
  if (!value) return null;
  return (
    <div className="flex gap-md text-body-small">
      <span className="w-14 shrink-0 font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
        {name}
      </span>
      <span className="min-w-0 break-words">{value}</span>
    </div>
  );
}

export function EmailCard({ draft }: { draft: EmailDraft }) {
  const mailto = safeActionUrl(
    `mailto:${draft.to}?${[draft.cc && `cc=${encodeURIComponent(draft.cc)}`, draft.bcc && `bcc=${encodeURIComponent(draft.bcc)}`, `subject=${encodeURIComponent(draft.subject)}`, `body=${encodeURIComponent(draft.body)}`].filter(Boolean).join("&")}`,
  );
  const gmail = safeWebUrl(
    `https://mail.google.com/mail/?view=cm&fs=1&to=${encodeURIComponent(draft.to)}&su=${encodeURIComponent(draft.subject)}&body=${encodeURIComponent(draft.body)}`,
  );
  return (
    <RichFrame
      label="Email draft"
      actions={
        <>
          <CopyAction text={emailAsText(draft)} />
          <LinkAction href={mailto} label="Mail app" />
          <LinkAction href={gmail} label="Gmail" />
        </>
      }
    >
      <div className="flex flex-col gap-xs border-b border-border pb-md">
        <Field name="To" value={draft.to} />
        <Field name="Cc" value={draft.cc} />
        <Field name="Bcc" value={draft.bcc} />
        <Field name="Subject" value={draft.subject} />
      </div>
      <p className="pt-md text-body-small whitespace-pre-wrap">{draft.body}</p>
    </RichFrame>
  );
}

export function MessageCard({ draft }: { draft: MessageDraft }) {
  const digits = draft.to.replace(/\D/g, "");
  const text = encodeURIComponent(draft.text);
  const link =
    draft.platform === "whatsapp" && digits
      ? safeWebUrl(`https://wa.me/${digits}?text=${text}`)
      : draft.platform === "sms" && digits
        ? safeActionUrl(`sms:${digits}?body=${text}`)
        : null;
  return (
    <RichFrame
      label={draft.platform ? `${draft.platform} message` : "Message"}
      actions={
        <>
          <CopyAction text={draft.text} />
          <LinkAction href={link} label={draft.platform === "whatsapp" ? "WhatsApp" : "Send"} />
        </>
      }
    >
      {draft.to && <Field name="To" value={draft.to} />}
      <p className={cn("text-body-small whitespace-pre-wrap", draft.to && "pt-sm")}>{draft.text}</p>
    </RichFrame>
  );
}

export function SpecCard({ data }: { data: SpecData }) {
  return (
    <RichFrame label="Card">
      <p className="text-title font-medium">{data.title}</p>
      {data.subtitle && <p className="text-body-small text-text-secondary">{data.subtitle}</p>}
      {data.rows.length > 0 && (
        <dl className="mt-md flex flex-col">
          {data.rows.map((row) => (
            <div
              key={row.key}
              className="flex justify-between gap-md border-t border-border py-sm text-body-small"
            >
              <dt className="text-text-secondary">{row.key}</dt>
              <dd className="min-w-0 text-right break-words">{row.value}</dd>
            </div>
          ))}
        </dl>
      )}
    </RichFrame>
  );
}

export function AskCard({ data }: { data: AskData }) {
  const { sendMessage } = useRichActions();
  const [chosen, setChosen] = useState<ReadonlySet<string>>(new Set());
  const [other, setOther] = useState("");
  const [typing, setTyping] = useState(false);
  const [sent, setSent] = useState(false);
  const locked = sent || !sendMessage;

  function submit(values: string[]) {
    if (!sendMessage || values.length === 0) return;
    sendMessage(values.join(", "));
    setSent(true);
  }

  function pick(option: string) {
    if (locked) return;
    if (!data.multi) return submit([option]);
    setChosen((current) => {
      const next = new Set(current);
      if (!next.delete(option)) next.add(option);
      return next;
    });
  }

  const answer = [...chosen, ...(typing && other.trim() ? [other.trim().slice(0, 300)] : [])];

  return (
    <RichFrame label={sent ? "Answered" : "Question"}>
      <p className="mb-md text-body font-medium">{data.question}</p>
      {data.multi && !sent && (
        <p className="mb-sm font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
          Select all that apply
        </p>
      )}
      <div className="flex flex-wrap gap-sm">
        {data.options.map((option) => (
          <button
            key={option}
            type="button"
            disabled={locked}
            aria-pressed={chosen.has(option)}
            onClick={() => pick(option)}
            className={cn(
              "duration-fast min-h-11 rounded-pill border px-lg text-body-small transition-colors ease-standard",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-default",
              chosen.has(option)
                ? "border-text-primary bg-text-primary text-text-inverse"
                : "border-border-strong hover:border-text-primary",
              locked && !chosen.has(option) && "opacity-60",
            )}
          >
            {option}
          </button>
        ))}
        {data.other && !sent && (
          <button
            type="button"
            disabled={locked}
            onClick={() => setTyping((value) => !value)}
            className={cn(
              "min-h-11 rounded-pill border px-lg text-body-small",
              typing
                ? "border-text-primary bg-text-primary text-text-inverse"
                : "border-border-strong hover:border-text-primary",
            )}
          >
            Other…
          </button>
        )}
      </div>
      {typing && !sent && (
        <Input
          className="mt-md h-11"
          maxLength={300}
          placeholder="Type your answer"
          value={other}
          onChange={(event) => setOther(event.target.value)}
        />
      )}
      {(data.multi || typing) && !sent && sendMessage && (
        <Button
          size="sm"
          className="mt-md"
          disabled={answer.length === 0}
          onClick={() => submit(answer)}
        >
          Send
        </Button>
      )}
    </RichFrame>
  );
}
