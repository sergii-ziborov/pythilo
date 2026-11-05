# Maintaining lessons and labs

The website and app share authored content. Change that source first; generated
`site/content/` is an ignored build input and must not be edited by hand.

## Courses

Courses live in `Pythilo/Resources/Courses/<number>-<id>.json`. The app bundles this
folder, and `site/scripts/prepare-assets.mjs` converts it into browser sections and
computes package availability. Keep existing course and lesson IDs stable: they
are URLs and saved-progress keys.

Each lesson needs a body, task, starter, solution, explanation, three progressive
hints and 3–6 named assertion checks. A path lesson's body has 60–180 prose words,
one or two fenced Python examples and headings no deeper than `##`. Examples
should fit a phone. The starter must compile and fail at least one check; the
solution must pass every check. Checks should exercise boundaries and mutations,
and should not depend on a clock, network or global randomness.

When adding a course, extend `EXPECTED_COURSES` in `scripts/verify-lessons.py` and
the ordered catalog assertion in `site/tests/python-runtime.test.mjs`. Run:

```sh
python3 scripts/verify-lessons.py --only algorithm-patterns,data-practice,reliable-python,ml-practice
npm --prefix site test
npm --prefix site run check
npm --prefix site run build
```

The site test runs every browser-compatible solution using the actual Pyodide
runtime and the app's checker. A missing package is reported as App required;
never advertise a torch, thread or server exercise as browser runnable.

## Shared lab expansion

New lab metadata is in
`Pythilo/PythonRuntime/pythilo_runtime/labcode/catalog-expansion.json`. Every entry
has an ID, title, summary, section, symbol, tint, idea and variant. The variant
points to a filename and prompt, with explicit `scales: false` unless a scaling
plan is implemented. Section and tint strings must match the Swift Codable enums.

Each lab has `<id>.practice.starter.py` and `<id>.practice.answer.py` in the same
folder. Register its callable and edge cases in `labs_extended.CASES`, and map its
ID to `labs_extended` in `labs_engine.MODULES`. Cases should include ordinary
inputs and meaningful traps: duplicates, ties, empty inputs, a negative cycle or
reuse of an item, as appropriate. Validators return a readable message or None.

`LabCatalog.swift` decodes the expansion metadata from the embedded Python
resources and appends it to the classic catalog. The site preparer reads that
same metadata, code and tracer into `site/content/labs.json`. Its browser pages
execute this tracer through the existing Python worker, never on the server.

The shared renderer inspects learner locals after each statement. Arrays,
variables, plots and scatter panels are supported by the browser. Add matching
browser rendering before introducing another panel type. `xs`, `ys`, `w`, `b` and
`history` enable the regression diagnostic panels. Comprehension internals are
omitted, and browser replay is capped at 180 frames while checks run separately.
Keep the supplied worked examples below that cap; the Pyodide integration test
asserts that they replay completely.

A scaling-enabled lab also needs a `scale` plan in its engine specification.
Do not enable the button merely by changing its metadata flag.

The native catalog assertion is deliberately exact: update the expected total in
`PythiloTests/LabsTests.swift` when adding entries. The focused tests to run are
`testTheCatalogHasSectionsAndManyLabs`, `testEveryAnswerTracesAndPassesItsChecks`,
`testEveryStarterFailsWithAReadableMessage` and
`FeatureGateTests/testEveryBundledLessonSolutionPassesOnTheDevice`.

## Publishing

Follow `site/DEPLOY.md`. The installed Hostwatch builder consumes prepared site
source and runs Next.js directly. Include regenerated `content/courses.json`,
`content/labs.json` and any changed worker assets in the source overlay. A source
build, registry publication and live deployment are separate operations.

Check `/learn/`, the new course routes and `/labs/` publicly after deployment.
Walk a failing starter, a passing solution, replay controls and saved progress in
the browser. Keep cross-origin isolation on `/labs/:path*` so Stop can interrupt
Python. Lab drafts and completed flags use versioned local-storage keys and are
covered by the website privacy policy.

New app content goes to TestFlight only under the current owner instruction.
Update the App Store draft's counts, TestFlight notes and relevant screenshot
artwork, but do not request App Review or Beta App Review. Verify screenshot
processing reaches COMPLETE and a build reaches internal beta testing before
reporting it as available.
