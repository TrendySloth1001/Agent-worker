import type { Metadata } from "next";
import { ConnectionsScreen } from "@/features/settings/components/connections/connections-screen";

export const metadata: Metadata = { title: "Connected apps" };

export default function Page() {
  return <ConnectionsScreen />;
}
