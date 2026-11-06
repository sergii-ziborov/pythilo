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
npm run prepare-mcp                           # builds the official SDK download
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
and loads the home, guide, pricing, support, legal, blog, lessons, playground,
Connect AI and Pyodide files.

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

## Support email

Vercel DNS holds MX records for mx1.forwardemail.net and mx2.forwardemail.net, plus
Forward Email aliases for support, privacy and security at pythilo.com, to the
owner-approved Gmail destination. SPF includes spf.forwardemail.net. Website routing
records are unchanged. Forwarding is inbound only; replies are sent from Gmail.

The website price is US$9.99 for the planned one-time App Store purchase; the
TestFlight beta remains free and invitation-only. Do not link to an App Store listing
or public TestFlight signup before one is available.

## Page cache across releases

The Hostwatch profile mounts `/srv/apps/pythilo/cache/route-cache` at
`/app/.next/server/route-cache` so the container can keep its root filesystem
read-only. Next.js 16 response keys do not include a build ID. Reusing that mount
without a version check can serve a previous release's HTML and RSC even though
the serving image and its compiled pages are new.

`instrumentation.ts` now checks `.next/BUILD_ID` before the server handles requests.
On a different or unmarked build, `lib/site-route-cache.ts` moves old response
entries into `.pythilo-previous-builds/` inside that mount and records the new ID.
A restart of the same build keeps its current cache. The archived entries are
derived page responses, retained for inspection; they contain no room storage.
The lifecycle is covered by `tests/site-route-cache.test.mjs`. Always check the
actual home-page text after deployment, in addition to container health.

Release verified 5 November 2026: image
`sha256:d73afdeea48a9bb729121e594bd2c51f3022cb06fe17a925540dd7e6b2c7720f`,
Hostwatch deployment `pythilo-site-cache-guard-deploy-20261105-v4`. All public smoke
checks passed; the browser displayed the new home on desktop and mobile, with no
horizontal overflow at 390 px. Local checks passed: 75 site tests, 59 SDK tests,
TypeScript and production build. The public SDK archive also passed `pythilo doctor`.

The learning expansion was deployed at 19:22 UTC on 5 November 2026 as image
`sha256:57727030bc4db2d93be2290eb4f01617815a3a0c4efb86fa96fbe6572c654803`,
receipt `pythilo-learning-expansion-deploy-20261105-v2`. It adds 32 lessons and ten
browser labs; 76 site tests, the production build and the expanded public smoke
checks passed. Lab pages use the same cross-origin isolation as lessons/playground.
The source overlay includes prepared `content/courses.json` and `content/labs.json`;
prepare these locally from the shared iOS source before uploading through Hostwatch.

The final follow-up deployed at 19:31:52 UTC uses image
`sha256:befd00129498ce5cb430cda0976f2659bb2f8c37f3d209ab8bf67598c80c69f2`,
receipt `pythilo-learning-expansion-final-deploy-20261105-v3`. It adds the direct
browser-lab link on the home page and documents lab storage in the privacy policy.
The public smoke test passed again after this deployment.

The JSON-example correction deployed at 19:59:41 UTC uses image
`sha256:271aa96e03669d5a892ba84ef6d9de3fd4416a1be423bbcbd24b306ed9b80083`,
receipt `pythilo-learning-example-fix-deploy-20261105-v4`. All 77 site tests pass,
including execution of all 32 new reading examples in Pyodide. Public HTML confirms
the corrected JSON string and the public smoke test passed after deployment.

ML/AI and interview expansion deployed on 5 November 2026 at 22:03:09 UTC
(6 November in Jerusalem). Serving image:
`sha256:846c5b24418bf743615979992e849cf6de6d85bac48703a6ea0b2b13c929a749`;
Hostwatch receipt `pythilo-intelligence-100-deploy-20261105-v2`, source revision
`sha256:a82911433dfc5a6889c2340eefda86b6aaa2d7e4b93747c421c807de030931b0`.

This release has 256 lessons in 19 courses, 100 interview tasks, 30 browser Labs,
a full 52-Lab native catalog, and eight blog posts including six new practical
ML/AI articles. The source overlay contains prepared course/Lab JSON, the new
Python tracing module, numeric matrix rendering, blog Markdown/SVGs and the real
native screenshot with ML/AI filters. No dependency or infrastructure changes.

All 80 site tests, TypeScript and the production build pass. Public production
smoke checks pass for encrypted rooms, the new lesson/task/Lab/article routes,
worker/Wasm delivery and isolation headers. Browser verification on production
checked the 100-task catalog, eight-post blog, and a causal mask worked answer
through the final matrix and passing checks. Local responsive checks covered
390 px blog and Lab layouts. Evidence is in `build/verification/` and
`build/logs/intelligence100-public-smoke.log`.

