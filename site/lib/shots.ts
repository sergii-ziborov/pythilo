/** Screenshots of the iOS app in public/shots, taken on the simulator with the app's debug launch arguments. */
export type Shot = { file: string; device: "phone" | "ipad"; alt: string; title: string; caption: string };

const phone = (file: string, title: string, caption: string, alt: string): Shot => ({ file, device: "phone", title, caption, alt });

export const shots = {
  projects: phone("projects", "Projects are folders", "New, Clone or Import. Every project is an ordinary folder that also shows up in the Files app.", "The Projects screen with New, Clone and Import, and a list of recent projects"),
  editor: phone("editor", "An editor made for touch", "Syntax colours, completion that knows your modules, and problems flagged as you type.", "A FastAPI main.py open in the editor, with line numbers and syntax colours"),
  torch: phone("torch", "PyTorch, on the phone", "The PyTorch template trains a small network on the CPU, offline, to 97% test accuracy.", "The terminal in dark mode after python main.py trained a PyTorch network to 97 percent test accuracy"),
  django: phone("django", "Django serves from the phone", "runserver starts a real server. Open site shows it; migrate and friends are one tap away.", "A Django development server running in the terminal, with a Django is running banner and an Open site button"),
  preview: phone("preview", "Any path, in the preview", "A React page built by esbuild in the app, served by FastAPI on the same device.", "The web preview showing a React task list served by FastAPI from 127.0.0.1"),
  terminal: phone("terminal", "A terminal without a server", "pytest, pip, git and npm, built into the app. Nothing runs anywhere else.", "The terminal after pytest -q reported 2 passed, with command keys for python, pip, npm, pytest, git and ls"),
  notebook: phone("notebook", "Notebooks", "Ordinary .ipynb files, with cells that share one namespace and NumPy built in.", "A notebook called Rainfall by month with two code cells and Add code and Add text buttons"),
  files: phone("files", "Files, folders and Git status", "A drawer with nested folders, quick search, Packages, Git and Room one tap away.", "The file drawer of a Django project with nested folders and Packages, Git, Room and Share buttons"),
  learn: phone("learn", "A path through Python", "Courses from the first variable to PyTorch and language models, with progress on the device.", "The Learn screen with a Continue lesson card and the course path"),
  lesson: phone("lesson", "Lessons you can run", "Short parts, runnable examples, then a task checked on the device.", "A lesson about guard clauses with a runnable code example"),
  check: phone("check", "Checks that say what came back", "describe(3) returned None, expected 'int: 3'. Is a return missing?", "The check sheet listing five failed checks, each saying what came back and what was expected"),
  graphLab: phone("graph-lab", "Graph Explorer", "Your own BFS, DFS or Dijkstra, traced step by step on a grid, tree or random graph.", "Graph Explorer tracing a breadth-first search on a grid"),
  dpLab: phone("dp-lab", "Dynamic Programming", "How many calls a recursion repeats, and what a cache saves.", "The Dynamic Programming lab showing 177 calls, 11 distinct, for ways(10)"),
  labs: phone("labs", "Explore algorithms", "Write Python and trace how it works on this device.", "An earlier Labs overview showing Sorting Bench, Graph Explorer, Search and Hashing, and Dynamic Programming"),
  room: phone("room", "Rooms, with permission", "Someone asks to run code on your iPhone. You decide: deny, or run once.", "A shared room in dark mode where Ada asks to run python main.py on this iPhone, with Deny and Run once"),
  share: phone("share", "Share a project", "Choose how long the room lasts and who may edit. The relay only sees encrypted text.", "The Share sheet in dark mode with room length, edit or view, and run permissions"),
  playground: phone("playground", "Playground", "Share a project, join with a link, or connect an AI client on your network.", "The Playground tab with Share a project, Join with a link and AI client over MCP"),
  darkEditor: phone("dark-editor", "Light or dark", "Pythilo follows the system appearance, or the one you choose in Settings.", "A Django views.py open in the editor in dark mode"),
  coreml: phone("coreml", "Core ML from Python", "pythilo.coreml runs a model on the CPU, the GPU or the Neural Engine and times each one.", "Terminal output comparing Core ML timings on CPU, GPU and all compute units"),
  migrate: phone("migrate", "Migrations, one tap", "Django says migrations are missing; Migrate & restart applies them and starts again.", "A Django is running banner warning that 3 migrations are not applied, with a Migrate and restart button"),
  ipadDjango: { file: "ipad-django", device: "ipad", title: "iPad: project column and panel", caption: "Files on the left, the editor in the middle, the terminal below, and keyboard shortcuts when a keyboard is attached.", alt: "Pythilo on iPad with a Django project: file column, manage.py, a Django is running banner, and the terminal with Django command chips" },
  ipadLesson: { file: "ipad-lesson", device: "ipad", title: "iPad: read and code side by side", caption: "The lesson on the left, your code on the right, Check at the bottom.", alt: "A lesson on iPad with the reading on the left and the code editor on the right" },
} satisfies Record<string, Shot>;

/** The home page gallery, in the order of a first afternoon with the app. */
export const gallery: Shot[] = [shots.projects, shots.editor, shots.torch, shots.django, shots.preview, shots.terminal, shots.notebook, shots.learn, shots.check, shots.graphLab, shots.dpLab, shots.room];
