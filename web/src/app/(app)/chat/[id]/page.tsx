import type { Metadata } from "next";
import { ConversationScreen } from "@/features/chat/components/conversation-screen";

export const metadata: Metadata = { title: "Chat · sparky" };

export default async function ConversationPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <ConversationScreen id={id} />;
}
