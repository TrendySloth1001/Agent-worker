import type { Metadata } from "next";
import { DotBackdrop } from "@/components/brand/dot-backdrop";
import { Wordmark } from "@/components/brand/wordmark";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { Avatar } from "@/components/ui/avatar";
import { Card } from "@/components/ui/card";
import { LogoutButton } from "@/features/auth/logout-button";
import { getSession } from "@/server/get-session";

export const metadata: Metadata = { title: "Chat · sparky" };

export default async function ChatPage() {
  const session = await getSession();
  if (session.status !== "signed-in") return null;
  const { user } = session.me;
  return (
    <DotBackdrop matrix className="min-h-dvh">
      <header className="mx-auto flex max-w-[64rem] items-center justify-between px-lg py-lg">
        <Wordmark className="text-title" />
        <ThemeToggle />
      </header>
      <main className="mx-auto flex max-w-[28rem] flex-col gap-xl px-lg pt-xl">
        <Card className="flex flex-col items-center gap-lg p-xl text-center">
          <Avatar name={user.name} src={user.avatarUrl ?? undefined} size={72} />
          <div className="flex flex-col gap-xs">
            <h1 className="text-title font-bold">{user.name}</h1>
            <p className="text-body-small text-text-secondary">{user.email}</p>
          </div>
          <LogoutButton />
        </Card>
        <p className="text-center text-body-small text-text-tertiary">Chat is coming soon.</p>
      </main>
    </DotBackdrop>
  );
}
