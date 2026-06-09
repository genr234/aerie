use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{BufRead, BufReader},
    path::{Component, Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};
use tauri::{Emitter, Manager, State};
use tempfile::TempDir;

#[derive(Default)]
struct PreviewState {
    process: Mutex<Option<PreviewProcess>>,
}

struct PreviewProcess {
    child: Arc<Mutex<Child>>,
    _project_dir: TempDir,
}

#[derive(Deserialize, Serialize)]
struct PreviewFile {
    path: String,
    bytes: Vec<u8>,
}

#[derive(Deserialize)]
struct ProjectFolderRequest {
    root: String,
    files: Vec<PreviewFile>,
}

#[derive(Deserialize)]
struct ExportWebRequest {
    destination: String,
    files: Vec<PreviewFile>,
}

const MAX_PROJECT_FILE_BYTES: u64 = 25 * 1024 * 1024;
const IGNORED_PROJECT_DIRS: &[&str] = &[
    ".git",
    ".hg",
    ".svn",
    ".tauri",
    "node_modules",
    "target",
    "zig-cache",
    "zig-out",
    "zig-pkg",
    "dist",
    "build",
    ".svelte-kit",
    ".claude",
    "apps",
    "frontend",
    "reference",
    "src",
    "src-tauri",
];

#[tauri::command]
fn open_project_folder(root: String) -> Result<Vec<PreviewFile>, String> {
    let root = PathBuf::from(root);
    let manifest = root.join("game.json");
    if !manifest.exists() {
        return Err(format!("{} does not contain game.json", root.display()));
    }

    let mut files = Vec::new();
    read_project_files(&root, &root, &mut files)?;
    Ok(files)
}

#[tauri::command]
fn save_project_folder(request: ProjectFolderRequest) -> Result<String, String> {
    let root = PathBuf::from(request.root);
    fs::create_dir_all(&root).map_err(to_string)?;
    write_files_to_dir(&root, request.files)?;
    Ok(format!("Saved project to {}.", root.display()))
}

#[tauri::command]
fn export_web_bundle(app: tauri::AppHandle, request: ExportWebRequest) -> Result<String, String> {
    let destination = PathBuf::from(request.destination);
    if destination.exists() {
        if !destination.is_dir() {
            return Err(format!(
                "export destination exists and is not a folder: {}",
                destination.display()
            ));
        }
        if !is_dir_empty(&destination)? {
            return Err(format!(
                "export destination already exists and is not empty: {}. Choose an empty folder or a new export name.",
                destination.display()
            ));
        }
    }
    fs::create_dir_all(&destination).map_err(to_string)?;
    let project_dir = tempfile::Builder::new()
        .prefix("game-engine-web-export-")
        .tempdir()
        .map_err(to_string)?;
    write_files_to_dir(project_dir.path(), request.files)?;
    build_wasm_web_export(&app, project_dir.path(), &destination)?;
    write_web_export_readme(&destination)?;

    Ok(format!("Exported web game to {}.", destination.display()))
}

#[tauri::command]
fn start_preview(
    app: tauri::AppHandle,
    state: State<'_, PreviewState>,
    files: Vec<PreviewFile>,
) -> Result<String, String> {
    stop_preview_state(&state)?;

    let project_dir = tempfile::Builder::new()
        .prefix("game-engine-preview-")
        .tempdir()
        .map_err(to_string)?;

    write_files_to_dir(project_dir.path(), files)?;

    let engine_path = resolve_engine_path(&app)?;
    let _ = app.emit(
        "preview-log",
        serde_json::json!({
            "stream": "stdout",
            "line": format!("[preview] launching {}", engine_path.display()),
        }),
    );
    let mut child = Command::new(&engine_path)
        .arg(project_dir.path())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to launch {}: {error}", engine_path.display()))?;

    if let Some(stdout) = child.stdout.take() {
        stream_preview_output(app.clone(), "stdout", stdout);
    }
    if let Some(stderr) = child.stderr.take() {
        stream_preview_output(app.clone(), "stderr", stderr);
    }

    let child = Arc::new(Mutex::new(child));
    monitor_preview_process(app.clone(), child.clone());

    *state.process.lock().map_err(lock_error)? = Some(PreviewProcess {
        child,
        _project_dir: project_dir,
    });

    Ok("Preview running.".to_string())
}

#[tauri::command]
fn stop_preview(state: State<'_, PreviewState>) -> Result<String, String> {
    stop_preview_state(&state)
}

fn stop_preview_state(state: &PreviewState) -> Result<String, String> {
    if let Some(preview) = state.process.lock().map_err(lock_error)?.take() {
        if let Ok(mut child) = preview.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
    Ok("Preview stopped.".to_string())
}

fn write_files_to_dir(root: &Path, files: Vec<PreviewFile>) -> Result<(), String> {
    for file in files {
        let relative = safe_relative_path(&file.path)?;
        let output_path = root.join(relative);
        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent).map_err(to_string)?;
        }
        fs::write(output_path, file.bytes).map_err(to_string)?;
    }
    Ok(())
}

