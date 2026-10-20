export type ChangeKind = "added" | "improved" | "fixed";

export interface Change {
  kind: ChangeKind;
  title: string;
  detail: string;
}

export interface Release {
  version: string;
  date: string;
  headline: string;
  items: ReadonlyArray<Change>;
}

export const RELEASES: ReadonlyArray<Release> = [
  {
    version: "1.13.1",
    date: "15 Oct 2026",
    headline: "Knows where you are, roughly",
    items: [
      {
        kind: "added",
        title: "Local answers",
        detail:
          "Weather, prices, places and news fit your city or state, with no location permission.",
      },
    ],
  },
  {
    version: "1.13.0",
    date: "15 Oct 2026",
    headline: "Tap to do it",
    items: [
      {
        kind: "added",
        title: "Playlists",
        detail:
          "Song suggestions arrive as a playlist: covers, previews and open in your music app.",
      },
      {
        kind: "added",
        title: "Action cards",
        detail: "Directions, calendar events, alarms, timers and more, ready in one tap.",
      },
    ],
  },
  {
    version: "1.12.2",
    date: "15 Oct 2026",
    headline: "Drive, opened up",
    items: [
      {
        kind: "added",
        title: "Drive previews",
        detail: "Open files from Google Drive right inside a chat.",
      },
      {
        kind: "added",
        title: "Pick folders",
        detail: "Choose whole folders for sparky to read.",
      },
    ],
  },
  {
    version: "1.12.0",
    date: "15 Oct 2026",
    headline: "See it before you ask",
    items: [
      { kind: "added", title: "File previews", detail: "Look at a file before you ask about it." },
      { kind: "added", title: "Ask about a file", detail: "Ask sparky about any file you shared." },
      {
        kind: "improved",
        title: "Smoother Drive picking",
        detail: "Choosing files from Drive takes fewer taps.",
      },
    ],
  },
  {
    version: "1.10.0",
    date: "15 Oct 2026",
    headline: "Straight answers",
    items: [
      {
        kind: "improved",
        title: "Answers get to the point",
        detail: "Shorter replies that start with the answer.",
      },
      {
        kind: "fixed",
        title: "Real model names",
        detail: "Each reply shows the model that wrote it.",
      },
    ],
  },
];
