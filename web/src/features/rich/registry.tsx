"use client";

import dynamic from "next/dynamic";
import type { ReactNode } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { ChecklistCard } from "./components/checklist-card";
import { AskCard, EmailCard, MessageCard, SpecCard } from "./components/draft-cards";
import { DeviceActionCard } from "./components/device-action-card";
import { DiffBlock } from "./components/diff-block";
import { FlashcardsCard } from "./components/flashcards-card";
import { IntentCard } from "./components/intent-card";
import { PlaylistCard } from "./components/playlist-card";
import { QuizCard } from "./components/quiz-card";
import { StatsCard } from "./components/stats-card";
import { CompareCard, FlowCard, ProgressCard, TreeCard } from "./components/structure-cards";
import { TimelineCard } from "./components/timeline-card";
import { asRichLang, type RichLang } from "./langs";
import { parseChart } from "./parsers/chart";
import { parseDeviceAction } from "./parsers/device-action";
import { parseAsk, parseEmail, parseMessage, parseSpec } from "./parsers/drafts";
import { parseIntentCard } from "./parsers/intent-card";
import { parsePlaylist } from "./parsers/playlist";
import {
  parseCalc,
  parseChecklist,
  parseFlashcards,
  parseQuiz,
  parseStats,
  parseTimeline,
} from "./parsers/playful";
import { parseCompare, parseFlow, parseProgress, parseTree } from "./parsers/structure";

const loading = () => <Skeleton className="my-sm h-40 w-full" />;

const ChartCard = dynamic(() => import("./components/chart-card").then((m) => m.ChartCard), {
  loading,
});
const CalcCard = dynamic(() => import("./components/calc-card").then((m) => m.CalcCard), {
  loading,
});
const HtmlCard = dynamic(() => import("./components/html-card").then((m) => m.HtmlCard), {
  ssr: false,
  loading,
});
const MermaidCard = dynamic(() => import("./components/mermaid-card").then((m) => m.MermaidCard), {
  ssr: false,
  loading,
});

type Renderer = (code: string) => ReactNode;

function from<T>(parse: (code: string) => T | null, render: (data: T) => ReactNode): Renderer {
  return (code) => {
    const data = parse(code);
    return data === null ? null : render(data);
  };
}

export const RENDERERS: Readonly<Record<RichLang, Renderer>> = {
  chart: from(parseChart, (spec) => <ChartCard spec={spec} />),
  quiz: from(parseQuiz, (data) => <QuizCard data={data} />),
  flashcards: from(parseFlashcards, (data) => <FlashcardsCard data={data} />),
  calc: from(parseCalc, (data) => <CalcCard data={data} />),
  timeline: from(parseTimeline, (data) => <TimelineCard data={data} />),
  stats: from(parseStats, (data) => <StatsCard data={data} />),
  checklist: from(parseChecklist, (data) => <ChecklistCard data={data} />),
  compare: from(parseCompare, (data) => <CompareCard data={data} />),
  progress: from(parseProgress, (data) => <ProgressCard data={data} />),
  tree: from(parseTree, (data) => <TreeCard data={data} />),
  flow: from(parseFlow, (data) => <FlowCard data={data} />),
  email: from(parseEmail, (draft) => <EmailCard draft={draft} />),
  message: from(parseMessage, (draft) => <MessageCard draft={draft} />),
  card: from(parseSpec, (data) => <SpecCard data={data} />),
  ask: from(parseAsk, (data) => <AskCard data={data} />),
  diff: (code) => <DiffBlock code={code} />,
  html: (code) => (code.trim() ? <HtmlCard code={code} /> : null),
  mermaid: (code) => (code.trim() ? <MermaidCard code={code} /> : null),
  "sparky-card": from(parseIntentCard, (data) => <IntentCard data={data} />),
  "sparky-playlist": from(parsePlaylist, (data) => <PlaylistCard data={data} />),
  "sparky-action": from(parseDeviceAction, (data) => <DeviceActionCard data={data} />),
};

export function renderRich(lang: string, code: string): ReactNode {
  const name = asRichLang(lang);
  return name ? RENDERERS[name](code) : null;
}
