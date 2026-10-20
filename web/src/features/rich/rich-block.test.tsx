import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { asRichLang, isRichLang, RICH_LANGS } from "./langs";
import { RENDERERS } from "./registry";
import { RichBlock } from "./rich-block";

describe("language routing", () => {
  it("routes every rich language and nothing else", () => {
    for (const lang of RICH_LANGS) expect(isRichLang(lang)).toBe(true);
    expect(isRichLang(" Chart ")).toBe(true);
    for (const lang of ["ts", "python", "", "constructor", "__proto__", "github-repo"])
      expect(isRichLang(lang)).toBe(false);
    expect(asRichLang("SPARKY-CARD")).toBe("sparky-card");
  });

  it("has a renderer for each language", () => {
    expect(Object.keys(RENDERERS).sort()).toEqual([...RICH_LANGS].sort());
  });
});

describe("RichBlock", () => {
  it("renders a valid block as a card", async () => {
    render(<RichBlock lang="checklist" code={"title: Pack\n[ ] Passport\n[x] Charger"} />);
    expect(screen.getByText("Pack")).toBeInTheDocument();
    const boxes = screen.getAllByRole("checkbox");
    expect(boxes[0]).toHaveAttribute("aria-checked", "false");
    await userEvent.click(boxes[0] as HTMLElement);
    expect(boxes[0]).toHaveAttribute("aria-checked", "true");
  });

  it("falls back to a plain code block for an invalid payload", () => {
    render(<RichBlock lang="chart" code={'{"type":"bar","series":"oops"'} />);
    expect(screen.getByText('{"type":"bar","series":"oops"')).toBeInTheDocument();
    expect(screen.getByText("chart")).toBeInTheDocument();
  });

  it("falls back for an unknown language", () => {
    render(<RichBlock lang="ts" code="const a = 1;" />);
    expect(screen.getByText("const a = 1;")).toBeInTheDocument();
  });

  it("shows only safe links on action cards", () => {
    const card = {
      v: 1,
      type: "product",
      title: "Gadget",
      actions: [
        {
          id: "a",
          label: "Good",
          app: "",
          intent: { action: "view", uri: "https://www.amazon.in/s?k=x" },
        },
        { id: "b", label: "Evil", app: "", intent: { action: "view", uri: "javascript:alert(1)" } },
      ],
    };
    render(<RichBlock lang="sparky-card" code={JSON.stringify(card)} />);
    expect(screen.getByRole("link", { name: "Good" })).toHaveAttribute(
      "href",
      "https://www.amazon.in/s?k=x",
    );
    expect(screen.queryByText("Evil")).not.toBeInTheDocument();
  });
});
