import type { Metadata } from "next";
import { NewChatScreen } from "@/features/chat/components/new-chat-screen";

export const metadata: Metadata = { title: "New chat · sparky" };

export default function NewChatPage() {
  return <NewChatScreen />;
}