A follow-up for link-preview compatibility deployed at 22:27:50 UTC on
5 November 2026, image
`sha256:d6d956f87350ad3e21c2d43fa8317ba600685d0a997f4a2cc3960f2e4f7c8252`,
receipt `pythilo-blog-share-covers-deploy-20261105-v4`, source revision
`sha256:08c65fdc389325d62b56d821b95f52b8814ed46c8e363ca6da253a854bb4e25a`.
All eight articles now use PNG covers for Open Graph, Twitter metadata and RSS;
SVG design sources and the existing WebP illustrations are retained. The target
blog test and production build pass. Production checks fetched every article and
image, verified matching metadata, PNG signatures/dimensions/MIME and all eight
RSS enclosure types. The full public smoke check passes again. The app binary
and lesson/Lab content are unchanged by this follow-up.

The original interview reading examples were repaired and deployed at 22:41:02 UTC
on 5 November 2026, image
`sha256:5af988ab8b6b83822e9d6b64cbc2365d0303f6dd6ab4fa700fb8a4020bc2a57c`,
receipt `pythilo-interview-reading-deploy-20261105-v5`, source revision
`sha256:254de60b185d7e1fe1541f97fe5b005105c3e5ef953037b2186ef03bcfd8ab62`.
All 112 reading blocks in the 100 interview tasks now execute in isolation. The
expanded Pyodide test and all 80 site tests pass; the new native test executes the
same 112 blocks inside the app and passes. The production build and public smoke
check pass. A browser check on production ran the first task's example and showed
`[4, 1, 2, 3]`, exit 0; existing Home/Labs tabs were refreshed to the current counts.
The screenshot is `build/verification/pythilo-interview-example-fixed-live.jpg`.

The library-course expansion was verified in production on 6 November 2026. It
adds 52 lessons: Pydantic 2 (20), FastAPI/HTTPX (14), practical testing (10), and
data/file formats (8). Totals are 308 path lessons in 23 courses plus 100 interview
tasks; Labs remain 52 native and 30 browser. Eight older reading blocks were made
self-contained. The shared checker registers its temporary module so Pydantic
RootModel generics work, and restores interpreter state after checking.

The final follow-up deployed at 09:08:31 UTC as image
`sha256:4b3365290a3f5064436ea0a853e912d1ecc6922df2bc620fa63387f0641f9c59`,
source revision
`sha256:16999fd244d67cc89bb7dbaa798aa0e2deb6900aff507a24ac553a78655b8c60`,
receipt `pythilo-package-catalog-deploy-20261106-v2`. Build receipt:
`pythilo-package-catalog-build-20261106-v2`; registry receipt:
`pythilo-package-catalog-publish-20261106-v2`. The initial content deployment
`pythilo-library-courses-deploy-20261106-v1` was superseded by this fix for a cached
package catalog. The worker now requests a catalog URL derived from its SHA-256,
so an earlier browser visit cannot hide newly bundled Pydantic/FastAPI packages.
Receipts are archived in `build/release-receipts/`.

All 82 site tests, TypeScript and the 506-page production build pass. A fresh
Pyodide instance discovers and executes Pydantic/FastAPI/HTTPX imports without
manual package preloading. All 362 browser-compatible solutions and 417 reading
blocks execute; 48 reading blocks explicitly require native packages or threads.
All 52 new lesson routes return 200 with their expected title and isolation
headers; the served worker matches the prepared artifact byte for byte. Public
smoke checks pass for the relay, pages, worker, Wasm and headers. Production browser
checks ran Pydantic and an async HTTPX ASGI request, both exit 0, then passed all
three checks for each lesson. Home shows 308/23. Proof:
`build/verification/pythilo-pydantic-live-passed.png`; logs:
`build/logs/library-new-live-audit.json`, `library-final-public-smoke.log`,
`expanded-site-tests-cold-start.log`. Native verification additionally executed
all 408 solutions and all 465 reading blocks without skips.

The advanced expansion was published on 6 November 2026: 74 lessons in seven
courses, including six integrated projects, and 20 companion Labs. Totals are
382 path lessons in 30 courses plus 100 interview tasks; 72 native Labs (33 ML,
16 AI), of which 50 run in the browser. Forty lesson/Lab pairs have reciprocal
links. `/learn/senior/` publishes three paths, review criteria and the real
production/model/hardware work still required beyond local exercises.

Content deployment `pythilo-senior-final-deploy-20261106-v4` was followed by a
navigation-style repair at 11:50:33 UTC, receipt
`pythilo-senior-css-deploy-20261106-v2`. Serving image:
`sha256:3aaecff08c3816996be03240ddd2738ce357c8567071b7ceb36e4c49ed339beb`;
source revision:
`sha256:f56b9c34886153300a4e3a9670c4f456be785284b914abfc9584108aa0dfb640`.
Build and registry receipts use the same `pythilo-senior-css-…-20261106-v2`
prefix; archived receipts are in `build/release-receipts/senior-css-release.json`.
Lesson editor positioning is scoped to `.lesson-editor`, so retained Next.js CSS
cannot overlay a Lab or intercept its lesson link after client navigation.

