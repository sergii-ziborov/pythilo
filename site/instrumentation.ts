export async function register() {
  if (process.env.NEXT_RUNTIME !== "nodejs" || process.env.NODE_ENV !== "production") return;
  const { readFile } = await import("node:fs/promises");
  const { join } = await import("node:path");
  let build: string;
  try { build = (await readFile(join(process.cwd(), ".next", "BUILD_ID"), "utf8")).trim(); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return; throw error; }
  const { prepareRouteCache } = await import("./lib/site-route-cache");
  await prepareRouteCache(join(process.cwd(), ".next", "server", "route-cache"), build);
}
