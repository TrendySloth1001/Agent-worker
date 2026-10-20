"use client";

import { useId, useState, type ComponentProps } from "react";
import { Icon } from "@/components/ui/icon";
import { IconButton } from "@/components/ui/icon-button";
import type { IconName } from "@/components/ui/icons";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/cn";
import { AUTH_COPY } from "./copy";

interface AuthFieldProps extends Omit<ComponentProps<"input">, "id"> {
  label: string;
  icon: IconName;
  error?: string;
  reveal?: boolean;
}

export function AuthField({
  label,
  icon,
  error,
  reveal = false,
  className,
  ...props
}: AuthFieldProps) {
  const id = useId();
  const errorId = `${id}-error`;
  const [shown, setShown] = useState(false);
  return (
    <div className="flex flex-col gap-xs">
      <label htmlFor={id} className="sr-only">
        {label}
      </label>
      <div className="relative">
        <Icon
          name={icon}
          className="pointer-events-none absolute top-1/2 left-lg -translate-y-1/2 text-text-tertiary"
        />
        <Input
          id={id}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? errorId : undefined}
          className={cn("pl-[3.25rem]", reveal && "pr-14", className)}
          {...props}
          type={reveal && shown ? "text" : props.type}
        />
        {reveal && (
          <IconButton
            variant="ghost"
            icon={shown ? "hide" : "show"}
            label={shown ? AUTH_COPY.hide : AUTH_COPY.show}
            onClick={() => setShown((v) => !v)}
            className="absolute top-1/2 right-xs -translate-y-1/2"
          />
        )}
      </div>
      {error && (
        <p id={errorId} className="px-lg text-caption text-error">
          {error}
        </p>
      )}
    </div>
  );
}
