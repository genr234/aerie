# Export Guide

Use `Export Source Project` to download a zip of the editable project files.

Use `Export Playable Web Game` to create a static WebAssembly build of the engine with the current project baked into Emscripten's virtual filesystem. The exporter refuses to overwrite a non-empty destination folder, so choose a new folder or an empty folder.

Web export currently needs the Zig 0.16 toolchain available to the desktop editor. Set `ZIG` to a Zig binary, keep the bundled `.tools/zig-aarch64-macos-0.16.0` toolchain with the app during development, or use an app package that includes that toolchain as a resource. If the editor cannot find Zig, the export command reports that directly in the UI.

The exported folder contains:

- `index.html`
- Emscripten-generated engine assets such as `.wasm`, `.js`, and `.data`
- `README.html`

Playable web exports include `README.html`. Serve the exported folder locally before testing:

```sh
python3 -m http.server 8000
```

Then open `http://localhost:8000`.
