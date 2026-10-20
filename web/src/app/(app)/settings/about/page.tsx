import type { Metadata } from "next";
import { AboutScreen } from "@/features/settings/components/about-screen";
import { APP_VERSION } from "@/features/settings/content/version";

export const metadata: Metadata = { title: "About" };

export default function Page() {
  return <AboutScreen version={APP_VERSION} />;
}
