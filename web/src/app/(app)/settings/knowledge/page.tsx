import type { Metadata } from "next";
import { KnowledgeScreen } from "@/features/settings/components/knowledge/knowledge-screen";

export const metadata: Metadata = { title: "Saved knowledge" };

export default function Page() {
  return <KnowledgeScreen />;
}