fn read_project_files(root: &Path, dir: &Path, out: &mut Vec<PreviewFile>) -> Result<(), String> {
    for entry in fs::read_dir(dir).map_err(to_string)? {
        let entry = entry.map_err(to_string)?;
        let path = entry.path();
        if path.is_dir() {
            if should_ignore_project_dir(&path) {
                continue;
            }
            read_project_files(root, &path, out)?;
        } else if path.is_file() {
            let metadata = entry.metadata().map_err(to_string)?;
            if metadata.len() > MAX_PROJECT_FILE_BYTES {
                continue;
            }
            let relative = path
                .strip_prefix(root)
                .map_err(to_string)?
                .to_string_lossy()
                .replace('\\', "/");
            out.push(PreviewFile {
                path: relative,
                bytes: fs::read(path).map_err(to_string)?,
            });
        }
    }
    Ok(())
}

fn should_ignore_project_dir(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| IGNORED_PROJECT_DIRS.contains(&name))
}

fn is_dir_empty(path: &Path) -> Result<bool, String> {
    Ok(fs::read_dir(path).map_err(to_string)?.next().is_none())
}

fn write_web_export_readme(destination: &Path) -> Result<(), String> {
    let readme = r#"<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Run This Game</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 720px; margin: 48px auto; line-height: 1.5; color: #20242a; }
    code { background: #eef1f4; padding: 2px 5px; border-radius: 4px; }
    pre { background: #20242a; color: white; padding: 16px; overflow: auto; }
  </style>
</head>
<body>
  <h1>Run This Game</h1>
  <p>This folder is a playable static web export. For browser security reasons, run it from a local web server instead of opening <code>index.html</code> directly.</p>
  <pre>python3 -m http.server 8000</pre>
  <p>Then open <a href="http://localhost:8000">http://localhost:8000</a>.</p>
</body>
</html>
"#;
    fs::write(destination.join("README.html"), readme).map_err(to_string)
}

fn stream_preview_output<R>(app: tauri::AppHandle, stream: &'static str, reader: R)
where
    R: std::io::Read + Send + 'static,
{
    thread::spawn(move || {
        for line in BufReader::new(reader).lines().map_while(Result::ok) {
            let _ = app.emit(
                "preview-log",
                serde_json::json!({
                    "stream": stream,
                    "line": line,
                }),
            );
        }
    });
}

fn monitor_preview_process(app: tauri::AppHandle, child: Arc<Mutex<Child>>) {
    thread::spawn(move || {
        let status = loop {
            let status = match child.lock() {
                Ok(mut child) => child.try_wait(),
                Err(_) => {
                    let _ = app.emit(
                        "preview-log",
                        serde_json::json!({
                            "stream": "stderr",
                            "line": "[preview] process monitor lock failed",
                        }),
                    );
                    return;
                }
            };
            match status {
                Ok(Some(status)) => break Ok(status),
                Ok(None) => thread::sleep(Duration::from_millis(250)),
                Err(error) => break Err(error),
            }
        };

        let line = match status {
            Ok(status) => match status.code() {
                Some(code) => format!("[preview] exited with code {code}"),
                None => "[preview] exited without a status code".to_string(),
            },
            Err(error) => format!("[preview] wait failed: {error}"),
        };

        let _ = app.emit(
            "preview-log",
            serde_json::json!({
                "stream": "stdout",
                "line": line,
            }),
        );
    });
}

fn safe_relative_path(path: &str) -> Result<PathBuf, String> {
    let normalized = path.replace('\\', "/");
    let candidate = Path::new(&normalized);
    let mut out = PathBuf::new();

    for component in candidate.components() {
        match component {
            Component::Normal(part) => out.push(part),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(format!("invalid project file path: {path}"));
            }
        }
    }

    if out.as_os_str().is_empty() {
        return Err("empty project file path".to_string());
    }

    Ok(out)
}

fn resolve_engine_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let repo_engine = repo_engine_path()?;

    if cfg!(debug_assertions) && repo_engine.exists() {
        return Ok(repo_engine);
    }

    if let Ok(resource_dir) = app.path().resource_dir() {
        let bundled = resource_dir.join(engine_binary_name());
        if bundled.exists() {
            return Ok(bundled);
        }
    }

    if repo_engine.exists() {
        return Ok(repo_engine);
    }

    Err(format!(
        "game_engine binary not found. Run `just build` first; expected {}",
        repo_engine.display()
    ))
}

fn repo_engine_path() -> Result<PathBuf, String> {
    Ok(repo_root()?
        .join("zig-out")
        .join("bin")
        .join(engine_binary_name()))
}

fn repo_root() -> Result<PathBuf, String> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .map(Path::to_path_buf)
        .ok_or_else(|| "failed to resolve repository root".to_string())
}

