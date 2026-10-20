import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

const FONT_SIZES = [
  "caption",
  "label",
  "body-small",
  "body",
  "title",
  "metric",
  "headline",
  "display",
  "display-large",
];

const RADII = ["none", "sm", "md", "lg", "pill", "field", "dialog", "sheet", "menu", "card"];

const SPACING = [
  "xxs",
  "xs",
  "sm",
  "md",
  "lg",
  "xl",
  "xxl",
  "xxxl",
  "button-height",
  "input-height",
  "row-height",
  "min-tap",
  "toggle-width",
  "toggle-height",
  "toggle-knob",
  "sheet-handle-width",
  "chip-height",
  "segment-height",
  "icon-circle",
  "icon-glyph",
  "avatar",
  "group-gap",
  "touch-target",
];

const merge = extendTailwindMerge({
  extend: {
    theme: { spacing: SPACING },
    classGroups: {
      "font-size": [{ text: FONT_SIZES }],
      rounded: [{ rounded: RADII }],
    },
  },
});

export const cn = (...inputs: ClassValue[]): string => merge(clsx(inputs));
