import type { Metadata } from "next";
import { DotBackdrop } from "@/components/brand/dot-backdrop";
import { Wordmark } from "@/components/brand/wordmark";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { Illustration } from "@/components/ui/illustration";
import { AuthForm } from "@/features/auth/auth-form";
import { AUTH_COPY, NOTICES } from "@/features/auth/copy";
import { safeNext } from "@/lib/safe-next";
import { fetchProviders } from "@/server/providers";

export const metadata: Metadata = { title: "Sign in · sparky" };

interface LoginPageProps {
  searchParams: Promise<{ next?: string; notice?: string; error?: string }>;
}

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const params = await searchParams;
  const providers = await fetchProviders();
  const key = params.error ?? params.notice;
  return (
    <DotBackdrop matrix className="min-h-dvh">
      <header className="mx-auto flex max-w-[64rem] items-center justify-between px-lg py-lg">
        <Wordmark className="text-title" />
        <ThemeToggle />
      </header>
      <main className="mx-auto flex w-full max-w-[26rem] flex-col gap-xl px-lg pt-md pb-xxl">
        <div className="flex flex-col items-center gap-lg text-center">
          <Illustration name="hello" height={120} />
          <div className="flex flex-col gap-sm">
            <h1 className="text-headline font-bold">{AUTH_COPY.loginTitle}</h1>
            <p className="text-body text-text-secondary">{AUTH_COPY.loginSubtitle}</p>
          </div>
        </div>
        <AuthForm
          next={safeNext(params.next)}
          notice={key ? NOTICES[key] : undefined}
          githubEnabled={providers.githubWeb}
        />
      </main>
    </DotBackdrop>
  );
}
