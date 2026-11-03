export const HANDOFF_SCHEMA = "pythilo-handoff-v1";
export const MCP_PACKAGE = "pythilo";

export type AIClient = "claude-code" | "claude-desktop" | "codex";
export const aiClients: Record<AIClient, string> = { "claude-code": "Claude Code", "claude-desktop": "Claude Desktop", codex: "Codex" };

/** The one-time setup for each client, from npm or from a local checkout of `sdk/`. */
export function setupCommand(client: AIClient, checkout?: string): string {
  const command = checkout ? ["node", `${checkout.replace(/\/+$/, "")}/sdk/dist/cli.mjs`] : ["npx", "-y", MCP_PACKAGE];
  if (client === "claude-code") return `claude mcp add --transport stdio pythilo -- ${command.join(" ")}`;
  if (client === "codex") return `codex mcp add pythilo -- ${command.join(" ")}`;
  return JSON.stringify({ mcpServers: { pythilo: { command: command[0], args: command.slice(1) } } }, null, 2);
}

/** The message a person pastes into their AI client. Nothing leaves the page until they do. */
export function aiHandoffText(link: string, mode: "edit" | "view", expiresAt: number): string {
  const handoff = { schema: HANDOFF_SCHEMA, linkType: `temporary ${mode} Playground`, link, expiresAt: new Date(expiresAt).toISOString(), mode, execution: "No code is executed by opening or handing off this link." };
  return ["Join my Pythilo room with pythilo_connect:", link, "", mode === "edit" ? "Read the current source before changing it. Running code needs separate permission from a device in the room." : "Read the source only; this link cannot edit it.", "", JSON.stringify(handoff, null, 2)].join("\n");
}

/** The same message with the link's secrets hidden, for showing on screen. */
export const maskedLink = (link: string) => link.replace(/key=[^&]+/, "key=[KEY]").replace(/access=[^&]+/, "access=[ACCESS]");
