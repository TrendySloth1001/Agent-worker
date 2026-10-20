import type { Metadata } from "next";
import { ProfileScreen } from "@/features/settings/components/profile/profile-screen";

export const metadata: Metadata = { title: "Profile" };

export default function Page() {
  return <ProfileScreen />;
}
