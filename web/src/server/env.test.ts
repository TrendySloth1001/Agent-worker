// @vitest-environment node
import { describe, expect, it } from "vitest";
import { parseEnv } from "./env";

describe("parseEnv", () => {
  it("defaults to the production API and trims trailing slashes", () => {
    expect(parseEnv({}).apiUrl).toBe("https://sparky.cloudnsofts.com");
    expect(parseEnv({ SPARKY_API_URL: "http://localhost:8080//" }).apiUrl).toBe(
      "http://localhost:8080",
    );
  });

  it("treats blank values as unset", () => {
    expect(
      parseEnv({ SPARKY_API_URL: "", APP_ORIGIN: "", SESSION_COOKIE_SECURE: "" }),
    ).toMatchObject({ apiUrl: "https://sparky.cloudnsofts.com", appOrigin: undefined });
  });

  it("marks cookies Secure in production unless overridden", () => {
    expect(parseEnv({ NODE_ENV: "production" }).cookieSecure).toBe(true);
    expect(parseEnv({ NODE_ENV: "development" }).cookieSecure).toBe(false);
    expect(parseEnv({ NODE_ENV: "production", SESSION_COOKIE_SECURE: "false" }).cookieSecure).toBe(
      false,
    );
  });

  it("rejects an invalid API URL", () => {
    expect(() => parseEnv({ SPARKY_API_URL: "nope" })).toThrow();
  });
});
