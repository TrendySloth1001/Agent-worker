import { describe, expect, it } from "vitest";
import { validateAuth } from "./validation";

const fields = {
  name: "Ada",
  email: "ada@example.com",
  password: "longenough",
  confirm: "longenough",
};

describe("validateAuth", () => {
  it("accepts valid sign-in and sign-up input", () => {
    expect(validateAuth("login", { ...fields, name: "", confirm: "" })).toEqual({});
    expect(validateAuth("register", fields)).toEqual({});
  });

  it("flags a bad email and an empty password on sign-in", () => {
    expect(validateAuth("login", { ...fields, email: "nope", password: "" })).toEqual({
      email: "Enter a valid email.",
      password: "Enter your password.",
    });
  });

  it("checks name, length and confirmation on sign-up", () => {
    expect(
      validateAuth("register", { ...fields, name: " ", password: "short", confirm: "other" }),
    ).toEqual({
      name: "Enter your name.",
      password: "Use at least 8 characters.",
      confirm: "Passwords do not match.",
    });
  });
});
