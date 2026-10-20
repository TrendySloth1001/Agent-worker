"use client";

import { useQuery } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { Icon } from "@/components/ui/icon";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/cn";
import { fetchPlayAll, fetchTracks, playlistKeys } from "../lib/playlist-api";
import { safeWebUrl } from "../lib/safe-url";
import type { PlaylistData, PlaylistTrack } from "../parsers/playlist";
import { RichFrame } from "./frame";

const HOUR = 60 * 60 * 1000;

function duration(ms: number | undefined): string {
  if (!ms) return "";
  const total = Math.round(ms / 1000);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

export function PlaylistCard({ data }: { data: PlaylistData }) {
  const tracksQuery = useQuery({
    queryKey: playlistKeys.tracks(data.items),
    queryFn: () => fetchTracks(data.items),
    staleTime: HOUR,
    retry: 1,
  });
  const playAllQuery = useQuery({
    queryKey: playlistKeys.playAll(data.items),
    queryFn: () => fetchPlayAll(data.items),
    staleTime: HOUR,
    retry: 1,
  });
  const audio = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState<number | null>(null);

  useEffect(() => {
    const element = audio.current;
    return () => element?.pause();
  }, []);

  const tracks: PlaylistTrack[] = tracksQuery.data ?? data.items.map((song) => ({ ...song }));
  const playAll = safeWebUrl(playAllQuery.data);

  function toggle(index: number, url: string) {
    const player = audio.current;
    if (!player) return;
    if (playing === index) {
      player.pause();
      setPlaying(null);
      return;
    }
    player.src = url;
    void player.play().then(
      () => setPlaying(index),
      () => setPlaying(null),
    );
  }

  return (
    <RichFrame
      label={data.title}
      flush
      trailing={
        playAll && (
          <a
            href={playAll}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-xs font-mono text-caption tracking-[0.08em] text-accent-text uppercase hover:underline"
          >
            <Icon name="play" size="sm" />
            Play all
          </a>
        )
      }
    >
      <audio ref={audio} onEnded={() => setPlaying(null)} className="hidden" />
      <ul>
        {tracks.map((track, index) => {
          const art = safeWebUrl(track.art);
          const preview = safeWebUrl(track.previewUrl);
          const link = safeWebUrl(track.link);
          const loading = tracksQuery.isPending;
          return (
            <li
              key={`${track.title}-${index}`}
              className="flex items-center gap-md border-t border-border px-md py-sm first:border-t-0"
            >
              <span
                role="img"
                aria-label={art ? `Cover of ${track.title}` : ""}
                className="flex size-11 shrink-0 items-center justify-center overflow-hidden rounded-sm bg-surface-high bg-cover bg-center"
                style={art ? { backgroundImage: `url("${art}")` } : undefined}
              >
                {!art &&
                  (loading ? (
                    <Skeleton className="size-full" />
                  ) : (
                    <Icon name="audio" size="sm" className="text-text-tertiary" />
                  ))}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-body-small font-medium">{track.title}</p>
                <p className="truncate text-label text-text-secondary">
                  {[track.artist, track.album, track.year].filter(Boolean).join(" · ")}
                </p>
              </div>
              {track.durationMs ? (
                <span className="font-mono text-caption text-text-tertiary">
                  {duration(track.durationMs)}
                </span>
              ) : null}
              {preview && (
                <button
                  type="button"
                  onClick={() => toggle(index, preview)}
                  aria-label={
                    playing === index ? `Pause ${track.title}` : `Play preview of ${track.title}`
                  }
                  className={cn(
                    "flex size-9 shrink-0 items-center justify-center rounded-full border border-border-strong",
                    "duration-fast transition-colors ease-standard hover:border-text-primary",
                    playing === index && "border-accent text-accent-text",
                  )}
                >
                  <Icon name={playing === index ? "pause" : "play"} size="sm" />
                </button>
              )}
              {link && (
                <a
                  href={link}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label={`Open ${track.title}`}
                  className="flex size-9 shrink-0 items-center justify-center rounded-full text-text-secondary hover:bg-surface-raised hover:text-text-primary"
                >
                  <Icon name="openExternal" size="sm" />
                </a>
              )}
            </li>
          );
        })}
      </ul>
    </RichFrame>
  );
}
