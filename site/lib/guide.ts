/** The pages of the app guide, in reading order. */
export type GuidePage = { slug: string; title: string; summary: string; group: string };

export const guidePages: GuidePage[] = [
  { slug: "getting-started", group: "Start", title: "Projects and files", summary: "Make, clone and import projects, templates, the file drawer and where files live." },
  { slug: "editor", group: "Start", title: "The editor and the key bar", summary: "Typing code on glass: the key bar, completion, problems, tabs and keyboard shortcuts." },
  { slug: "run-and-debug", group: "Start", title: "Run, stop and debug", summary: "Run a file, answer input(), stop anything, and step through code with breakpoints." },
  { slug: "terminal", group: "Tools", title: "The terminal", summary: "Built-in commands, framework chips, history, Ctrl-C and what iOS does not allow." },
  { slug: "packages", group: "Tools", title: "Packages, PyTorch and Core ML", summary: "pip per project, everything bundled, npm with esbuild, PyTorch and pythilo.coreml." },
  { slug: "web-servers", group: "Tools", title: "Web servers and the preview", summary: "Django, Flask, FastAPI and Starlette on the device, Open site, migrations and the preview." },
  { slug: "sqlite", group: "Tools", title: "SQLite", summary: "The sqlite3 command and the database browser. Coming in the next build." },
  { slug: "git", group: "Tools", title: "Git", summary: "A real .git folder: changes, commits, branches, merge, rebase, clone and HTTPS tokens." },
  { slug: "notebooks", group: "Tools", title: "Notebooks", summary: "Open and save .ipynb files, run cells, rich output and what is not Jupyter." },
  { slug: "learn", group: "Learn", title: "Courses, labs and interview practice", summary: "Lessons, checks, hints, Debug in a project, the four labs and timed tasks." },
  { slug: "rooms", group: "Together", title: "Playground and shared rooms", summary: "Share a project by link, join one, permissions for editing and running code." },
  { slug: "connect-ai", group: "Together", title: "Connect an AI client", summary: "Let Claude Code, Codex or any MCP client work on one project, with your permission." },
  { slug: "settings", group: "Reference", title: "Settings", summary: "Every setting, what it changes, and where Pythilo keeps it." },
  { slug: "layouts", group: "Reference", title: "iPhone, iPad and foldable layouts", summary: "How the workspace arranges itself on each screen shape and pose." },
  { slug: "limits", group: "Reference", title: "What runs on iOS", summary: "What works on the device, what iOS does not allow, and what to know about safety." },
];

export const guidePage = (slug: string) => guidePages.find(page => page.slug === slug);
