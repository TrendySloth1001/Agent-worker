"use client";

import { usePathname } from "next/navigation";
import { useState } from "react";
import { ChatSession } from "./chat-session";

const NEW_CHAT_PATH = "/chat";

export function NewChatScreen() {
  const pathname = usePathname();
  const [seen, setSeen] = useState(pathname);
  const [epoch, setEpoch] = useState(0);

  if (pathname !== seen) {
    setSeen(pathname);
    if (pathname === NEW_CHAT_PATH) setEpoch((e) => e + 1);
  }

  return <ChatSession key={epoch} />;
}
