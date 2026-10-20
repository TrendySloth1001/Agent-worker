import type { Metadata } from "next";
import { KeysScreen } from "@/features/settings/components/keys/keys-screen";

export const metadata: Metadata = { title: "Your API keys" };

export default function Page() {
  return <KeysScreen />;
}
