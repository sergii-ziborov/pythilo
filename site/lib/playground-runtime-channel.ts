import type { Awareness } from "y-protocols/awareness";
import { publishRuntimePresence } from "./playground-presence.ts";
import type { RuntimeEnvelope } from "./playground-runtime-protocol.ts";

/**
 * A participant has one runtime presence field. A browser that is both a host and
 * a controller publishes through this queue, so each envelope stays in presence
 * long enough to be sent and read before the next one replaces it.
 */
export class RuntimePresenceChannel {
  private queue = Promise.resolve();
  private count = 0;
  private publishedAt = 0;
  private closed = false;
  private awareness: Awareness;
  private spacingMs: number;
  constructor(awareness: Awareness, spacingMs = 300) { this.awareness = awareness; this.spacingMs = spacingMs; }
  publish(envelope: RuntimeEnvelope): Promise<void> {
    if (this.count >= 24) return Promise.reject(new Error("Runtime transport is busy."));
    this.count++;
    const next = this.queue.then(async () => {
      await new Promise(resolve => setTimeout(resolve, Math.max(0, this.spacingMs - (Date.now() - this.publishedAt))));
      if (this.closed) throw new Error("Runtime connection closed.");
      publishRuntimePresence(this.awareness, envelope); this.publishedAt = Date.now();
    });
    this.queue = next.catch(() => {});
    void next.finally(() => { this.count--; }).catch(() => {});
    return next;
  }
  close() { this.closed = true; }
}
