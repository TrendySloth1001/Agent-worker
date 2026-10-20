import type { Metadata } from "next";
import { AppearanceScreen } from "@/features/settings/components/appearance-screen";

export const metadata: Metadata = { title: "Appearance" };

export default function Page() {
  return <AppearanceScreen />;
}
