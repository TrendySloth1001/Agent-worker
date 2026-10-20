import Image from "next/image";
import { cn } from "@/lib/cn";

export const ILLUSTRATIONS = {
  think: "/illustrations/home_think.svg",
  chat: "/illustrations/home_chat.svg",
  hello: "/illustrations/hello.svg",
  emptyHistory: "/illustrations/empty_history.svg",
} as const;

export type IllustrationName = keyof typeof ILLUSTRATIONS;

const ASPECT = 1.3;

interface IllustrationProps {
  name: IllustrationName;
  height?: number;
  className?: string;
}

export function Illustration({ name, height = 150, className }: IllustrationProps) {
  return (
    <Image
      src={ILLUSTRATIONS[name]}
      alt=""
      width={Math.round(height * ASPECT)}
      height={height}
      unoptimized
      className={cn("illustration mx-auto object-contain", className)}
      style={{ height }}
    />
  );
}
