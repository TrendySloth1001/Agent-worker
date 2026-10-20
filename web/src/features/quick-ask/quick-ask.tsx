"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState, type KeyboardEvent } from "react";
import { Button } from "@/components/ui/button";
import { Kbd } from "@/components/ui/kbd";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import { QUICK_ASK_MAX, QUICK_ASK_URL, isQuickAskShortcut, stashQuickAsk } from "./handoff";

export function QuickAsk() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [prompt, setPrompt] = useState("");

  useEffect(() => {
    const onKeyDown = (event: globalThis.KeyboardEvent) => {
      if (!isQuickAskShortcut(event)) return;
      event.preventDefault();
      setOpen((current) => !current);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const submit = () => {
    if (!stashQuickAsk(prompt)) return;
    setPrompt("");
    setOpen(false);
    router.push(QUICK_ASK_URL);
  };

  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key !== "Enter" || event.shiftKey || event.nativeEvent.isComposing) return;
    event.preventDefault();
    submit();
  };

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetContent>
        <div className="flex flex-col gap-md">
          <div className="flex flex-col gap-xs">
            <SheetTitle className="text-title font-bold">Quick ask</SheetTitle>
            <SheetDescription className="text-body-small text-text-secondary">
              Ask sparky anything. It opens in a new chat.
            </SheetDescription>
          </div>
          <Textarea
            autoFocus
            rows={3}
            value={prompt}
            maxLength={QUICK_ASK_MAX}
            aria-label="Your question"
            placeholder="Ask sparky…"
            onChange={(event) => setPrompt(event.target.value)}
            onKeyDown={onKeyDown}
          />
          <div className="flex items-center justify-between gap-md">
            <span className="flex items-center gap-xs text-caption text-text-tertiary">
              <Kbd>Enter</Kbd> to ask
            </span>
            <Button onClick={submit} disabled={prompt.trim().length === 0}>
              Ask
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
