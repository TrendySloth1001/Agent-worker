import { BetaTag } from "@/components/ui/beta-tag";
import { Button, type ButtonVariant } from "@/components/ui/button";
import { IconButton } from "@/components/ui/icon-button";
import { Kbd } from "@/components/ui/kbd";
import { Tag } from "@/components/ui/tag";
import { Section } from "./section";

const VARIANTS: ButtonVariant[] = ["primary", "secondary", "ghost", "danger"];

export function ButtonsSection() {
  return (
    <>
      <Section title="Buttons">
        <div className="flex flex-wrap items-center gap-md">
          {VARIANTS.map((v) => (
            <Button key={v} variant={v}>
              {v}
            </Button>
          ))}
          <Button disabled>Disabled</Button>
        </div>
        <div className="flex flex-wrap items-center gap-md">
          <Button size="sm">Small</Button>
          <Button size="md">Medium</Button>
          <Button size="lg">Large</Button>
          <Button plain>Plain text</Button>
        </div>
        <Button fullWidth variant="secondary">
          Full width
        </Button>
      </Section>
      <Section title="Icon buttons">
        <div className="flex flex-wrap items-center gap-md">
          <IconButton icon="settings" label="Settings" />
          <IconButton icon="newChat" label="New chat" variant="filled" />
          <IconButton icon="more" label="More" variant="ghost" />
          <IconButton icon="close" label="Close" disabled />
        </div>
      </Section>
      <Section title="Tags and keys">
        <div className="flex flex-wrap items-center gap-md">
          <Tag>Owner</Tag>
          <Tag accent>Live</Tag>
          <Tag mono={false}>Readable</Tag>
          <BetaTag />
          <Kbd>⌘</Kbd>
          <Kbd>K</Kbd>
          <Kbd>Esc</Kbd>
        </div>
      </Section>
    </>
  );
}
