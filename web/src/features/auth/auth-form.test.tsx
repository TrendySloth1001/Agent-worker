import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { AuthForm } from "./auth-form";
import { AUTH_COPY } from "./copy";

vi.mock("next/navigation", () => ({ useRouter: () => ({ replace: vi.fn(), refresh: vi.fn() }) }));

describe("AuthForm", () => {
  it("keeps what the user types", async () => {
    render(
      <QueryClientProvider client={new QueryClient()}>
        <AuthForm next="/chat" githubEnabled={false} />
      </QueryClientProvider>,
    );
    const email = screen.getByPlaceholderText(AUTH_COPY.emailHint);
    const password = screen.getByPlaceholderText(AUTH_COPY.passwordHint);
    await userEvent.type(email, "me@example.test");
    await userEvent.type(password, "secret-pass");
    expect(email).toHaveProperty("value", "me@example.test");
    expect(password).toHaveProperty("value", "secret-pass");
  });
});
