import type { Metadata } from "next";
import Link from "next/link";
import { Wordmark } from "@/components/brand/wordmark";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { FilesFixture } from "./files-fixture";

export const metadata: Metadata = { title: "sparky files" };

export default async function FilesFixturePage({
  searchParams,
}: {
  searchParams: Promise<{ preview?: string }>;
}) {
  const { preview } = await searchParams;
  return (
    <main className="mx-auto flex max-w-[44rem] flex-col gap-lg px-lg py-xl">
      <header className="flex items-center justify-between gap-md">
        <Link href="/ui">
          <Wordmark className="text-headline" />
        </Link>
        <ThemeToggle />
      </header>
      <FilesFixture initial={preview === "image" || preview === "document" ? preview : null} />
    </main>
  );
}
