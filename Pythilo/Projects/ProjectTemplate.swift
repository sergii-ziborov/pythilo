import Foundation

struct ProjectTemplate: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let files: [String: String]

    private static let ignore = ".pythilo/\n__pycache__/\n*.sqlite3\n"

    static let all: [ProjectTemplate] = [blank, csvCleaner, djangoNotes, flaskAPI, asgiAPI, notebook]

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


            async def list_tasks(request):
                return JSONResponse(tasks)


            app = Starlette(routes=[Route("/tasks", list_tasks)])

            """,
            "README.md": "# ASGI\n\nIn the Terminal: `uvicorn main:app`\n",
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
