import type { Metadata } from "next";
import { MemoryScreen } from "@/features/settings/components/memory/memory-screen";

export const metadata: Metadata = { title: "Memory" };

export default function Page() {
  return <MemoryScreen />;
}
