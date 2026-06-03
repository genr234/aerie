# Export Guide

Use `Export Source Project` to download a zip of the editable project files.

Use `Export Playable Web Game` to create a static web build. The exporter copies the prebuilt browser runner plus `game.json` and `assets/**`; it does not require Zig, Emscripten, or project-specific build tools. The exporter refuses to overwrite a non-empty destination folder, so choose a new folder or an empty folder.

The exported folder contains:

- `index.html`
- `runner.js`
- `game.json`
- `assets/**`
- `README.html`

Playable web exports include `README.html`. Serve the exported folder locally before testing:

```sh
python3 -m http.server 8000
```

Then open `http://localhost:8000`.
