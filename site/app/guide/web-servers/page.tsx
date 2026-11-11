import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "Web servers and the preview", description: "Run Django, Flask, FastAPI and Starlette on iPhone and iPad with Pythilo, open the site in the built-in preview, apply migrations and stop the server." };

export default function Page() {
  return <>
    <GuideHeader slug="web-servers" />
    <Toc items={[["start", "Start a server"], ["banner", "Running and Open site"], ["preview", "The web preview"], ["migrations", "Django migrations"], ["after-changes", "After a change"], ["frameworks", "Framework notes"], ["limits", "Limits"]]} />

    <h2 id="start">Start a server</h2>
    <p>Start a server the way you would on a computer, from the terminal or with a chip: <code>python manage.py runserver</code> for Django, <code>flask --app hello run</code> for Flask, <code>uvicorn main:app</code> for FastAPI and Starlette. Running a file that serves (for example with <code>http.server</code>) works too. The templates <strong>Django notes</strong>, <strong>Flask app</strong>, <strong>FastAPI</strong>, <strong>ASGI API</strong> and <strong>React and FastAPI</strong> are ready to serve.</p>

    <h2 id="banner">Running and Open site</h2>
    <p>Pythilo notices when your program starts listening on a port, whatever the framework, and shows a banner: <em>Django is running</em> (or Flask, Uvicorn, or <em>Site is running</em>) with the address and an <span className="ui">Open site</span> button. The banner steps aside while you type. A globe button for the preview appears in the toolbar, and <span className="ui">Site</span> in the file drawer.</p>
    <figure><DeviceShot shot={shots.migrate} /><DeviceShot shot={shots.preview} /><figcaption>Django with migrations to apply, and a React site served by FastAPI in the preview.</figcaption></figure>

    <h2 id="preview">The web preview</h2>
    <p><span className="ui">Open site</span> shows the site in a <span className="ui">Web preview</span> sheet, with the server&apos;s latest output below it. The address bar has back, the server&apos;s address, an editable path (type <code>/admin/</code> or <code>/docs</code> and go) and reload. <span className="ui">Stop server</span> stops it; <span className="ui">Close</span> hides the preview and leaves the server running. On an iPad in landscape, the preview appears as a column beside the editor while the server runs.</p>
    <p>The preview is a normal web view. Pages that load scripts from the internet, such as FastAPI&apos;s <code>/docs</code>, which loads Swagger UI from a CDN, need a network connection for those parts.</p>

    <h2 id="migrations">Django migrations</h2>
    <p>When <code>runserver</code> reports unapplied migrations, the banner adds <em>N migrations are not applied. Pages that use the database will fail.</em> and a <span className="ui">Migrate &amp; restart</span> button, which runs <code>python manage.py migrate</code> and starts the server again. The <code>migrate</code> and <code>makemigrations</code> chips are always there too; a <code>migrate</code> run in another tab also clears the warning, without a restart.</p>

    <h2 id="after-changes">After a change</h2>
    <p>Autoreloaders start a second process, which iOS does not allow, so servers do not restart on their own when you save. Stop and run again. While your server runs, other terminal tabs keep working: tap <span className="ui">+</span> and run <code>migrate</code>, <code>test</code> or <code>git</code> there, and the site keeps answering. A command typed into the server&apos;s own tab runs in another tab. See <Link href="/guide/terminal/#servers-busy">Tabs</Link>.</p>

    <h2 id="frameworks">Framework notes</h2>
    <ul>
      <li><strong>Django</strong>: SQLite databases, migrations, the admin, <code>createsuperuser</code>, and <code>manage.py test</code> all work. <code>dbshell</code> does not, because it starts an external program.</li>
      <li><strong>Flask</strong>: runs without the reloader and without threads.</li>
      <li><strong>FastAPI</strong>: Pydantic validation, async routes, WebSockets and <code>TestClient</code> work; the template&apos;s tests pass on the device.</li>
      <li><strong>Uvicorn</strong>: one worker, on <code>127.0.0.1:8000</code> unless you pass <code>--host</code> or <code>--port</code>.</li>
    </ul>

    <h2 id="limits">Limits</h2>
    <Note>iOS pauses apps in the background, and a server pauses with Pythilo. Keep Pythilo open while you use the site. The preview ends when the run ends. To share a running project with someone else, use a <Link href="/guide/rooms/">room</Link>; the server itself is reachable only from this device.</Note>
    <Pager slug="web-servers" />
  </>;
}
