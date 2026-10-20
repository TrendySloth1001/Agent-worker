import { AUTH_COPY } from "./copy";

export type AuthMode = "login" | "register";

export interface AuthFields {
  name: string;
  email: string;
  password: string;
  confirm: string;
}

export type FieldErrors = Partial<Record<keyof AuthFields, string>>;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PASSWORD_MIN = 8;

export function validateAuth(mode: AuthMode, fields: AuthFields): FieldErrors {
  const errors: FieldErrors = {};
  if (!EMAIL_PATTERN.test(fields.email.trim())) errors.email = AUTH_COPY.errEmail;
  if (mode === "login") {
    if (fields.password === "") errors.password = AUTH_COPY.errPassword;
    return errors;
  }
  if (fields.name.trim() === "") errors.name = AUTH_COPY.errName;
  if (fields.password.length < PASSWORD_MIN) errors.password = AUTH_COPY.errPasswordShort;
  if (fields.confirm !== fields.password) errors.confirm = AUTH_COPY.errConfirm;
  return errors;
}
