"use client";

import { useState } from "react";
import { Avatar } from "@/components/ui/avatar";
import { BetaTag } from "@/components/ui/beta-tag";
import { ProfileAura } from "@/components/ui/profile-aura";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsSwitchTile } from "@/components/ui/settings-switch-tile";
import { SettingsTile } from "@/components/ui/settings-tile";
import { Section } from "./section";

export function SettingsSection() {
  const [haptics, setHaptics] = useState(true);
  const [notify, setNotify] = useState(false);
  return (
    <>
      <Section title="Settings">
        <div className="max-w-[36rem]">
          <SettingsGroupHeader>Appearance</SettingsGroupHeader>
          <SettingsGroup>
            <SettingsTile icon="appearance" title="Theme" subtitle="Follows the system" chevron />
            <SettingsTile icon="models" title="Model" value="Fastest" chevron />
            <SettingsTile
              icon="key"
              title="Google Drive"
              subtitle="Connect your files"
              badge={<BetaTag />}
              chevron
            />
          </SettingsGroup>
          <SettingsGroupHeader>Behavior</SettingsGroupHeader>
          <SettingsGroup>
            <SettingsSwitchTile
              icon="haptics"
              title="Haptics"
              subtitle="Feel taps on supported devices"
              checked={haptics}
              onCheckedChange={setHaptics}
            />
            <SettingsSwitchTile
              icon="notify"
              title="Notifications"
              checked={notify}
              onCheckedChange={setNotify}
            />
            <SettingsTile icon="delete" title="Delete all chats" danger onClick={() => undefined} />
          </SettingsGroup>
        </div>
      </Section>
      <Section title="Avatar and aura">
        <div className="flex flex-wrap items-center gap-xl">
          <Avatar name="Nikhil Kumawat" size={56} />
          <Avatar name="Sparky" size={40} />
          <Avatar size={32} />
          <ProfileAura>
            <Avatar name="Nikhil Kumawat" size={88} />
          </ProfileAura>
        </div>
      </Section>
    </>
  );
}
