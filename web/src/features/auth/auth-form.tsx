"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { Button } from "@/components/ui/button";
import { Divider } from "@/components/ui/divider";
import { Icon } from "@/components/ui/icon";
import { ApiError, authApi } from "@/lib/api/client";
import { ME_KEY } from "@/lib/api/use-me";
import { authResultSchema, type LoginInput, type RegisterInput } from "@/lib/api/schemas";
import { AuthField } from "./auth-field";
import { AUTH_COPY } from "./copy";
import { validateAuth, type AuthFields, type AuthMode, type FieldErrors } from "./validation";

interface AuthFormProps {
  next: string;
  notice?: string;
  githubEnabled: boolean;
}

const EMPTY: AuthFields = { name: "", email: "", password: "", confirm: "" };

export function AuthForm({ next, notice, githubEnabled }: AuthFormProps) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [mode, setMode] = useState<AuthMode>("login");
  const [fields, setFields] = useState<AuthFields>(EMPTY);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [formError, setFormError] = useState<string | undefined>(notice);

  const submit = useMutation({
    mutationFn: (): Promise<unknown> => {
      if (mode === "login") {
        const body: LoginInput = { email: fields.email.trim(), password: fields.password };
        return authApi.post("/login", authResultSchema, { body });
      }
      const body: RegisterInput = {
        name: fields.name.trim(),
        email: fields.email.trim(),
        password: fields.password,
      };
      return authApi.post("/register", authResultSchema, { body });
    },
    onSuccess: () => {
      queryClient.removeQueries({ queryKey: ME_KEY });
      router.replace(next);
      router.refresh();
    },
    onError: (error) => {
      setFormError(error instanceof ApiError ? error.message : AUTH_COPY.errNetwork);
    },
  });

  const register = mode === "register";
  const pending = submit.isPending || submit.isSuccess;

  const update = (key: keyof AuthFields) => (event: FormEvent<HTMLInputElement>) => {
    setFields((prev) => ({ ...prev, [key]: event.currentTarget.value }));
    setErrors((prev) => ({ ...prev, [key]: undefined }));
  };

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setFormError(undefined);
    const found = validateAuth(mode, fields);
    setErrors(found);
    if (Object.keys(found).length === 0) submit.mutate();
  };

  const toggle = () => {
    setMode(register ? "login" : "register");
    setErrors({});
    setFormError(undefined);
  };

  return (
    <div className="flex flex-col gap-lg">
      <form onSubmit={onSubmit} noValidate className="flex flex-col gap-md">
        {formError && (
          <p
            role="alert"
            className="rounded-card border border-error bg-surface px-lg py-md text-body-small text-error"
          >
            {formError}
          </p>
        )}
        {register && (
          <AuthField
            label={AUTH_COPY.name}
            icon="profileName"
            placeholder={AUTH_COPY.nameHint}
            autoComplete="name"
            value={fields.name}
            onInput={update("name")}
            error={errors.name}
            disabled={pending}
          />
        )}
        <AuthField
          label={AUTH_COPY.email}
          icon="email"
          type="email"
          placeholder={AUTH_COPY.emailHint}
          autoComplete={register ? "email" : "username"}
          inputMode="email"
          value={fields.email}
          onInput={update("email")}
          error={errors.email}
          disabled={pending}
        />
        <AuthField
          label={AUTH_COPY.password}
          icon="password"
          type="password"
          reveal
          placeholder={register ? AUTH_COPY.newPasswordHint : AUTH_COPY.passwordHint}
          autoComplete={register ? "new-password" : "current-password"}
          value={fields.password}
          onInput={update("password")}
          error={errors.password}
          disabled={pending}
        />
        {register && (
          <AuthField
            label={AUTH_COPY.confirm}
            icon="password"
            type="password"
            reveal
            placeholder={AUTH_COPY.confirmHint}
            autoComplete="new-password"
            value={fields.confirm}
            onInput={update("confirm")}
            error={errors.confirm}
            disabled={pending}
          />
        )}
        <Button type="submit" size="lg" fullWidth disabled={pending} className="mt-sm">
          {register
            ? pending
              ? AUTH_COPY.creatingAccount
              : AUTH_COPY.createAccount
            : pending
              ? AUTH_COPY.signingIn
              : AUTH_COPY.signIn}
        </Button>
      </form>

      {githubEnabled && (
        <>
          <div className="flex items-center gap-md text-caption text-text-tertiary uppercase">
            <Divider className="flex-1" />
            {AUTH_COPY.or}
            <Divider className="flex-1" />
          </div>
          <Button asChild variant="secondary" size="lg" fullWidth aria-disabled={pending}>
            <a href={`/api/auth/github/start?next=${encodeURIComponent(next)}`}>
              <Icon name="github" />
              {AUTH_COPY.continueWithGithub}
            </a>
          </Button>
        </>
      )}

      <p className="text-center text-body-small text-text-secondary">
        {register ? AUTH_COPY.haveAccount : AUTH_COPY.noAccount}{" "}
        <button
          type="button"
          onClick={toggle}
          disabled={pending}
          className="font-semibold text-text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          {register ? AUTH_COPY.signIn : AUTH_COPY.createAccount}
        </button>
      </p>
    </div>
  );
}
