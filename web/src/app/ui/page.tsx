import type { Metadata } from "next";
import Link from "next/link";
import { Wordmark } from "@/components/brand/wordmark";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { BrandSection } from "./_sections/brand-section";
import { ButtonsSection } from "./_sections/buttons-section";
import { FeedbackSection } from "./_sections/feedback-section";
import { FoundationsSection } from "./_sections/foundations-section";
import { FormsSection } from "./_sections/forms-section";
import { SettingsSection } from "./_sections/settings-section";
import { SurfacesSection } from "./_sections/surfaces-section";

export const metadata: Metadata = { title: "sparky UI" };

export default function UiGalleryPage() {
  return (
    <main className="mx-auto flex max-w-5xl flex-col gap-xxxl px-lg py-xl">
      <header className="flex items-center justify-between gap-md">
        <Link href="/">
          <Wordmark className="text-headline" />
        </Link>
        <ThemeToggle />
      </header>
      <BrandSection />
      <FoundationsSection />
      <ButtonsSection />
      <FormsSection />
      <SurfacesSection />
      <SettingsSection />
      <FeedbackSection />
    </main>
  );
}
