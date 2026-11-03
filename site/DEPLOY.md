# Deploying the Pythilo site

The site is one Next.js server: pages, lessons, the playground, and the room relay.
The relay keeps encrypted rooms in memory and never runs code. Python runs in each
visitor's browser (Pyodide, served from this site) or on a device in the room.

There is no production domain yet. Nothing in the code names one; the steps below
use `<domain>` for the public name and `<host>` for the server you reach over SSH.

## What the server needs

- Docker with Compose, and nginx with a certificate for `<domain>` (Let's Encrypt
  via the `/.well-known/acme-challenge/` location in `hetzner/pythilo.nginx`).
- About 150 MB for the image. No database, no volume, no secrets: the relay holds
  only ciphertext, and a restart ends every open room.

## 1. Build on a development machine

```sh
cd site
pnpm install
pnpm test && pnpm check && pnpm build
node scripts/prepare-server-release.mjs        # writes site/release/
```

`pnpm build` copies Pyodide from `node_modules/pyodide` into `public/pyodide/` and
fetches the few package wheels the lessons and Test need (NumPy, pytest and its
dependencies) from the Pyodide CDN once, checking each against the SHA-256 in
`pyodide-lock.json`. The release step checks them again.

## 2. Copy the release to the server

```sh
rsync -a --delete site/release/ <host>:/srv/apps/pythilo-site/
```

## 3. Start it

```sh
ssh <host>
cd /srv/apps/pythilo-site
PYTHILO_SITE_TAG=$(date +%Y%m%d%H%M) PYTHILO_SITE_ORIGIN=https://<domain> \
  docker compose -f compose.prebuilt.yaml up -d --build
curl -fsS http://127.0.0.1:3212/healthz/
```

`PYTHILO_SITE_ORIGIN` becomes `SITE_ORIGIN` in the container. The relay refuses
browser requests whose `Origin` is anything else; native clients (the app and the
MCP bridge) send no `Origin` and still need a room capability for every request.
`PYTHILO_SITE_PORT` changes the loopback port (default 3212).

Optional: set `NEXT_PUBLIC_APP_STORE_URL` at build time to point "Get the iPhone
app" at the App Store page. Without it, the button opens the app section of the home page.

## 4. nginx

```sh
sed 's/__PYTHILO_DOMAIN__/<domain>/g' hetzner/pythilo.nginx | sudo tee /etc/nginx/sites-available/pythilo
sudo ln -s /etc/nginx/sites-available/pythilo /etc/nginx/sites-enabled/pythilo
sudo mkdir -p /var/log/pythilo && sudo nginx -t && sudo systemctl reload nginx
```

The config proxies everything to `127.0.0.1:3212`, keeps the relay unbuffered for
its event streams, and does not log relay or room requests. The pages set their
own `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers (needed
for `input()` and Stop in the browser); nginx passes them through unchanged.

## 5. Check

```sh
node site/scripts/smoke.mjs https://<domain>
```

It creates a room, streams it, posts an update and presence, ends the room, and
loads `/`, `/learn/`, a lesson, `/playground/` and the Pyodide files.

## Pointing the clients at it

- iOS app: set `PythiloRelayOrigin` in Info.plist to `https://<domain>`.
- MCP bridge: `PYTHILO_RELAY=https://<domain>` (or `--relay https://<domain>`) to
  create rooms; joining uses the origin inside the room link.

## Local development

```sh
cd site
pnpm install
pnpm dev                                   # http://127.0.0.1:3212
```

Production mode locally: `pnpm build && SITE_ORIGIN=http://127.0.0.1:3212 node .next/standalone/server.js`
after copying `public/` and `.next/static/` next to it, or simply `pnpm start`.
