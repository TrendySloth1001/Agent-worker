import type { Metadata } from "next";
import { ModelsScreen } from "@/features/settings/components/models-screen";

export const metadata: Metadata = { title: "Models & reply style" };

export default function Page() {
  return <ModelsScreen />;
}
