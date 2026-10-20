import Link from "next/link";
import { DotBackdrop } from "@/components/brand/dot-backdrop";
import { Mascot } from "@/components/brand/mascot";
import { Wordmark } from "@/components/brand/wordmark";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { Button } from "@/components/ui/button";

export default function HomePage() {
  return (
    <DotBackdrop matrix className="min-h-dvh">
      <main className="mx-auto flex min-h-dvh max-w-[36rem] flex-col items-center justify-center gap-xl px-lg text-center">
        <Mascot size={88} />
        <Wordmark className="text-display" />
        <p className="text-body text-text-secondary">The web app is on its way.</p>
        <div className="flex items-center gap-md">
          <Button asChild>
            <Link href="/ui">Component gallery</Link>
          </Button>
          <ThemeToggle />
        </div>
      </main>
    </DotBackdrop>
  );
}
