import type { Metadata } from "next";
import Link from "next/link";
import { Table, Toc } from "@/components/guide/doc";
import { OWNER } from "@/lib/site-info";
import { appRuntime, bridgeComponents, pythonPackages, siteLicense, type Component } from "@/lib/licenses";
import { PYODIDE_VERSION } from "@/lib/python-runtime";
import site from "@/package.json";

export const metadata: Metadata = { title: "Open-source licences", description: "The open-source components in the Pythilo app, its website and the Pythilo MCP bridge, with their versions and licences." };

const rows = (items: Component[]) => items.map(item => [<a key="n" href={item.url} target="_blank" rel="noreferrer">{item.name}</a>, item.version ?? "", item.license, item.note ?? ""]);

export default function LicensesPage() {
  const deps = Object.entries(site.dependencies as Record<string, string>);
  return <>
    <header>
      <span className="label">Legal</span>
      <h1>Open-source licences</h1>
      <p>Pythilo stands on a lot of open-source work. These are the components in the app, on this website and in the Pythilo MCP bridge, with the licences they are used under. Thank you to everyone who makes them.</p>
    </header>
    <Toc items={[["pythilo", "Pythilo itself"], ["runtime", "In the app: runtime and libraries"], ["python", "In the app: Python packages"], ["website", "On this website"], ["bridge", "In the MCP bridge"], ["texts", "Licence texts"]]} />

    <h2 id="pythilo">Pythilo itself</h2>
    <p>Pythilo, its website and its courses are © 2026 {OWNER}. All rights reserved. The source is public to read on GitHub, but it is not open source: no licence is granted to use, copy, modify or distribute it. The open-source components below keep their own licences, which this does not limit.</p>

    <h2 id="runtime">In the app: runtime and libraries</h2>
    <Table head={["Component", "Version", "Licence", "Notes"]} rows={rows(appRuntime)} />

    <h2 id="python">In the app: Python packages</h2>
    <p>Bundled with the app and listed in Settings › Python › Licenses. Each package&apos;s full licence ships inside the app, in its <code>.dist-info</code> folder. Packages you install yourself with pip or npm come with their own licences.</p>
    <Table head={["Package", "Version", "Licence"]} rows={pythonPackages.map(([name, version, license]) => [<a key="n" href={`https://pypi.org/project/${name}/${version}/`} target="_blank" rel="noreferrer">{name}</a>, version, license])} />

    <h2 id="website">On this website</h2>
    <p>Python in your browser runs on <a href="https://pyodide.org" target="_blank" rel="noreferrer">Pyodide</a> {PYODIDE_VERSION} (Mozilla Public License 2.0), served from this site together with the package wheels the lessons need (NumPy, pytest and their dependencies, each under its own licence). The site is built with:</p>
    <Table head={["Package", "Version", "Licence"]} rows={deps.map(([name, version]) => [<a key="n" href={`https://www.npmjs.com/package/${name}`} target="_blank" rel="noreferrer">{name}</a>, version.replace(/^[\^~]/, ""), siteLicense(name)])} />

    <h2 id="bridge">In the MCP bridge</h2>
    <p>The <Link href="/ai/">Pythilo MCP bridge</Link> that lets an AI client join a room includes:</p>
    <Table head={["Component", "Version", "Licence", "Notes"]} rows={rows(bridgeComponents)} />

    <h2 id="texts">Licence texts</h2>
    <p>The full licence texts are linked above and ship with each component: in the app bundle for the app&apos;s components, in the site&apos;s dependencies for the website, and in <code>ThirdPartyNotices.txt</code> for the bridge. Some editor, Git build and layout code comes from Crabrix and SharpRune, which have the same owner.</p>
  </>;
}
