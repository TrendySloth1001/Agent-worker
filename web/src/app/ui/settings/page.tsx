import type { Metadata } from "next";
import { SettingsFixture } from "./_settings-fixture";

export const metadata: Metadata = { title: "sparky settings fixture" };

interface PageProps {
  searchParams: Promise<{ screen?: string }>;
}

export default async function SettingsFixturePage({ searchParams }: PageProps) {
  const { screen } = await searchParams;
  return <SettingsFixture initial={screen ?? "index"} />;
}
