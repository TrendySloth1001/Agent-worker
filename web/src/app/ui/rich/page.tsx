import type { Metadata } from "next";
import Link from "next/link";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { Wordmark } from "@/components/brand/wordmark";
import { RichBlock } from "@/features/rich";
import { playlistKeys } from "@/features/rich/lib/playlist-api";
import { parsePlaylist } from "@/features/rich/parsers/playlist";
import { FixtureQueryProvider } from "../_fixtures/fixture-query-provider";
import { RichFixture } from "./rich-fixture";
import { RICH_SAMPLES } from "./samples";

export const metadata: Metadata = { title: "sparky rich blocks" };

const PLAYLIST = RICH_SAMPLES.find((sample) => sample.lang === "sparky-playlist");
const SONGS = PLAYLIST ? (parsePlaylist(PLAYLIST.code)?.items ?? []) : [];

const TRACKS = SONGS.map((song, index) => ({
  ...song,
  art: `https://picsum.photos/seed/sparky-${index}/300`,
  durationMs: 215_000 + index * 17_000,
  album: "Fixture album",
  year: 2013 + index,
  link: "https://music.apple.com/",
}));

export default function RichFixturePage() {
  return (
    <FixtureQueryProvider
      seeds={[
        [playlistKeys.tracks(SONGS), TRACKS],
        [playlistKeys.playAll(SONGS), "https://www.youtube.com/watch_videos?video_ids=a,b,c"],
      ]}
    >
      <RichFixture>
        <main className="mx-auto flex max-w-[44rem] flex-col gap-lg px-lg py-xl">
          <header className="flex items-center justify-between gap-md">
            <Link href="/ui">
              <Wordmark className="text-headline" />
            </Link>
            <ThemeToggle />
          </header>
          {RICH_SAMPLES.map((sample) => (
            <section key={sample.title} className="flex flex-col gap-xs">
              <h2 className="font-mono text-caption tracking-[0.14em] text-text-tertiary uppercase">
                {sample.title}
              </h2>
              <RichBlock lang={sample.lang} code={sample.code} />
            </section>
          ))}
        </main>
      </RichFixture>
    </FixtureQueryProvider>
  );
}