fn build_wasm_web_export(
    app: &tauri::AppHandle,
    project_root: &Path,
    destination: &Path,
) -> Result<(), String> {
    let repo = resolve_engine_source_root(app)?;
    let build_dir = tempfile::Builder::new()
        .prefix("game-engine-wasm-build-")
        .tempdir()
        .map_err(to_string)?;
    let prefix = build_dir.path().join("out");
    let zig = resolve_zig_path(app, &repo)?;

    let output = Command::new(&zig)
        .current_dir(&repo)
        .arg("build")
        .arg("-Dtarget=wasm32-emscripten")
        .arg("-Doptimize=ReleaseSmall")
        .arg(format!("-Dproject-root={}", project_root.display()))
        .arg("--prefix")
        .arg(&prefix)
        .output()
        .map_err(|error| format!("failed to launch {}: {error}", zig.display()))?;

    if !output.status.success() {
        return Err(format!(
            "WASM web build failed.\n\nstdout:\n{}\n\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    let web_dir = prefix.join("web");
    if !web_dir.is_dir() {
        return Err(format!(
            "WASM web build did not produce expected folder: {}",
            web_dir.display()
        ));
    }

    copy_dir_contents(&web_dir, destination)?;
    promote_engine_html(destination)
}

fn resolve_zig_path(app: &tauri::AppHandle, repo: &Path) -> Result<PathBuf, String> {
    if let Some(path) = std::env::var_os("ZIG") {
        let path = PathBuf::from(path);
        if path.exists() {
            return Ok(path);
        }
        return Err(format!(
            "WASM export needs Zig, but ZIG points to a missing file: {}",
            path.display()
        ));
    }

    let bundled = repo
        .join(".tools")
        .join("zig-aarch64-macos-0.16.0")
        .join("zig");
    if bundled.exists() {
        return Ok(bundled);
    }

    if let Ok(resource_dir) = app.path().resource_dir() {
        let resource_zig = resource_dir.join("zig-aarch64-macos-0.16.0").join("zig");
        if resource_zig.exists() {
            return Ok(resource_zig);
        }
    }

    Err(
        "WASM export needs the Zig 0.16 toolchain because project assets are baked into the browser build. Set ZIG to a Zig binary, keep .tools/zig-aarch64-macos-0.16.0 next to the source tree, or use an app build that includes the Zig resource."
            .to_string(),
    )
}

fn resolve_engine_source_root(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let repo = repo_root()?;
    if repo.join("build.zig").exists() && repo.join("src").is_dir() {
        return Ok(repo);
    }

    if let Ok(resource_dir) = app.path().resource_dir() {
        if resource_dir.join("build.zig").exists() && resource_dir.join("src").is_dir() {
            return Ok(resource_dir);
        }
    }

    Err("WASM export needs the engine source files. This app package does not include build.zig and src/ as resources.".to_string())
}

fn copy_dir_contents(from: &Path, to: &Path) -> Result<(), String> {
    for entry in fs::read_dir(from).map_err(to_string)? {
        let entry = entry.map_err(to_string)?;
        let source = entry.path();
        let target = to.join(entry.file_name());
        if source.is_dir() {
            fs::create_dir_all(&target).map_err(to_string)?;
            copy_dir_contents(&source, &target)?;
        } else if source.is_file() {
            fs::copy(&source, &target).map_err(to_string)?;
        }
    }
    Ok(())
}

fn promote_engine_html(destination: &Path) -> Result<(), String> {
    let engine_html = destination.join("game_engine.html");
    let index_html = destination.join("index.html");
    if engine_html.exists() {
        fs::rename(&engine_html, &index_html).map_err(to_string)?;
    }
    if !index_html.exists() {
        return Err(format!(
            "WASM web build did not produce index.html or game_engine.html in {}",
            destination.display()
        ));
    }
    Ok(())
}

fn engine_binary_name() -> &'static str {
    if cfg!(windows) {
        "game_engine.exe"
    } else {
        "game_engine"
    }
}

fn to_string(error: impl std::fmt::Display) -> String {
    error.to_string()
}

fn lock_error<T>(_: std::sync::PoisonError<T>) -> String {
    "preview process state lock was poisoned".to_string()
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(PreviewState::default())
        .invoke_handler(tauri::generate_handler![
            open_project_folder,
            save_project_folder,
            start_preview,
            stop_preview,
            export_web_bundle
        ])
        .run(tauri::generate_context!())
        .expect("error while running");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn promotes_engine_html_to_index() {
        let temp = tempfile::tempdir().unwrap();
        fs::write(temp.path().join("game_engine.html"), "<html>wasm</html>").unwrap();

        promote_engine_html(temp.path()).unwrap();

        let html = fs::read_to_string(temp.path().join("index.html")).unwrap();
        assert!(html.contains("wasm"));
        assert!(!temp.path().join("game_engine.html").exists());
    }

    #[test]
    fn safe_relative_path_rejects_parent_traversal() {
        assert!(safe_relative_path("../game.json").is_err());
        assert_eq!(
            safe_relative_path("./assets\\scenes/start.json").unwrap(),
            PathBuf::from("assets").join("scenes").join("start.json")
        );
    }
}
