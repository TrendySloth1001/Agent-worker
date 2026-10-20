"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useState } from "react";
import { pollGithub, startGithub } from "../../api/connections";
import { errorMessage } from "../../api/http";
import { settingsKeys } from "../../api/query-keys";
import { CONNECTIONS_COPY } from "../../content/copy";
import type { DeviceFlow } from "../../schemas/connections";

const MIN_INTERVAL_S = 5;

export interface GithubFlowState {
  flow: DeviceFlow | null;
  starting: boolean;
  problem: string | null;
  start: () => Promise<void>;
  cancel: () => void;
}

export function useGithubFlow(): GithubFlowState {
  const queryClient = useQueryClient();
  const [flow, setFlow] = useState<DeviceFlow | null>(null);
  const [starting, setStarting] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  const cancel = useCallback(() => {
    setFlow(null);
    setProblem(null);
  }, []);

  const start = useCallback(async () => {
    setStarting(true);
    setProblem(null);
    try {
      setFlow(await startGithub());
    } catch (error) {
      setProblem(errorMessage(error));
    } finally {
      setStarting(false);
    }
  }, []);

  const flowId = flow?.flowId;
  const interval = Math.max(flow?.interval ?? MIN_INTERVAL_S, MIN_INTERVAL_S);

  useEffect(() => {
    if (!flowId) return;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout>;

    const tick = async () => {
      try {
        const result = await pollGithub(flowId);
        if (stopped) return;
        if (result.status === "pending") {
          timer = setTimeout(tick, interval * 1000);
          return;
        }
        if (result.status === "connected") {
          await queryClient.invalidateQueries({ queryKey: settingsKeys.connections });
          setFlow(null);
          return;
        }
        setProblem(
          result.status === "expired"
            ? CONNECTIONS_COPY.github.expired
            : result.status === "denied"
              ? CONNECTIONS_COPY.github.denied
              : (result.error ?? CONNECTIONS_COPY.github.failed),
        );
        setFlow(null);
      } catch (error) {
        if (stopped) return;
        setProblem(errorMessage(error));
        setFlow(null);
      }
    };

    timer = setTimeout(tick, interval * 1000);
    return () => {
      stopped = true;
      clearTimeout(timer);
    };
  }, [flowId, interval, queryClient]);

  return { flow, starting, problem, start, cancel };
}
