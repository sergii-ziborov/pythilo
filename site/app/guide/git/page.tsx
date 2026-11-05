import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";

export const metadata: Metadata = { title: "Git", description: "Git in Pythilo on iPhone and iPad: a real .git folder, changes and commits, branches, merge with conflicts, rebase, HTTPS clone and tokens in the Keychain." };

export default function Page() {
  return <>
    <GuideHeader slug="git" />
    <Toc items={[["real", "A real repository"], ["identity", "Your name and email"], ["sheet", "The Git screen"], ["remotes", "Remotes, fetch, pull and push"], ["tokens", "HTTPS tokens"], ["terminal", "Git in the terminal"], ["merge", "Merge and rebase"], ["not", "Not supported"]]} />

    <h2 id="real">A real repository</h2>
    <p>Pythilo uses libgit2, the library behind many Git tools, and keeps an ordinary <code>.git</code> folder in your project. Anything you commit on the phone is a normal Git history that any Git on a computer reads, and the other way round. On <code>init</code> and clone, Pythilo adds <code>.pythilo/</code> and <code>__pycache__/</code> to the repository&apos;s local exclude list so they never get committed by accident.</p>

    <h2 id="identity">Your name and email</h2>
    <p>Commits need an author. Set <span className="ui">Name</span> and <span className="ui">Email</span> under <span className="ui">Git</span> in <Link href="/guide/settings/">Settings</Link>, in the fields the Git screen shows when they are missing, or with <code>git config user.name</code> and <code>git config user.email</code>. They are stored on the device and written into every commit you make, as Git always does.</p>

    <h2 id="sheet">The Git screen</h2>
    <p>Open <span className="ui">Git</span> from the file drawer or the <span className="ui">⋯</span> menu. A project without history offers <span className="ui">Start a repository</span>, which creates one on the branch <code>main</code>. Otherwise the top shows the branch, how far it is ahead of or behind its remote, the remote&apos;s address and the current commit, and three tabs:</p>
    <Table head={["Tab", "What it does"]} rows={[
      [<strong key="t">Changes</strong>, <>Every changed file with what happened to it (added, modified, deleted, renamed, conflicted, untracked) and an <span className="ui">Include</span> tick, on by default. Tap a file for a coloured diff. Write a <span className="ui">Commit message</span> and tap <span className="ui">Commit</span> to stage the ticked files and commit them.</>],
      [<strong key="t">History</strong>, "The commits on this branch: message, short id, author and date."],
      [<strong key="t">Branches</strong>, <>Tap a branch to switch to it. Type a name under <span className="ui">New branch</span> and tap <span className="ui">Create</span>.</>],
    ]} />
    <p>Switching branches is safe: Pythilo refuses to switch if it would overwrite changes you have not committed.</p>

    <h2 id="remotes">Remotes, fetch, pull and push</h2>
    <p>Without a remote, the Git screen has an address field and <span className="ui">Add</span>. With one, it shows <span className="ui">Fetch</span>, <span className="ui">Pull</span> and <span className="ui">Push</span>. Pull fast-forwards your branch to the remote&apos;s; if both sides have new commits, merge them (below). Remotes use HTTPS addresses.</p>
    <Note title="New in this beta">Fetch, pull and push are new. If a remote misbehaves, please <Link href="/support/">tell us</Link> which host it was.</Note>

    <h2 id="tokens">HTTPS tokens</h2>
    <p>Private repositories need a username and an access token (a personal access token from GitHub, GitLab and the like; not your password). Enter them when you clone, or with the key button labelled <span className="ui">HTTPS token</span> on the Git screen. Pythilo keeps one token per host in the iOS Keychain, on this device only, readable only while the device is unlocked, and never in the project or its <code>.git</code> folder. <span className="ui">Settings</span> shows how many you have stored. A token typed into the address itself is refused.</p>

    <h2 id="terminal">Git in the terminal</h2>
    <p>The terminal&apos;s <code>git</code> speaks the commands you know:</p>
    <pre><code>{`git init                     git branch [name]
git status                   git switch [-c] name     (or checkout [-b])
git add . | path             git merge branch | --abort
git reset | restore path     git rebase branch
git commit -m "message"      git remote add origin URL
git log                      git fetch | pull | push
git diff [path]              git config user.name | user.email`}</code></pre>
    <p><code>git --version</code> prints <em>Pythilo Git, libgit2 1.9.7</em>. A subcommand that is not built in says so and lists the ones that are. To clone, use <span className="ui">Clone</span> on the Projects screen.</p>

    <h2 id="merge">Merge and rebase</h2>
    <ul>
      <li><code>git merge branch</code> fast-forwards when it can and makes a merge commit when it must. On a conflict it writes the usual conflict markers into the files, marks them <strong>!</strong> in the file tree and conflicted on the Git screen. Fix the files and commit, or <code>git merge --abort</code> to go back.</li>
      <li><code>git rebase branch</code> replays your commits on top of another branch. It is all or nothing: if it meets a conflict, it is undone and your branch is as it was.</li>
    </ul>

    <h2 id="not">Not supported</h2>
    <p>SSH remotes (use the HTTPS address), submodules and Git LFS are not supported.</p>
    <Pager slug="git" />
  </>;
}
