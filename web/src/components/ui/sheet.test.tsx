import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { Sheet, SheetContent, SheetDescription, SheetTitle, SheetTrigger } from "./sheet";

describe("Sheet", () => {
  it("opens from its trigger and shows content", async () => {
    render(
      <Sheet>
        <SheetTrigger>Open</SheetTrigger>
        <SheetContent>
          <SheetTitle>Hello</SheetTitle>
          <SheetDescription>Body</SheetDescription>
        </SheetContent>
      </Sheet>,
    );
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    await userEvent.click(screen.getByText("Open"));
    expect(screen.getByRole("dialog", { name: "Hello" })).toBeInTheDocument();
  });

  it("closes on escape", async () => {
    render(
      <Sheet defaultOpen>
        <SheetContent>
          <SheetTitle>Hello</SheetTitle>
          <SheetDescription>Body</SheetDescription>
        </SheetContent>
      </Sheet>,
    );
    await userEvent.keyboard("{Escape}");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });
});
