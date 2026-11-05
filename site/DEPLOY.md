# Deploying the Pythilo site

The site is one Next.js server: pages, lessons, the playground, and the room relay.
The relay keeps encrypted rooms in memory and never runs code. Python runs in each
visitor's browser (Pyodide, served from this site) or on a device in the room.

Production is `https://pythilo.com` (and `www`, which redirects), on the Hetzner
Helsinki application node `2.29.175.213`, enrolled in Hostwatch as
`fe8b3706-3da6-47f8-875c-ce86a0cb8114`. Its IPv6 is `2a01:4f9:c015:13da::1`.
Authoritative DNS remains on Vercel: apex and `www` A records point to
`2.29.175.213`, and both AAAA records point to `2a01:4f9:c015:13da::1` (TTL 60).
Provider readback, authoritative DNS and valid public HTTPS on both address
families were verified on 5 November 2026. The old analytics origin
`46.225.60.104` is retained as a TLS forwarding route; its Pythilo process and
separate certificate-renewal profile are disabled.
Check live DNS with `vercel dns ls pythilo.com --scope serhii-bddc` before retiring that route.

## How it runs

- Hostwatch target `pythilo-web` runs the owned Podman container `pythilo-web`
  as UID 1000, with 384 MB and 0.75 CPU, on `127.0.0.1:3215` (container port 3000)
  with `SITE_ORIGIN=https://pythilo.com`.
  One instance only: rooms live in its memory, and a restart ends every open room.
- `/srv/apps/pythilo/releases/<UTC time>/` holds staged releases. The initial
  migrated bundle is retained at `/opt/pythilo/releases/move-20261105`.
  `hostwatch-app-pythilo.service` starts the approved container at boot.
- nginx (`/etc/nginx/sites-available/pythilo`) terminates TLS,
  keeps the relay unbuffered for its event streams, and does not log relay or room requests.
  The pages set their own `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy`
  headers (needed for `input()` and Stop in the browser); nginx passes them through.
- The Let's Encrypt certificate (`/etc/letsencrypt/live/pythilo.com`) renews through the
  webroot `/var/www/letsencrypt` with certbot's timer and reloads nginx afterwards.
- No application database or essential persistent volume: the relay holds only
  ciphertext in memory. Operator-mounted Next.js caches are derived data.

## Release

```sh
cd site
pnpm install
pnpm test && pnpm check && pnpm build
node scripts/prepare-server-release.mjs        # writes site/release/
sh hetzner/deploy.sh                           # stage the reviewed Linux image
# Hostwatch MCP: deployment_preview, then deployment_update on the node/target above.
# Poll image_publish_status to verified success before the public smoke test.
node scripts/smoke.mjs https://pythilo.com
```

`pnpm build` copies Pyodide from `node_modules/pyodide` into `public/pyodide/` and
fetches the few package wheels the lessons and Test need (NumPy, pytest and its
dependencies) from the Pyodide CDN once, checking each against the SHA-256 in
`pyodide-lock.json`. The release step checks them again.

`deploy.sh` delegates to `stage-hostwatch.sh`. It stages an image and does not
replace the running container or ingress. The historical `pythilo.nginx` uses
port 3212 on the old analytics node; do not install it over Helsinki's port 3215
route (3212 belongs to Crabrix there). `PYTHILO_HOST`, `PYTHILO_SSH_KEY` and
`PYTHILO_HOSTWATCH_NODE` select an explicitly prepared alternative. The pinned
Node base must exist on that node. Review the Linux sharp pin when upgrading it.

The smoke test creates a room, streams it, posts an update and presence, ends the room,
and loads `/`, `/learn/`, a lesson, `/playground/` and the Pyodide files.

Optional: set `NEXT_PUBLIC_APP_STORE_URL` at build time to point "Get the
app" at the App Store page. Without it, the button opens the beta section of the pricing page.

## Clients

- iOS app: `PythiloRelayOrigin` in Info.plist (`project.yml`) is `https://pythilo.com`.
  The app is offline otherwise; only a shared room reaches the relay.
- MCP bridge: creates rooms on `https://pythilo.com` unless `PYTHILO_RELAY` or `--relay`
  names another relay; joining uses the origin inside the room link.

## Local development

```sh
cd site
pnpm install
pnpm dev                                   # http://127.0.0.1:3212
```

Production mode locally: `pnpm build && SITE_ORIGIN=http://127.0.0.1:3212 node .next/standalone/server.js`
after copying `public/` and `.next/static/` next to it, or simply `pnpm start`.
