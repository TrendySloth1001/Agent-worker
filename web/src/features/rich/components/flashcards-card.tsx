"use client";

import { useState } from "react";
import type { FlashcardsData } from "../parsers/playful";
import { MonoButton, RichAction, RichFrame } from "./frame";

function shuffled<T>(items: readonly T[]): T[] {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j] as T, copy[i] as T];
  }
  return copy;
}

export function FlashcardsCard({ data }: { data: FlashcardsData }) {
  const [deck, setDeck] = useState(data.cards);
  const [index, setIndex] = useState(0);
  const [flipped, setFlipped] = useState(false);
  const [known, setKnown] = useState(0);
  const [again, setAgain] = useState<typeof data.cards>([]);
  const card = deck[index];

  function advance(knew: boolean) {
    if (!card) return;
    if (knew) setKnown((value) => value + 1);
    else setAgain((value) => [...value, card]);
    setFlipped(false);
    setIndex((value) => value + 1);
  }

  function restart(cards: typeof data.cards) {
    setDeck(cards);
    setIndex(0);
    setFlipped(false);
    setKnown(0);
    setAgain([]);
  }

  if (!card) {
    return (
      <RichFrame label={`${data.title} - deck done`}>
        <div className="flex flex-col items-center gap-sm py-md text-center">
          <p className="font-mono text-label tracking-[0.12em] text-accent-text uppercase">
            Deck done
          </p>
          <p className="font-mono text-caption tracking-[0.08em] text-text-secondary uppercase">
            Known {known} · Again {again.length}
          </p>
          <div className="mt-sm flex flex-wrap justify-center gap-sm">
            <MonoButton onClick={() => restart(data.cards)}>Restart</MonoButton>
            {again.length > 0 && (
              <MonoButton onClick={() => restart(again)}>Study again cards only</MonoButton>
            )}
          </div>
        </div>
      </RichFrame>
    );
  }

  return (
    <RichFrame
      label={data.title}
      trailing={
        <span className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
          {index + 1}/{deck.length}
        </span>
      }
      actions={<RichAction icon="shuffle" label="Shuffle" onRun={() => restart(shuffled(deck))} />}
    >
      <button
        type="button"
        onClick={() => setFlipped((value) => !value)}
        aria-label={flipped ? "Show front" : "Show back"}
        className="duration-fast flex h-44 w-full flex-col items-center justify-center gap-sm rounded-md border border-border bg-surface px-lg text-center transition-colors ease-standard hover:border-border-strong focus-visible:outline-2 focus-visible:outline-accent"
      >
        <span className="text-title font-medium">{flipped ? card.back : card.front}</span>
        <span className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
          {flipped ? "Back" : "Tap to flip"}
        </span>
      </button>
      <div className="mt-md flex justify-center gap-sm">
        <MonoButton onClick={() => advance(false)}>Again</MonoButton>
        <MonoButton
          onClick={() => advance(true)}
          className="border-text-primary bg-text-primary text-text-inverse hover:bg-accent hover:text-white"
        >
          Knew it
        </MonoButton>
      </div>
    </RichFrame>
  );
}
