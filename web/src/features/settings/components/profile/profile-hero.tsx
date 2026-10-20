"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRef, useState, type ChangeEvent } from "react";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ProfileAura } from "@/components/ui/profile-aura";
import { Tag } from "@/components/ui/tag";
import { toast } from "@/components/ui/toaster";
import { updateProfile } from "../../api/account";
import { errorMessage } from "../../api/http";
import { settingsKeys } from "../../api/query-keys";
import { PROFILE_COPY } from "../../content/copy";
import { fileToAvatar, isAcceptedImage } from "../../lib/avatar-image";
import { nameSchema, type User } from "../../schemas/account";
import { FieldError } from "../form-sheet";

export function ProfileHero({ user }: { user: User }) {
  const queryClient = useQueryClient();
  const fileInput = useRef<HTMLInputElement>(null);
  const [name, setName] = useState(user.name ?? "");
  const [problem, setProblem] = useState<string | null>(null);

  const save = useMutation({
    mutationFn: updateProfile,
    onSuccess: (data, patch) => {
      queryClient.setQueryData(settingsKeys.me, data);
      toast.success(patch.name !== undefined ? PROFILE_COPY.nameSaved : PROFILE_COPY.photoSaved);
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const submitName = () => {
    const parsed = nameSchema.safeParse(name);
    if (!parsed.success) return setProblem(parsed.error.issues[0]?.message ?? null);
    setProblem(null);
    save.mutate({ name: parsed.data });
  };

  const pickPhoto = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    if (!isAcceptedImage(file.type)) return toast.error(PROFILE_COPY.photoInvalid);
    const avatar = await fileToAvatar(file).catch(() => null);
    if (!avatar) return toast.error(PROFILE_COPY.photoTooBig);
    save.mutate({ avatar });
  };

  const display = user.name ?? user.email ?? "";

  return (
    <section className="flex flex-col items-center gap-lg">
      <ProfileAura size={200}>
        <Avatar name={display} src={user.avatarUrl ?? undefined} size={96} />
      </ProfileAura>
      <div className="-mt-xl flex flex-col items-center gap-xs text-center">
        <Tag accent={user.role === "owner"}>
          {user.role === "owner" ? PROFILE_COPY.roleOwner : PROFILE_COPY.roleMember}
        </Tag>
        {user.email && <p className="text-body-small text-text-secondary">{user.email}</p>}
      </div>
      <div className="flex flex-wrap justify-center gap-sm">
        <input
          ref={fileInput}
          type="file"
          accept="image/png,image/jpeg,image/webp"
          className="sr-only"
          aria-label={PROFILE_COPY.changePhoto}
          tabIndex={-1}
          onChange={pickPhoto}
        />
        <Button
          size="sm"
          variant="secondary"
          onClick={() => fileInput.current?.click()}
          disabled={save.isPending}
        >
          {PROFILE_COPY.changePhoto}
        </Button>
        {user.avatarUrl && (
          <Button
            size="sm"
            variant="ghost"
            onClick={() => save.mutate({ avatar: null })}
            disabled={save.isPending}
          >
            {PROFILE_COPY.removePhoto}
          </Button>
        )}
      </div>
      <form
        className="flex w-full flex-col gap-sm"
        onSubmit={(event) => {
          event.preventDefault();
          submitName();
        }}
      >
        <label
          htmlFor="profile-name"
          className="px-xs font-mono text-caption tracking-[0.08em] text-text-secondary uppercase"
        >
          {PROFILE_COPY.nameLabel}
        </label>
        <div className="flex gap-sm">
          <Input
            id="profile-name"
            value={name}
            maxLength={60}
            aria-invalid={problem !== null}
            onChange={(event) => setName(event.target.value)}
            autoComplete="name"
          />
          <Button type="submit" disabled={save.isPending || name.trim() === (user.name ?? "")}>
            {PROFILE_COPY.saveName}
          </Button>
        </div>
        {problem && <FieldError>{problem}</FieldError>}
      </form>
    </section>
  );
}
