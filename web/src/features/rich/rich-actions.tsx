"use client";

import { createContext, useContext, type ReactNode } from "react";

export interface RichActions {
  sendMessage?: (text: string) => void;
}

const RichActionsContext = createContext<RichActions>({});

export function RichActionsProvider({
  value,
  children,
}: {
  value: RichActions;
  children: ReactNode;
}) {
  return <RichActionsContext value={value}>{children}</RichActionsContext>;
}

export function useRichActions(): RichActions {
  return useContext(RichActionsContext);
}
