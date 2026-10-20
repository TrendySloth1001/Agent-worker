"use client";

import { Button } from "@/components/ui/button";

export default function AppError({ reset }: { error: Error; reset: () => void }) {
  return (
    <main className="mx-auto flex min-h-app max-w-[28rem] flex-col items-center justify-center gap-lg px-lg text-center">
      <h1 className="text-headline font-bold">Something went wrong</h1>
      <p className="text-body text-text-secondary">Cannot reach your account right now.</p>
      <Button onClick={reset}>Try again</Button>
    </main>
  );
}