All 85 site tests pass, including 428 browser solutions, 483 reading blocks and
every browser Lab answer/starter. The 608-page production build includes type
checking. Production audits cover all 94 new lesson/Lab routes, three paths and
40 reciprocal links, followed by the public smoke suite. A real browser ran a
reading example, passed the ROC AUC lesson's three checks, replayed its Lab to
step 11/11 with three passing checks and returned through the lesson link after
client navigation. Proof: `build/verification/pythilo-senior-lab-live.png`.

The ML/AI systems expansion adds 24 lessons and 24 Labs, including 12 larger
projects. Totals are 406 path lessons in 32 courses plus 100 interview tasks,
96 native Labs (45 ML, 28 AI), 74 browser Labs and 64 reciprocal lesson/Lab pairs.
The advanced paths list 18 integration projects. All new code uses stdlib or the
NumPy already bundled in both runtimes. Saved provider outputs and scheduling
simulations are explicitly distinguished from actual model/GPU serving.

Final deployment `pythilo-projects24-layout-deploy-20261106-v3` succeeded at
15:56:01 UTC on 6 November 2026. Serving image:
`sha256:d96b323fc0e4480f5cbe35731aefd4163c6b0ae86e2cc673afa3f017acbdcffd`;
source revision:
`sha256:981d04a257397a797b118bb2e3aa20bc50da3bea9d8c82cffbf6f92af927c69e`.
Build/publish receipts use the corresponding `pythilo-projects24-layout-…-20261106-v3`
keys; archive: `build/release-receipts/projects24-layout-site-release.json`.
Earlier content and cold-start receipts are retained in `projects24-site-release.json`
and `projects24-cold-site-release.json` in that directory.

The worker receives learner code as an actual Python file before import discovery,
so an independent Lab runtime loads NumPy without relying on an earlier lesson.
A scoped wrapping style prevents a long Read lesson link from widening the page.
All 87 site tests, TypeScript and the 658-page production build pass. Production
audits cover 133 URLs/headers and all 64 reciprocal pairs; the public smoke suite
passes. Real-browser verification runs the ridge example and four lesson checks,
loads and traces the Lab answer to step 31/31 with four passing checks, confirms
390px page width at a 390px viewport and follows the lesson link back. Desktop
and mobile screenshots: `build/verification/pythilo-projects24-ridge-live.png` and
`build/verification/pythilo-projects24-ridge-mobile.png`.

The PyTorch/topic expansion adds 18 native CPU Labs, 18 lessons and six projects.
The app catalog has 114 Labs in 13 expandable topics (54 ML, 37 AI); the web
catalog offers 74 runnable Labs and 18 explicitly App required PyTorch pages.
Search, section/runtime filters and topic expand/collapse use the shared topic
assignments. There are 82 reciprocal lesson/Lab pairs and 24 integration projects.

Deployment `pythilo-torch18-topics-deploy-20261106-v2` succeeded at 17:04:02 UTC on
6 November 2026. Fresh readback confirms the serving image:
`sha256:e0e3566dccbe26dc21f3a41f36612f554379166f73c0668deb1c76af9b1a8ef4`.
Source revision:
`sha256:5505f4f2b7dd1045ced8fc2792de892c0744576944ec9908d85117a7dda946a5`.
The corresponding build and publish operation keys use
`pythilo-torch18-topics-build-20261106-v2` and
`pythilo-torch18-topics-publish-20261106-v2`. Completed receipts and serving
readback: `build/release-receipts/torch18-site-release.json`.

The sealed partial source archive contains 17 files, 585092 bytes, SHA-256
`1eb4d43f78f84a1f4608551a55b6070e449df71bc96f2f5c8a3257d9c9145ece`.
Baseline hashes matched the approved preceding source. The first archive was
never accepted during agent maintenance; v2 includes a lesson-link wrapping fix
found during mobile QA. No running service was changed during that maintenance.

All 90 web tests pass; the final content-specific seven checks, TypeScript and
696-page build also pass. Public audit passes 179 URLs with isolation headers and
all 82 reciprocal pairs; public smoke checks pass. Real browser verification
covers search, combined filters, topics, the tiny-transformer Lab/lesson links and
App required controls. At 390px the lesson, Lab and expanded catalog have no
horizontal overflow. Viewport overrides were reset. Proofs:
`build/verification/pythilo-torch18-catalog-live.png` and
`build/verification/pythilo-torch18-lesson-mobile-live.png`.
