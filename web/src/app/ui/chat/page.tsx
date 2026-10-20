import type { Metadata } from "next";
import { ChatFixture } from "./_components/chat-fixture";
import { SCENARIOS, type Scenario } from "./_components/fixtures";

export const metadata: Metadata = { title: "sparky chat fixture" };

const isScenario = (value: string | undefined): value is Scenario =>
  SCENARIOS.some((s) => s === value);

export default async function ChatFixturePage({
  searchParams,
}: {
  searchParams: Promise<{ scenario?: string }>;
}) {
  const { scenario } = await searchParams;
  return <ChatFixture scenario={isScenario(scenario) ? scenario : "conversation"} />;
}
