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

"Get the app" opens the App Store page, `APP_STORE_URL` in `lib/site-info.ts`.
`NEXT_PUBLIC_APP_STORE_URL` at build time overrides it, for example with a campaign link.

## Clients

- iOS app: `PythiloRelayOrigin` in Info.plist (`project.yml`) is `https://pythilo.com`.
  Shared rooms use the relay. Courses, Lab topics and Python API packages download
  from the site; pinned public model weights use Hugging Face. Execution works
  offline once its required content has downloaded.
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

Pythilo 1.0 has been on the App Store since 12 November 2026 for US$9.99, paid once
(`PRICE`, `RELEASED` and `APP_STORE_URL` in `lib/site-info.ts`). The site links to the
App Store page; TestFlight builds stay free and by invitation, with no public signup link.

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

## Downloadable content and complete BERT projects (6 November 2026)

The site publishes 430 path lessons in 35 courses, 100 interview tasks, 120 native
Labs in 15 topics, 24 PyTorch Labs and 88 reciprocal lesson/Lab pairs. Six complete
BERT project source ZIPs include a pinned asset fetcher, editable code and
instructions for full-data training and evaluation. PyTorch execution is marked
App required; 74 compatible Labs also run in the browser.

The final release is live from source revision
`sha256:8d42153f446c95ed282039cca3bc240f3974d64d2cac07f62c7002bd4544a7c5`,
image `sha256:4471bf526558d9bcc054a978e3114dc58281254011d634342f56323aecafa903`,
registry manifest
`sha256:2e0444c684edbed80cd3e9212f0676408ff32dc0e8a80872798f7686dc724c4e`.
Serving readback at 21:38 UTC confirms the exact image, healthy running container
and revision `sha256:c1536e9c94b04a278444b934397f41769737fcbdaa07dd900a81c90f63076ee1`.
Operation keys are `pythilo-native-markers-{build,publish,deploy}-20261106-6`.
Receipt: `build/release-receipts/downloads26-final-site-release.json`.

All 57 catalog-pinned HTTPS payloads (43,530,882 bytes, including the external
Hugging Face weight asset) were fetched completely and verified with SHA-256.
The app's catalog hash is
`d46905be67cdbc1a2672be9ef097d2a5b93ce66dedfda7c53b9b6e05ef9932bf`.
Native transport tests then downloaded the actual published course and PyTorch
archives, paused and immediately resumed, verified inventory and embedded backend
links, and opened the automatic project download manager. All seven tests pass:
`build/downloads26-public-transport.xcresult`. Public integrity receipt:
`build/release-receipts/downloads26-public-integrity.json`.

All 92 web tests, TypeScript and the 709-page production build pass. The final
public audit passes 191 URLs, all 88 link pairs and isolation headers; the room
and runtime smoke checks also pass. Browser proof:
`build/verification/pythilo-finetuning-downloads-live.png`.

Before releasing an app catalog that references new payloads, prepare and publish
those files first. On the authoring Mac, after native package preparation:

```sh
python3 scripts/generate-finetune-content.py
python3 scripts/build-content-packs.py
python3 scripts/build-finetune-projects.py
```

Stage new `site/public/content-packs/` and `site/public/projects/` files in bounded
source overlays along with prepared site content. Content-addressed pack URLs are
immutable; keep prior app versions' files reachable. The current iOS app pins the
catalog inside its signature and verifies each archive and extracted file. Native
extension markers refer to signed backends already inside that app. Never publish
downloadable framework binaries or include model weights/data in its archive.

## Explicit downloads release (7 November 2026)

The current site explains explicit whole-course, whole-category and whole-library
downloads. Creating/opening a project or pressing Run never downloads packages.
The selected downloaded curriculum executes and checks offline; complete BERT
projects train and evaluate locally with their explicitly downloaded assets.

Source revision:
`sha256:b047d93dbc55075bca08419c76cce8d1513f5ecadf823953deaefbce54477839`.
Image: `sha256:d6d0b8f2afff4dda130ed218307c3c3d42b7c1252c496636e56c9cd7871dde83`.
Registry manifest:
`sha256:7e778c272c1ecfa80b621faa6aef06f646423076c811a2cb178bb8316623f4ed`.
Verified serving revision:
`sha256:a7822eb7e89809a8039faeeb3710736d2db22eb18d7b5339ee68238309d53ddd`.
Hostwatch operation keys use `pythilo-explicit-offline-{build,publish,deploy}-20261107-v1`.
Deployment completed at 23:14:53 UTC on 6 November (7 November local time).
Receipt: `build/release-receipts/manual27-site-release.json`.

All 92 web tests and TypeScript pass. The public audit passes 191 URLs, all
88 reciprocal lesson/Lab pairs and isolation headers; room/runtime smoke passes.
All 57 pinned payloads (43,530,947 bytes) were fetched and checked with SHA-256.
Catalog hash: `eeafdc1b5bf814b0674f3a8700fdf9c9c09c84861fa3bd2a631abc95c3218ab4`.
Only the fine-tuning course text pack changed; prior content-addressed URLs remain
reachable for older builds. Public transport proof:
`build/release-receipts/manual27-public-integrity.json`.

