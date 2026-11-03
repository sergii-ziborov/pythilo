"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { Awareness } from "y-protocols/awareness";
import { RuntimeController, type RemoteRunResult } from "@/lib/playground-runtime-controller";
import type { RuntimePresenceChannel } from "@/lib/playground-runtime-channel";
import type { PlaygroundSession } from "@/lib/playground-session";
import type { PlaygroundDocument } from "@/lib/playground-document";
import type { RuntimeAction } from "@/lib/playground-runtime-authority";

type Status = ReturnType<RuntimeController["status"]>;

/** This browser as a controller: it lists runtime hosts in the room and asks one to run. */
export function useRuntimeController(session: PlaygroundSession | null, awareness: Awareness, channel: RuntimePresenceChannel | null, source: () => PlaygroundDocument, name: string) {
  const controller = useRef<RuntimeController | null>(null), latest = useRef(source); latest.current = source;
  const [status, setStatus] = useState<Status | null>(null);
  useEffect(() => {
    if (!session || !channel || session.link.mode !== "edit") return;
    let stopped = false, instance: RuntimeController | null = null;
    void RuntimeController.create(session, awareness, () => latest.current(), channel, `${name.slice(0, 30)} · website`).then(created => {
      if (stopped) { created.close(); return; }
      instance = created; controller.current = created; setStatus(created.status());
    });
    const timer = setInterval(() => { if (instance) setStatus(instance.status()); }, 1000);
    return () => { stopped = true; clearInterval(timer); instance?.close(); controller.current = null; setStatus(null); };
  }, [session, awareness, channel, name]);

  const ask = useCallback(async (target: string, operations: RuntimeAction[]) => {
    if (!controller.current) throw new Error("This room is not connected for running on other devices.");
    await controller.current.request(target, operations);
    setStatus(controller.current.status());
  }, []);
  const follow = useCallback(async (target: string, operation: RuntimeAction, onStage: (stage: string, job: string) => void): Promise<RemoteRunResult> => {
    if (!controller.current) throw new Error("This room is not connected for running on other devices.");
    return controller.current.follow(target, operation, onStage);
  }, []);
  const stop = useCallback(async (target: string, revision: string, job: string) => {
    await controller.current?.command(target, "stop", revision, job).catch(() => {});
  }, []);
  return { status, ask, follow, stop };
}
export type RuntimeControl = ReturnType<typeof useRuntimeController>;
