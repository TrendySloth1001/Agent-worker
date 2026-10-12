/**
 * Gives extracted plain text (PDF pages, spreadsheets, .txt) heading structure
 * so the Markdown chunker can split on sections and store heading paths.
 * Text that already has Markdown headings (.md, converted .docx) is left alone
 * apart from the page / sheet markers.
 */
export function structureText(text: string): string {
  let t = text.replace(/\r\n/g, "\n");
  t = t.replace(/^--- Page (\d+) ---$/gm, "## Page $1").replace(/^--- Sheet: (.+) ---$/gm, "## Sheet: $1");
  const hasMd = /^#{1,6}\s+\S/m.test(t.replace(/^## (Page \d+|Sheet: .+)$/gm, ""));
  if (hasMd) return t;
  const lines = t.split("\n");
  let sawPage = false;
  return lines
    .map((line, i) => {
      if (/^## Page \d+$/.test(line)) sawPage = true;
      const s = line.trim();
      if (!s || s.length > 80 || /[.!?,;:]$/.test(s) || s.startsWith("#")) return line;
      const prevBlank = i === 0 || lines[i - 1].trim() === "" || /^## (Page \d+|Sheet: .+)$/.test(lines[i - 1]);
      // "1. Introduction", "2.3 Results": numbered heading
      const num = s.match(/^(\d{1,2}(?:\.\d{1,2}){0,3})\.?\s+\p{Lu}[\p{L}\p{N} ,&/'()-]{2,}$/u);
      if (num && s.split(/\s+/).length <= 10) return `${"#".repeat(Math.min(2 + num[1].split(".").length - (sawPage ? 0 : 1), 5))} ${s}`;
      // "INTRODUCTION": all-caps line standing on its own
      if (prevBlank && /^[\p{Lu}\p{N} &/'-]{4,}$/u.test(s) && /\p{Lu}{3}/u.test(s) && s.split(/\s+/).length <= 8) return `${sawPage ? "###" : "##"} ${s}`;
      return line;
    })
    .join("\n");
}