## Senior research Labs release (7 November 2026)

The published catalog contains 136 Labs in 19 topics, including 40 CPU PyTorch
Labs, 446 path lessons and 100 interview tasks. Two new eight-lesson courses
cover robust ML and alignment; 16 new Labs include four complete experiments
with deterministic synthetic local data, validation selection, separate test
evaluation and serialized model reloads. All 104 lesson/Lab pairs are reciprocal.
The app explicitly downloads an entire course or category, including dependencies,
before offline execution. Creating/opening a project or pressing Run starts no download.

Final source revision:
`sha256:41309c5c872caa455efb2a8a1f5867ced07e8622e38cacca2f238da3f41587b1`.
Image: `sha256:b0c814a46f09702f2d65cf8eaa2ef37cc490290778f23395c3145e7f53b226e8`.
Registry manifest:
`sha256:ee7dc590fb0ded9616f5842751a09e65228c8e53a5d85b3fc1151862cec5fc7d`.
Verified serving revision:
`sha256:7e24b15cf7530b7ee046f547a0deae19170f01d92c6632486f7433f7e934e56d`.
The source build, registry update and live deployment succeeded independently;
the live image matches the final staged image. Operation keys use
`pythilo-senior-research-{build,publish,deploy}-20261107-v2`.
Receipt: `build/release-receipts/research28-site-release.json`.

All 92 web tests, TypeScript and the final 743-page remote build pass. The public
audit passes 226 routes, all 104 link pairs, native runtime notices and isolation
headers. Room/runtime smoke checks pass. All 63 catalog-pinned public payloads
(43,593,736 bytes) were downloaded completely and verified with SHA-256.
Catalog hash: `b29787e5e05d7aa54a965695c7c59fb5b920b121174c5bce53321d12ef0bc191`.
Prior immutable pack URLs remain available. Public receipts:
`build/release-receipts/research28-public-integrity.json` and
`build/logs/research28-public-audit.json`.

## Terminal tabs guide (11 November 2026)

The terminal, settings and web-servers guide pages describe terminal tabs, Settings ›
About and running commands beside a server. A three-file partial overlay (6,578 bytes,
SHA-256 `4efbefd6b3ed310044c41a8ab9410fd6768e372e426b5db4ec06cee51fcf1178`) was
uploaded after the server's copies matched the previous revision byte for byte.

