"use client";

import { Button } from "@/components/ui/button";
import { DotLoader } from "@/components/ui/dot-loader";
import { Icon } from "@/components/ui/icon";
import { toast } from "@/components/ui/toaster";
import { CONNECTIONS_COPY } from "../../content/copy";
import type { DeviceFlow } from "../../schemas/connections";
import { FormSheet } from "../form-sheet";

interface GithubFlowSheetProps {
  flow: DeviceFlow | null;
  onCancel: () => void;
}

export function GithubFlowSheet({ flow, onCancel }: GithubFlowSheetProps) {
  const copy = CONNECTIONS_COPY.github;

  const copyCode = async () => {
    if (!flow) return;
    try {
      await navigator.clipboard.writeText(flow.userCode);
      toast.success(copy.codeCopied);
    } catch {
      toast.error(copy.failed);
    }
  };

  return (
    <FormSheet
      open={flow !== null}
      onOpenChange={(open) => !open && onCancel()}
      title={copy.connectTitle}
      description={copy.enterCode}
    >
      {flow && (
        <div className="flex flex-col gap-lg">
          <button
            type="button"
            onClick={copyCode}
            aria-label={copy.codeCopied}
            className="flex items-center justify-center gap-md rounded-menu bg-cell py-lg font-mono text-display tracking-[0.2em] hover:bg-cell-high"
          >
            {flow.userCode}
            <Icon name="copy" size="lg" className="text-text-secondary" />
          </button>
          <Button asChild fullWidth>
            <a
              href={flow.verificationUriComplete ?? flow.verificationUri}
              target="_blank"
              rel="noopener noreferrer"
            >
              {copy.openGithub}
              <Icon name="openExternal" size="sm" />
            </a>
          </Button>
          <div className="flex items-center justify-center gap-sm text-body-small text-text-secondary">
            <DotLoader />
            <span>{copy.waiting}</span>
          </div>
          <Button variant="ghost" fullWidth onClick={onCancel}>
            {copy.cancel}
          </Button>
        </div>
      )}
    </FormSheet>
  );
}
