import Foundation

struct ProjectTemplate: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let files: [String: String]

    private static let ignore = ".pythilo/\n__pycache__/\n*.sqlite3\n"

    static let all: [ProjectTemplate] = [blank, csvCleaner, djangoNotes, flaskAPI, fastAPI, reactFastAPI, asgiAPI, notebook, coreML]

    static let blank = ProjectTemplate(
        id: "blank",
        title: "Empty",
        summary: "One file, ready to run",
        systemImage: "doc",
        files: [
            "main.py": "print(\"Hello from Python on this device\")\n",
            ".gitignore": ignore,
        ]
    )

    static let csvCleaner = ProjectTemplate(
        id: "csv",
        title: "CSV cleaner",
        summary: "Files, a module and tests",
        systemImage: "tablecells",
        files: [
            "main.py": """
            import csv
            from pathlib import Path

            from cleaner import clean_row


            def read_rows(source):
                return [clean_row(row) for row in csv.DictReader(source)]


            def save(rows, target):
                with target.open("w", newline="") as out:
                    writer = csv.DictWriter(out, ["name", "city"])
                    writer.writeheader()
                    writer.writerows(rows)


            if __name__ == "__main__":
                with Path("people.csv").open() as source:
                    rows = read_rows(source)
                print(f"Read {len(rows)} rows from people.csv")
                for row in rows:
                    print(row)
                name = input("Clean file name? ")
                save(rows, Path(name))
                print("Saved", name)

            """,
            "cleaner.py": """
            def clean_row(row):
                name = row["name"].strip()
                city = row["city"].strip() or "unknown"
                return {"name": name, "city": city}

            """,
            "test_cleaner.py": """
            from cleaner import clean_row


            def test_trims_names():
                assert clean_row({"name": " Ada ", "city": "London"})["name"] == "Ada"


            def test_empty_city():
                assert clean_row({"name": "Grace", "city": ""})["city"] == "unknown"

            """,
            "people.csv": "name,city\nAda Lovelace,London\n Alan Turing ,Wilmslow\nGrace Hopper,\nGuido van Rossum,Belmont\n",
            "README.md": "# CSV cleaner\n\nRun `main.py`, or `pytest` in the Terminal.\n",
            ".gitignore": ignore,
        ]
    )

    static let djangoNotes = ProjectTemplate(
        id: "django",
        title: "Django notes",
        summary: "Models, templates, SQLite",
        systemImage: "globe",
        files: [
            "manage.py": """
            import os
            import sys

            from django.core.management import execute_from_command_line

            os.environ.setdefault("DJANGO_SETTINGS_MODULE", "site_config.settings")
            execute_from_command_line(sys.argv)

            """,
            "site_config/__init__.py": "",
            "site_config/settings.py": """
            from pathlib import Path

            BASE_DIR = Path(__file__).resolve().parent.parent
            SECRET_KEY = "only-for-local-development"
            DEBUG = True
            ALLOWED_HOSTS = ["127.0.0.1", "localhost"]
            ROOT_URLCONF = "site_config.urls"
            INSTALLED_APPS = [
                "django.contrib.contenttypes",
                "django.contrib.staticfiles",
                "notes",
            ]
            MIDDLEWARE = ["django.middleware.csrf.CsrfViewMiddleware"]
            TEMPLATES = [
                {
                    "BACKEND": "django.template.backends.django.DjangoTemplates",
                    "APP_DIRS": True,
                    "OPTIONS": {"context_processors": ["django.template.context_processors.request"]},
                }
            ]
            DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3"}}
            STATIC_URL = "static/"
            USE_TZ = True

            """,
            "site_config/urls.py": """
            from django.urls import path

            from notes import views

            urlpatterns = [
                path("", views.note_list, name="notes"),
                path("new", views.note_new, name="note_new"),
            ]

            """,
            "notes/__init__.py": "",
            "notes/models.py": """
            from django.db import models


            class Note(models.Model):
                text = models.CharField(max_length=500)
                created = models.DateTimeField(auto_now_add=True)

            """,
            "notes/views.py": """
            from django.shortcuts import redirect, render

            from .models import Note


            def note_list(request):
                notes = Note.objects.order_by("-created")
                return render(request, "notes/list.html", {"notes": notes})


            def note_new(request):
                if request.method == "POST":
                    text = request.POST["text"].strip()
                    if text:
                        Note.objects.create(text=text)
                return redirect("notes")

            """,
            "notes/migrations/__init__.py": "",
            "notes/migrations/0001_initial.py": """
            from django.db import migrations, models


            class Migration(migrations.Migration):
                initial = True
                dependencies = []
                operations = [
                    migrations.CreateModel(
                        name="Note",
                        fields=[
                            ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                            ("text", models.CharField(max_length=500)),
                            ("created", models.DateTimeField(auto_now_add=True)),
                        ],
                    ),
                ]

            """,
            "notes/templates/notes/list.html": """
            <!doctype html>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>My notes</title>
            <style>body{font:17px -apple-system,sans-serif;margin:24px}input{font:inherit;padding:10px;width:60%}button{font:inherit;padding:10px 14px}li{padding:10px 0;border-bottom:1px solid #ddd;list-style:none}ul{padding:0}</style>
            <h1>My notes</h1>
            <form method="post" action="{% url 'note_new' %}">{% csrf_token %}
              <input name="text" placeholder="Write a note"> <button>Add</button>
            </form>
            <ul>{% for note in notes %}<li>{{ note.text }}</li>{% empty %}<li>No notes yet.</li>{% endfor %}</ul>

            """,
            "README.md": "# Notes\n\nIn the Terminal:\n\n    python manage.py migrate\n    python manage.py runserver\n",
            ".gitignore": ignore,
        ]
    )

    static let flaskAPI = ProjectTemplate(
        id: "flask",
        title: "Flask app",
        summary: "A small JSON API",
        systemImage: "network",
        files: [
            "hello.py": """
            from flask import Flask, jsonify

            app = Flask(__name__)
            tasks = ["Read the docs", "Write a test"]


            @app.get("/")
            def home():
                return jsonify(tasks=tasks)

            """,
            "README.md": "# Flask\n\nIn the Terminal: `flask --app hello run`\n",
            ".gitignore": ignore,
        ]
    )

    static let asgiAPI = ProjectTemplate(
        id: "asgi",
        title: "ASGI API",
        summary: "Starlette on Uvicorn",
        systemImage: "bolt",
        files: [
            "main.py": """
            from starlette.applications import Starlette
            from starlette.responses import JSONResponse
            from starlette.routing import Route

            tasks = [{"id": 1, "title": "Read the docs"}]


            async def home(request):
                return JSONResponse({"name": "Tasks", "try": ["/tasks"]})


            async def list_tasks(request):
                return JSONResponse(tasks)


            app = Starlette(routes=[Route("/", home), Route("/tasks", list_tasks)])

            """,
            "README.md": "# ASGI\n\nIn the Terminal: `uvicorn main:app`\n",
            ".gitignore": ignore,
        ]
    )

    static let fastAPI = ProjectTemplate(
        id: "fastapi",
        title: "FastAPI",
        summary: "Validated models, async, a WebSocket",
        systemImage: "bolt.horizontal",
        files: [
            "main.py": """
            from fastapi import FastAPI, HTTPException, WebSocket
            from pydantic import BaseModel, Field

            app = FastAPI(title="Tasks")


            class TaskIn(BaseModel):
                title: str = Field(min_length=1, max_length=80)
                done: bool = False


            class Task(TaskIn):
                id: int


            tasks: dict[int, Task] = {}


            @app.get("/")
            async def home() -> dict:
                return {"name": "Tasks", "try": ["/tasks", "/tasks/1", "/openapi.json"]}


            @app.get("/tasks")
            async def list_tasks() -> list[Task]:
                return list(tasks.values())


            @app.post("/tasks", status_code=201)
            async def add_task(task: TaskIn) -> Task:
                created = Task(id=len(tasks) + 1, **task.model_dump())
                tasks[created.id] = created
                return created


            @app.get("/tasks/{task_id}")
            async def get_task(task_id: int) -> Task:
                if task_id not in tasks:
                    raise HTTPException(status_code=404, detail="No such task")
                return tasks[task_id]


            @app.websocket("/shout")
            async def shout(socket: WebSocket):
                await socket.accept()
                async for text in socket.iter_text():
                    await socket.send_text(text.upper())

            """,
            "test_main.py": """
            from fastapi.testclient import TestClient

            from main import app

            client = TestClient(app)


            def test_add_and_read_a_task():
                created = client.post("/tasks", json={"title": "Write tests"})
                assert created.status_code == 201
                assert client.get(f"/tasks/{created.json()['id']}").json()["title"] == "Write tests"


            def test_an_empty_title_is_rejected():
                assert client.post("/tasks", json={"title": ""}).status_code == 422


            def test_the_socket_shouts_back():
                with client.websocket_connect("/shout") as socket:
                    socket.send_text("hi")
                    assert socket.receive_text() == "HI"

            """,
            "README.md": "# Task API\n\nIn the Terminal: `uvicorn main:app`, then open the preview. `pytest` runs the tests.\n\n`/openapi.json` works offline. `/docs` loads Swagger UI from a CDN, so it needs the network.\n",
            ".gitignore": ignore,
        ]
    )

    static let reactFastAPI = ProjectTemplate(
        id: "react",
        title: "React and FastAPI",
        summary: "npm, esbuild and an API, one site",
        systemImage: "atom",
        files: [
            "main.py": """
            from fastapi import FastAPI
            from fastapi.staticfiles import StaticFiles
            from pydantic import BaseModel, Field

            app = FastAPI(title="Tasks")
            tasks = [{"id": 1, "title": "Try the React page", "done": False}]


            class TaskIn(BaseModel):
                title: str = Field(min_length=1, max_length=80)


            @app.get("/api/tasks")
            async def list_tasks() -> list[dict]:
                return tasks


            @app.post("/api/tasks", status_code=201)
            async def add_task(task: TaskIn) -> dict:
                created = {"id": len(tasks) + 1, "title": task.title, "done": False}
                tasks.append(created)
                return created


            # The React app, built by npm run build into static/assets.
            app.mount("/", StaticFiles(directory="static", html=True), name="site")

            """,
            "package.json": """
            {
              "name": "tasks",
              "private": true,
              "scripts": {
                "build": "esbuild src/main.jsx --bundle --minify --outdir=static/assets",
                "dev": "esbuild src/main.jsx --bundle --outdir=static/assets --watch"
              },
              "dependencies": {
                "react": "^19.3.1",
                "react-dom": "^19.3.1"
              },
              "devDependencies": {
                "esbuild": "^0.28.2"
              }
            }

            """,
            "src/main.jsx": """
            import { createRoot } from "react-dom/client";
            import { useEffect, useState } from "react";
            import "./style.css";

            function App() {
              const [tasks, setTasks] = useState([]);
              const [title, setTitle] = useState("");
              const [error, setError] = useState("");

              useEffect(() => {
                fetch("/api/tasks")
                  .then((response) => response.json())
                  .then(setTasks, () => setError("The API did not answer."));
              }, []);

              async function add(event) {
                event.preventDefault();
                const response = await fetch("/api/tasks", {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ title }),
                });
                if (!response.ok) {
                  setError("A task needs a title.");
                  return;
                }
                setTasks([...tasks, await response.json()]);
                setTitle("");
                setError("");
              }

              return (
                <main>
                  <h1>Tasks</h1>
                  <p className="note">React, built by esbuild in Pythilo, served by FastAPI on this device.</p>
                  <form onSubmit={add}>
                    <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Write a task" aria-label="Task title" />
                    <button>Add</button>
                  </form>
                  {error && <p className="error">{error}</p>}
                  <ul>
                    {tasks.map((task) => (
                      <li key={task.id}>{task.title}</li>
                    ))}
                  </ul>
                </main>
              );
            }

            createRoot(document.getElementById("root")).render(<App />);

            """,
            "src/style.css": """
            body { margin: 0; font-family: -apple-system, system-ui, sans-serif; background: #f5f7fa; color: #141a22; }
            main { max-width: 34rem; margin: 0 auto; padding: 2rem 1.25rem; }
            h1 { margin: 0 0 0.25rem; }
            .note { color: #55606e; margin: 0 0 1.25rem; }
            form { display: flex; gap: 0.5rem; }
            input { flex: 1; font: inherit; padding: 0.7rem 0.8rem; border: 1px solid #d5dce5; border-radius: 0.6rem; }
            button { font: inherit; font-weight: 600; padding: 0 1.1rem; border: 0; border-radius: 0.6rem; background: #0b62c4; color: white; }
            .error { color: #a3201a; }
            li { padding: 0.75rem 0; border-bottom: 1px solid #e8edf3; }

            """,
            "static/index.html": """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Tasks</title>
              <link rel="stylesheet" href="/assets/main.css">
            </head>
            <body>
              <div id="root">
                <p style="font-family: system-ui; padding: 1.5rem">Not built yet. In the Terminal: <code>npm install</code>, then <code>npm run build</code>, then reload this page.</p>
              </div>
              <script src="/assets/main.js"></script>
            </body>
            </html>

            """,
            "README.md": "# Tasks: React and FastAPI\n\nIn the Terminal, one at a time:\n\n    npm install\n    npm run build\n    uvicorn main:app\n\nnpm install fetches React from the npm registry. npm run build bundles src/ with esbuild, which runs inside Pythilo. npm run dev rebuilds on every save. FastAPI serves the API at /api/tasks and the built site at /.\n",
            ".gitignore": ignore + "node_modules/\nstatic/assets/\n",
        ]
    )

    static let coreML = ProjectTemplate(
        id: "coreml",
        title: "Neural Engine",
        summary: "Core ML models from Python",
        systemImage: "cpu",
        files: [
            "main.py": """
            \"\"\"The same Core ML model on the CPU, the GPU and the Neural Engine, timed,
            with every answer checked against the CPU's.\"\"\"

            import numpy

            from pythilo import coreml

            info = coreml.devices()
            print("Core ML sees:", ", ".join(info["devices"]))
            if not info["neuralEngine"]:
                where = " (this is the simulator)" if info["simulator"] else ""
                print(f"No Neural Engine here{where}, so ane runs on the CPU.")

            coreml.report(coreml.benchmark(runs=10))

            with coreml.sample(compute="ane") as model:
                image = numpy.random.default_rng(1).standard_normal((3, 224, 224)).astype("float32")
                probabilities = model.predict({"image": image})["probabilities"]
                print(f"class {int(probabilities.argmax())}, p={probabilities.max():.3f}, in {model.last_milliseconds:.2f} ms")

            """,
            "README.md": "# Neural Engine\n\nPyTorch does not run on an iPhone or iPad, and the Neural Engine is only reached through Core ML. So: train on a computer, convert with coremltools, copy the .mlpackage or .mlmodel into this project, then\n\n    from pythilo import coreml\n    model = coreml.load(\"classifier.mlpackage\", compute=\"ane\")\n    out = model.predict({\"image\": array})\n\nmain.py times Pythilo's sample model on each compute unit. Its weights are random; the point is speed and agreement, not the answer.\n",
            ".gitignore": ignore,
        ]
    )

    static let notebook = ProjectTemplate(
        id: "notebook",
        title: "Notebook",
        summary: "Cells and NumPy",
        systemImage: "text.book.closed",
        files: [
            "study.ipynb": #"""
            {
             "cells": [
              {"cell_type": "markdown", "metadata": {}, "source": ["# Rainfall by month\n", "\n", "Twelve months of readings, in millimetres."]},
              {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": ["import numpy as np\n", "rain = np.array([62, 48, 41, 44, 51, 55, 48, 59, 54, 72, 79, 74])\n", "rain.mean()"]},
              {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": ["for month, value in enumerate(rain, 1):\n", "    print(f\"{month:>2} {'#' * (int(value) // 4)}\")"]}
             ],
             "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"}},
             "nbformat": 4,
             "nbformat_minor": 5
            }

            """#,
            ".gitignore": ignore,
        ]
    )
}