The first source build was refused by the node's build guard: it requires 10 GiB free
and the node had 10.03 GB. Retention could reclaim nothing (rollbacks and other
services' recovery sets are protected). With the owner's approval `minFreeBytes` was
lowered to 9 GiB for this build and restored to 10 GiB right after the deployment.
The node's disk (40 GB, 17.7 GB of container layers) needs headroom before the next
build: resize it or free space deliberately.

Source revision:
`sha256:ed3afcb6862df89f7baf2e2fb72284a90e1d57045e985498332349322dc32693`.
Image: `sha256:9d762686826d9bd83ed599cf17400794504c60413e7bc3905da6c19dfe9ccae0`.
Registry manifest:
`sha256:f198249c90e4fe18d791a2eb89086cc82c8109ef9127f1fa64dbc04b849e7e17`.
Serving revision:
`sha256:751757d85866902c82fd930a507dc5ee2ffb75d607484dd142d8d70b98fb0670`.
Operation keys: `pythilo-guide-tabs-build-20261111-v2`, `pythilo-guide-tabs-publish-20261111-v1`,
`pythilo-guide-tabs-deploy-20261111-v1`; deployed at 06:14:15 UTC.
Receipt: `build/release-receipts/guide-tabs-site-release.json`.

All 92 site tests, TypeScript and the 743-page production build pass locally. The public
smoke suite passes, and the three live pages return 200 with the new text.

## Algorithms course, GitHub and project categories (11 November 2026)

Publishes the 32-lesson Algorithms and data structures course (pack
`course-algorithms-85ec1e9e661413c4.zip`, 19,066 bytes) for app build 33, and updates the
landing page, Projects, Git and Settings guides for GitHub search, the GitHub account and
project categories, with new Projects, Learn and GitHub shots. Totals: 478 path lessons in
38 courses plus 100 interview tasks; 776 pages.

The 13-file partial overlay (815,320 bytes, SHA-256
`613d118099535c661a4ee072987c74d989918ce4568105820950d0edba31ba19`) was larger than one
inline call, so it was sent in 256 KiB chunks through the same `source_upload` operation by
`build/release-tools/hostwatch_upload.py`, which drives the local Hostwatch MCP server.
Server baselines for every replaced file matched the committed sources.

The node had 9.77 GB free after its scheduled cleanup, short of the 10 GiB build guard.
As for the morning release, `minFreeBytes` was set to 9 GiB for this build and restored to
10 GiB right after deployment. The disk keeps shrinking with each release; resize it or
free space before the next build.

Source revision `sha256:1ba4db82da5be70ed37597b5c4edf1fa103b5bc9a7f0147585f686eb3e360db9`,
image `sha256:5986a21373a2315bd9cbfc9767daa00eca58cc91bad3256747c9a2cf52996c92`, registry
manifest `sha256:01b256b795c3cbbc488f22753b553a1033f7bbc41984e997d051eac82c1d292c`, serving
revision `sha256:f164ca2e730623e001f6b09095280b06f59bf01f77cf5dfddc0a0010a9d12d04`.
Operation keys `pythilo-algorithms-github-{build,publish,deploy}-20261111-v1`; deployed at
13:24:52 UTC. All 92 site tests, TypeScript and the build pass; the public smoke suite
passes, the course pack serves with its pinned SHA-256, and the new course, lesson and
guide pages return 200.

## Learn guide: download, remove and hide (11 November 2026)

The Learn guide describes tracks and the new Download, remove and hide actions for courses
and Lab topics (app build 34). Lessons, Labs and the course packs are unchanged from the
previous deployment, which already carries all 478 path lessons including the algorithms
course. Overlay: `app/guide/learn/page.tsx` and this file (14,843 bytes, SHA-256
`c0711ea3ab50c817d450c588d8edff2fadf7ccfc7fccaa234d04521d2f7c28de`).

Free disk was 8.70 GB. A reviewed retention run (`pythilo-guide34-cleanup-20261111`)
removed superseded shared build caches and the 7 November Pythilo build, freeing 0.94 GB;
current and two rollback versions stayed protected. With 9.64 GB free, `minFreeBytes` was
set to 8.5 GiB for this build only and restored to 10 GiB after deployment. The disk must be
enlarged before further releases: each build retains roughly 0.5 GB until it ages out.

Image `sha256:278008c6398df2a769a76669a23d2a498e87be6dded86faa88f9648ec7181d47`, registry
manifest `sha256:b922a7be9f56ae9d8632087e753f22b5f52aab85b8670fb3fdc9e8a3d1de7fa7`, serving
revision `sha256:e7823ad3d686725d6c54f72337dda5fecfe704a9480e0acb73f9030b54dc7749`. Keys
`pythilo-learn-guide-manage-{build,publish,deploy}-20261111-v1` (build v2: v1 was refused
while the guard update timed out). Deployed 17:00:17 UTC. 92 site tests, TypeScript and the
776-page build pass; the public smoke suite passes and the live guide shows the new section.

## App Store release, pricing and two articles (13 November 2026)

Pythilo 1.0 (34) went on sale on 12 November 2026 (App Store Connect: `READY_FOR_SALE`,
175 territories, US$9.99). The site now says so: Pricing is "One price, paid once", the
home page, Support, the Terms (sections 3 and 4, dated 12 November) and the Labs pages
drop the beta wording, and "Get the app" opens `https://apps.apple.com/app/id6829637526`.
The blog adds "Pythilo 1.0 is on the App Store" (12 November, 2,434 words) and "How real
Python runs on an iPhone" (13 November, 2,381 words), each with a JPEG cover and one
WebP figure, generated as images and stored in `public/blog/<slug>/`.

`lib/site-route-cache.ts` now keeps only the newest archived build in
`.pythilo-previous-builds/` and deletes the older ones at start-up. Every release used
to leave about 90 MB there for good; the folder had reached 555 MB.

Overlay: 19 files, 703,929 bytes, SHA-256
`63d153701a6451fe5ff17686c62d2f660907799d577e1a4867de1d880c85b318`, sent in three chunks by
`build/release-tools/hostwatch_upload.py`. Server baselines of all replaced files matched
`HEAD` (`build/release-tools/hostwatch_tree.py`). This file is not part of the overlay.

Free disk was 8.58 GB and retention had nothing eligible, so with the owner's go-ahead
`minFreeBytes` was 7.5 GiB for this build only and is 10 GiB again (read back). The node
hosts Pythilo, Crabrix, Tellwick, Sharprune and Gopherforge on 40 GB; it needs a larger
disk, or the guard needs a lower permanent value, before releases can run unattended.

Source revision `sha256:26038660f5d12a763d85f0427b0a499520fa458d8caba2229a4e544e890a7f56`,
image `sha256:7553bf7f338c5400ce09603e9213dc29db28798f8eabefa534d00658265fe638`, registry
manifest `sha256:30aa4fad86fca54ec0d7412603c8b815e758ad707d9e8d6a7d421c2db8867083`, serving
revision `sha256:bab078ea48fef275031d9dc69a792d659d5f2b82e3f1b72217100cd9d29c318c`. Keys
`pythilo-appstore-launch-{build,publish,deploy}-20261113-v1`; deployed 05:41:23 UTC.
All 94 site tests, TypeScript and the production build pass; the smoke suite (65 checks,
now including Pricing, the App Store link and both articles) passes locally and against
https://pythilo.com.

