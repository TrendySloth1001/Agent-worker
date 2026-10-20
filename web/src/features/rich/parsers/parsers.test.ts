import { describe, expect, it } from "vitest";
import { parseChart, chartToCsv } from "./chart";
import { emailAsText, parseAsk, parseEmail, parseMessage, parseSpec } from "./drafts";
import { parseIntentCard } from "./intent-card";
import { parsePlaylist } from "./playlist";
import {
  parseCalc,
  parseChecklist,
  parseFlashcards,
  parseQuiz,
  parseStats,
  parseTimeline,
} from "./playful";
import { parseCompare, parseFlow, parseProgress, parseTree } from "./structure";

describe("chart", () => {
  it("parses a bar chart and tolerates trailing commas", () => {
    const spec = parseChart(
      '{"type":"bar","x":["a","b"],"series":[{"name":"s","data":[1,"2",],}],}',
    );
    expect(spec?.kind).toBe("bar");
    expect(spec?.series[0]?.values).toEqual([1, 2]);
  });

  it("maps aliases, builds pie slices and groups the long tail", () => {
    const x = Array.from({ length: 14 }, (_, i) => `s${i}`);
    const data = Array.from({ length: 14 }, (_, i) => i + 1);
    const spec = parseChart(JSON.stringify({ type: "doughnut", x, series: [{ name: "v", data }] }));
    expect(spec?.kind).toBe("donut");
    expect(spec?.slices).toHaveLength(12);
    expect(spec?.slices.at(-1)?.label).toBe("Other");
  });

  it("rejects payloads that cannot be drawn", () => {
    expect(parseChart("not json")).toBeNull();
    expect(parseChart('{"type":"bar","series":[]}')).toBeNull();
    expect(parseChart('{"type":"radar","x":["a","b"],"series":[{"data":[1,2]}]}')).toBeNull();
    expect(parseChart('{"type":"scatter","series":[{"data":[]}]}')).toBeNull();
  });

  it("exports csv", () => {
    const spec = parseChart('{"type":"line","x":["a"],"series":[{"name":"n","data":[3]}]}');
    expect(spec && chartToCsv(spec)).toBe(",n\na,3");
  });
});

describe("playful blocks", () => {
  it("parses a quiz with the starred answer", () => {
    const quiz = parseQuiz("title: T\nq: Q1?\na: x\na: *y\nwhy: because");
    expect(quiz?.questions[0]).toMatchObject({ answer: 1, why: "because" });
  });

  it("drops a quiz question without a correct answer", () => {
    expect(parseQuiz("q: Q?\na: x\na: y")).toBeNull();
  });

  it("parses flashcards, timeline, checklist", () => {
    expect(parseFlashcards("card: a | b")?.cards).toEqual([{ front: "a", back: "b" }]);
    expect(parseTimeline("1991 | Web | detail")?.events[0]).toEqual({
      when: "1991",
      title: "Web",
      detail: "detail",
    });
    expect(parseChecklist("[x] done\n[ ] todo")?.items.map((i) => i.done)).toEqual([true, false]);
  });

  it("parses stats with sparklines", () => {
    const stats = parseStats("stat: Rev | 1M | +2% | up\nspark: Rev | 1,2,3");
    expect(stats?.stats[0]).toMatchObject({ direction: "up", spark: [1, 2, 3] });
  });

  it("parses a calculator and clamps the default into range", () => {
    const calc = parseCalc("input: a | A | 500 | 0..100 | $\nout: Double | a*2 | $ | 1");
    expect(calc?.inputs[0]?.value).toBe(100);
    expect(calc?.outputs[0]?.decimals).toBe(1);
    expect(parseCalc("input: 9bad | A | 1 | 0..2 |\nout: x | 1 | |")).toBeNull();
  });
});

describe("structure blocks", () => {
  it("parses compare options with pros and cons", () => {
    const data = parseCompare("option: A | tag | pick\n+ good\n- bad\noption: B");
    expect(data?.options[0]).toMatchObject({ pick: true, pros: ["good"], cons: ["bad"] });
    expect(data?.options).toHaveLength(2);
  });

  it("parses progress bars and ratings", () => {
    const data = parseProgress("bar: Course | 72 | 100 | note\nrating: Fun | 4 | 5");
    expect(data?.rows.map((r) => r.kind)).toEqual(["bar", "rating"]);
  });

  it("builds a tree by indentation", () => {
    const tree = parseTree("Root\n  a\n    b\n  c");
    expect(tree?.root.children.map((c) => c.label)).toEqual(["a", "c"]);
    expect(tree?.root.children[0]?.children[0]?.label).toBe("b");
  });

  it("parses flow rows and boxes", () => {
    const flow = parseFlow("title: T\nrow: 1 | a ; 2 | b\nbox: X | y | accent");
    expect(flow?.stages[0]).toMatchObject({ kind: "row" });
    expect(flow?.stages[1]).toMatchObject({ kind: "box", accent: true });
  });
});

describe("draft blocks", () => {
  it("parses an email and strips markdown from the body", () => {
    const draft = parseEmail("To: a@b.co\nSubject: Hi\n\n**Hello**\n- one");
    expect(draft).toMatchObject({ to: "a@b.co", subject: "Hi", body: "Hello\n• one" });
    expect(draft && emailAsText(draft)).toBe("To: a@b.co\nSubject: Hi\n\nHello\n• one");
  });

  it("rejects an email without headers", () => {
    expect(parseEmail("just text")).toBeNull();
  });

  it("parses messages, spec cards and ask blocks", () => {
    expect(parseMessage("To: Bob\nPlatform: Slack\n\nhey")).toEqual({
      to: "Bob",
      platform: "slack",
      text: "hey",
    });
    expect(parseMessage("To: Bob")).toBeNull();
    expect(parseSpec("title: PG\nPort: 5432")?.rows).toEqual([{ key: "Port", value: "5432" }]);
    expect(parseAsk("question: Q?\n- a\n- b\nmulti: true")).toMatchObject({
      multi: true,
      options: ["a", "b"],
    });
    expect(parseAsk("question: Q?\n- a")).toBeNull();
  });
});

describe("action cards and playlists", () => {
  const card = {
    v: 1,
    type: "place",
    title: "Cafe",
    actions: [
      {
        id: "d",
        label: "Go",
        app: "maps",
        intent: { action: "view", uri: "https://www.google.com/maps" },
      },
    ],
  };

  it("validates an action card", () => {
    expect(parseIntentCard(JSON.stringify(card))?.title).toBe("Cafe");
    expect(parseIntentCard(JSON.stringify({ ...card, actions: [] }))).toBeNull();
    expect(
      parseIntentCard(
        JSON.stringify({
          ...card,
          actions: [{ ...card.actions[0], intent: { action: "rm -rf" } }],
        }),
      ),
    ).toBeNull();
  });

  it("parses a playlist block", () => {
    const list = parsePlaylist("title: Mix\napp: Spotify Web\n- A | B\n2) C | D");
    expect(list).toEqual({
      title: "Mix",
      app: "spotify_web",
      items: [
        { title: "A", artist: "B" },
        { title: "C", artist: "D" },
      ],
    });
    expect(parsePlaylist("title: Empty")).toBeNull();
  });
});
