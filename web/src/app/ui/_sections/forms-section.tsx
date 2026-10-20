"use client";

import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { Section } from "./section";

export function FormsSection() {
  const [on, setOn] = useState(true);
  return (
    <>
      <Section title="Fields">
        <div className="flex max-w-[28rem] flex-col gap-md">
          <Input placeholder="Ask anything" aria-label="Text input" />
          <Input defaultValue="Invalid value" aria-invalid aria-label="Invalid input" />
          <Input placeholder="Disabled" disabled aria-label="Disabled input" />
          <Textarea placeholder="Type, and this grows with you" aria-label="Autosize textarea" />
        </div>
      </Section>
      <Section title="Switch">
        <div className="flex items-center gap-lg">
          <Switch checked={on} onCheckedChange={setOn} aria-label="Demo switch" />
          <Switch aria-label="Off switch" />
          <Switch disabled aria-label="Disabled switch" />
        </div>
      </Section>
      <Section title="Tabs">
        <Tabs defaultValue="chat" className="max-w-[28rem]">
          <TabsList className="w-full">
            <TabsTrigger value="chat">Chat</TabsTrigger>
            <TabsTrigger value="history">History</TabsTrigger>
            <TabsTrigger value="notes">Notes</TabsTrigger>
          </TabsList>
          <TabsContent value="chat" className="text-body-small text-text-secondary">
            Chat panel.
          </TabsContent>
          <TabsContent value="history" className="text-body-small text-text-secondary">
            History panel.
          </TabsContent>
          <TabsContent value="notes" className="text-body-small text-text-secondary">
            Notes panel.
          </TabsContent>
        </Tabs>
      </Section>
    </>
  );
}
