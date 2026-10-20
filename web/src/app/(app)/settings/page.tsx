import type { Metadata } from "next";
import { SettingsIndex } from "@/features/settings/components/settings-index";

export const metadata: Metadata = { title: "Settings" };

export default function Page() {
  return <SettingsIndex />;
}
