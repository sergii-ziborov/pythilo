import { PythiloError } from "./errors.js";

// A room link carries its own origin. Creating a room uses the public relay unless
// PYTHILO_RELAY or --relay names another, such as a local site at http://127.0.0.1:3212.
export const DEFAULT_RELAY = "https://pythilo.com";
export type RelayConfig = { origin: string; source: "--relay" | "PYTHILO_RELAY" | "option" | "default" };

const invalid = (from: string) => new PythiloError("RELAY_NOT_CONFIGURED", `${from} must be a relay origin such as http://127.0.0.1:3212 or https://relay.example, with no path, query or credentials.`);

/** An origin and nothing else: scheme, host and port. Credentials are refused and never echoed. */
export function relayOrigin(value: string, from = "PYTHILO_RELAY"): string {
  let url: URL;
  try { url = new URL(value.trim()); } catch { throw invalid(from); }
  if ((url.protocol !== "https:" && url.protocol !== "http:") || url.username || url.password || url.search || url.hash || url.pathname !== "/") throw invalid(from);
  return url.origin;
}

export function configuredRelay(option?: string, source: RelayConfig["source"] = "option", environment: NodeJS.ProcessEnv = process.env): RelayConfig {
  if (option !== undefined) return { origin: relayOrigin(option, source === "--relay" ? "--relay" : "The relay option"), source };
  const value = environment.PYTHILO_RELAY;
  return value?.trim() ? { origin: relayOrigin(value), source: "PYTHILO_RELAY" } : { origin: DEFAULT_RELAY, source: "default" };
}

export const isLoopback = (hostname: string) => hostname === "localhost" || hostname === "[::1]" || /^127(?:\.\d{1,3}){3}$/.test(hostname);

export const relayRequired = () => new PythiloError("RELAY_NOT_CONFIGURED", "Creating a room needs a relay, and none is configured. Set PYTHILO_RELAY to the relay's origin (for local development http://127.0.0.1:3212), or start the bridge with --relay <origin>. Joining a room from a link works without it, because the link carries its relay.");
