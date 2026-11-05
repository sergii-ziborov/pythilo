# Deploying the Pythilo site

The site is one Next.js server: pages, lessons, the playground, and the room relay.
The relay keeps encrypted rooms in memory and never runs code. Python runs in each
visitor's browser (Pyodide, served from this site) or on a device in the room.

Production is `https://pythilo.com` (and `www`, which redirects), on the Hetzner
analytics node `46.225.60.104` next to Versemora. DNS is on Vercel: A and AAAA records
for the apex and `www` point at the node (`vercel dns ls pythilo.com --scope serhii-bddc`).

## How it runs

- `pythilo-site.service` (systemd, `DynamicUser`, 384 MB, one CPU) runs
  `/opt/pythilo/current/server.js` on `127.0.0.1:3212` with `SITE_ORIGIN=https://pythilo.com`.
  One instance only: rooms live in its memory, and a restart ends every open room.
- `/opt/pythilo/releases/<UTC time>/` holds the last three releases; `current` links the live one.
- nginx (`/etc/nginx/sites-available/pythilo`, from `hetzner/pythilo.nginx`) terminates TLS,
  keeps the relay unbuffered for its event streams, and does not log relay or room requests.
  The pages set their own `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy`
  headers (needed for `input()` and Stop in the browser); nginx passes them through.
- The Let's Encrypt certificate (`/etc/letsencrypt/live/pythilo.com`) renews through the
  webroot `/var/www/letsencrypt` with certbot's timer and reloads nginx afterwards.
- No database, no volume, no secrets: the relay holds only ciphertext.

## Release

```sh
cd site
pnpm install
pnpm test && pnpm check && pnpm build
node scripts/prepare-server-release.mjs        # writes site/release/
sh hetzner/deploy.sh                           # copy, switch, restart, check
node scripts/smoke.mjs https://pythilo.com
```

`pnpm build` copies Pyodide from `node_modules/pyodide` into `public/pyodide/` and
fetches the few package wheels the lessons and Test need (NumPy, pytest and its
dependencies) from the Pyodide CDN once, checking each against the SHA-256 in
`pyodide-lock.json`. The release step checks them again.

`deploy.sh --nginx` also reinstalls the nginx site from `hetzner/pythilo.nginx`.
`PYTHILO_HOST`, `PYTHILO_SSH_KEY` and `PYTHILO_DOMAIN` point it elsewhere.

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
