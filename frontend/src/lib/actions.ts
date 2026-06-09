import { get } from 'svelte/store';
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import {
  vfs, projectRoot, project, dirty, status, undoStack, redoStack,
  diagnostics, runtimeDiagnostics, activeBottomTab, activeMainTab,
  selection, selectedPath, rawText, assetRenameName, output, previewRunning,
  runtimeProblems,
  newProjectTitle, newProjectId,
  newProjectTemplate,
  showCreateScene, showCreateScript, showCreateDialogue,
  newSceneName, newScriptName, newDialogueName, currentScreen
} from './stores';
import {
  openProjectFolder, saveProjectFolder, exportWebBundle, startPreview, stopPreview
} from './previewRuntime';
import {
  vfsFromZip, downloadZip, fileFromBytes, readText, writeText
} from './vfs';
import {
  parseProject, validateAll, fatalDiagnostics, parseScene, parseDialogue,
  writeScene, writeDialogue, parseCombat, writeCombat
} from './project';
import { defaultComponent } from './componentRegistry';
import { moveEntityPositions, nextSelectionAfterDelete, selectedEntities, setEntityEditorPosition, snapPoint, type EntityPreset } from './sceneEditor';
import {
  deleteDialogueNodeAndClearLinks,
  duplicateDialogueNode as duplicateDialogueNodeInDocument,
  renameDialogueNodeId,
  setDialogueAutoLayout,
  setDialogueNodePosition,
  uniqueDialogueId,
} from './dialogueGraph';
import type { MainTab } from './stores';
import type { CombatDocument, DialogueChoice, DialogueNode, DialogueNodePosition, ProjectConfig, SceneDocument, SceneEntity, Selection, Vfs } from './types';

type OpenLoadedProjectOptions = {
  dirtyPaths?: Iterable<string>;
  root?: string;
  statusMessage: string;
};

type SelectOptions = {
  autosave?: boolean;
};

export function refreshProject() {
  const currentVfs = get(vfs);
  const parsed = parseProject(currentVfs);
  project.set(parsed.project);
  diagnostics.set([...validateAll(currentVfs), ...get(runtimeDiagnostics)]);
}

export function markDirty(path: string) {
  dirty.update(d => new Set(d).add(path));
}

export function selectFile(
  path: string,
  tab?: MainTab,
  options: SelectOptions = {}
) {
  if (options.autosave ?? true) flushActiveEditorBuffer();
  const currentTab = get(activeMainTab);
  const finalTab = tab ?? (path.endsWith(".wren")
    ? "script"
    : path.endsWith(".json")
      ? "raw"
      : /\.(png|jpg|jpeg)$/i.test(path)
        ? "asset"
        : currentTab);
  
  selectedPath.set(path);
  selection.set({ type: "file", path });
  rawText.set(readText(get(vfs), path) ?? "");
  assetRenameName.set(path.split("/").pop() ?? path);
  activeMainTab.set(finalTab);
}

export function selectScene(path: string, options: SelectOptions = {}) {
  if (options.autosave ?? true) flushActiveEditorBuffer();
  selectedPath.set(path);
  rawText.set(readText(get(vfs), path) ?? "");
  selection.set({ type: "file", path });
  activeMainTab.set("scene");
}

export function selectCombat(path: string, options: SelectOptions = {}) {
  if (options.autosave ?? true) flushActiveEditorBuffer();
  selectedPath.set(path);
  rawText.set(readText(get(vfs), path) ?? "");
  selection.set({ type: "file", path });
  activeMainTab.set("combat");
}

export function repairDiagnostic(diagnostic: { path: string; message: string }) {
  const message = diagnostic.message;
  let repaired = false;

  const missingTexture = message.match(/^entities\[(\d+)\]\.Sprite\.texture missing asset /);
  if (missingTexture) {
    const index = Number(missingTexture[1]);
    mutateScene(diagnostic.path, (scene) => {
      const sprite = scene.entities[index]?.components.Sprite as Record<string, unknown> | undefined;
      if (sprite) delete sprite.texture;
      repaired = true;
    });
  }

  const missingFollow = message.match(/^entities\[(\d+)\]\.Camera\.followTag targets missing tag /);
  if (missingFollow) {
    const index = Number(missingFollow[1]);
    mutateScene(diagnostic.path, (scene) => {
      const camera = scene.entities[index]?.components.Camera as Record<string, unknown> | undefined;
      if (camera) delete camera.followTag;
      repaired = true;
    });
  }

  const missingScene = message.match(/^entities\[(\d+)\]\.Trigger targets missing scene /);
  if (missingScene) {
    const index = Number(missingScene[1]);
    mutateScene(diagnostic.path, (scene) => {
      const trigger = scene.entities[index]?.components.Trigger as Record<string, unknown> | undefined;
      if (trigger) delete trigger.action;
      repaired = true;
    });
  }

  const missingSkill = message.match(/^actors\[(\d+)\] references missing skill '([^']+)'/);
  if (missingSkill) {
    const index = Number(missingSkill[1]);
    const skillId = missingSkill[2];
    mutateCombat((combat) => {
      combat.actors[index].skills = (combat.actors[index].skills ?? []).filter((id) => id !== skillId);
      repaired = true;
    });
  }

  const missingActor = message.match(/^encounters\[(\d+)\] references missing actor '([^']+)'/);
  if (missingActor) {
    const index = Number(missingActor[1]);
    const actorId = missingActor[2];
    mutateCombat((combat) => {
      combat.encounters[index].party = combat.encounters[index].party.filter((id) => id !== actorId);
      combat.encounters[index].enemies = combat.encounters[index].enemies.filter((id) => id !== actorId);
      repaired = true;
    });
  }

  if (message === "Scene has no entity tagged 'player'") {
    mutateScene(diagnostic.path, (scene) => {
      scene.entities = [...(scene.entities ?? []), {
        tag: "player",
        components: {
          Transform: { position: [96, 260], scale: [1, 1], rotation: 0 },
          Rect: { width: 28, height: 38, color: "#5b7fdb" },
          Layer: { order: 20, ySort: true },
          PlayerController: { speed: 130, mode: "smooth8" },
          BoxCollider: { width: 22, height: 24, offset: [3, 12] },
        },
      }];
      repaired = true;
    });
  }

  if (message === "Scene has no Camera component") {
    mutateScene(diagnostic.path, (scene) => {
      scene.entities = [...(scene.entities ?? []), {
        tag: "main_camera",
        components: {
          Transform: { position: [0, 0] },
          Camera: { offset: [400, 225], zoom: 1, followTag: "player", clampToScene: true, smoothing: 8 },
        },
      }];
      repaired = true;
    });
  }

  if (message === "Missing combat file") {
    createCombatData(diagnostic.path);
    repaired = true;
  }

  if (/ starts dialogue but no dialogues are declared$/.test(message)) {
    createDefaultDialogue();
    repaired = true;
  }

  status.set(repaired ? "Repaired diagnostic." : "No automatic repair is available for that diagnostic.");
}

export function clearHistory() {
  undoStack.set([]);
  redoStack.set([]);
}

export function recordHistory() {
  undoStack.update(stack => [...stack.slice(-49), new Map(get(vfs))]);
  redoStack.set([]);
}

export function restoreFromHistory(next: Map<string, any>) {
  vfs.set(new Map(next));
  dirty.set(new Set(next.keys()));
  refreshProject();
  rawText.set(readText(get(vfs), get(selectedPath)) ?? "");
}

export function undo() {
  const stack = get(undoStack);
  const previous = stack[stack.length - 1];
  if (!previous) return;
  redoStack.update(r => [...r, new Map(get(vfs))]);
  undoStack.set(stack.slice(0, -1));
  restoreFromHistory(previous);
  status.set("Undid last edit.");
}

export function redo() {
  const stack = get(redoStack);
  const next = stack[stack.length - 1];
  if (!next) return;
  undoStack.update(u => [...u, new Map(get(vfs))]);
  redoStack.set(stack.slice(0, -1));
  restoreFromHistory(next);
  status.set("Redid edit.");
}

export function hasUnsavedEditorBuffer(): boolean {
  const path = get(selectedPath);
  if (!path) return false;
  const file = get(vfs).get(path);
  return file?.kind === "text" && file.text !== get(rawText);
}

export function flushActiveEditorBuffer() {
  const path = get(selectedPath);
  if (!path) return;
  const currentVfs = get(vfs);
  const file = currentVfs.get(path);
  if (file?.kind !== "text") return;
  const currentText = get(rawText);
  if (file.text === currentText) return;
  
  recordHistory();
  vfs.set(writeText(currentVfs, path, currentText));
  markDirty(path);
  refreshProject();
}

export function saveRaw() {
  flushActiveEditorBuffer();
  status.set("Saved editor buffer.");
}

export function updateScript(text: string) {
  rawText.set(text);
  flushActiveEditorBuffer();
  status.set("Saved script.");
}

export function confirmDiscardDirty(action: string): boolean {
  const bufferDirty = hasUnsavedEditorBuffer();
  const d = get(dirty);
  const path = get(selectedPath);
  if (d.size === 0 && !bufferDirty) return true;
  const count = d.size + (bufferDirty && !d.has(path) ? 1 : 0);
  return window.confirm(
    `${action}\n\n${count} file${count === 1 ? " has" : "s have"} unsaved changes. Continue and discard them?`
  );
}

export function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function uniqueAssetPath(path: string, current: Map<string, any>): string {
  if (!current.has(path)) return path;
  const dot = path.lastIndexOf(".");
  const base = dot >= 0 ? path.slice(0, dot) : path;
  const ext = dot >= 0 ? path.slice(dot) : "";
  let index = 2;
  while (current.has(`${base}-${index}${ext}`)) index += 1;
  return `${base}-${index}${ext}`;
}

export function openLoadedProject(loadedVfs: Vfs, options: OpenLoadedProjectOptions) {
  vfs.set(loadedVfs);
  dirty.set(new Set(options.dirtyPaths ?? []));
  clearHistory();
  if (options.root !== undefined) projectRoot.set(options.root);
  refreshProject();
  const p = get(project);
  const firstScene = (p?.scenes ?? [])[0]?.path;
  if (firstScene) selectScene(firstScene, { autosave: false });
  else selectFile("game.json", "raw", { autosave: false });
  currentScreen.set("editor");
  status.set(options.statusMessage);
}

export async function closeProjectToProjects() {
  if (!confirmDiscardDirty("Return to projects?")) return;
  if (get(previewRunning)) {
    try {
      await stopPreview();
    } catch {
      // The active editor state is still cleared if preview shutdown fails.
    }
  }
  vfs.set(new Map());
  dirty.set(new Set());
  clearHistory();
  project.set(undefined);
  diagnostics.set([]);
  runtimeDiagnostics.set([]);
  runtimeProblems.set([]);
  output.set([]);
  previewRunning.set(false);
  selection.set({ type: "file", path: "game.json" });
  selectedPath.set("game.json");
  rawText.set("");
  assetRenameName.set("");
  activeMainTab.set("scene");
  activeBottomTab.set("diagnostics");
  currentScreen.set("projects");
  status.set("Choose a project to open.");
}

export async function openFolder() {
  if (!confirmDiscardDirty("Open another project folder?")) return;
  const root = get(projectRoot).trim();
  if (!root) {
    status.set("Enter a project folder path first.");
    return;
  }
  try {
    const loadedVfs = await openProjectFolder(root);
    openLoadedProject(loadedVfs, {
      root,
      statusMessage: `Opened ${root}.`,
    });
  } catch (error) {
    status.set(messageOf(error));
  }
}

export async function chooseProjectFolder() {
  try {
    const selected = await openDialog({ directory: true, multiple: false });
    if (typeof selected === "string") projectRoot.set(selected);
  } catch (error) {
    status.set(messageOf(error));
  }
}

export async function saveFolder() {
  const root = get(projectRoot).trim();
  if (!root) {
    status.set("Enter a project folder path first.");
    return;
  }
  try {
    flushActiveEditorBuffer();
    const resultStatus = await saveProjectFolder(root, get(vfs));
    status.set(resultStatus);
    dirty.set(new Set());
  } catch (error) {
    status.set(messageOf(error));
  }
}

export function exportZip() {
  flushActiveEditorBuffer();
  downloadZip(get(vfs), `${get(project)?.id ?? "game-project"}-source.zip`);
  status.set("Exported source project zip.");
}

export async function exportWeb() {
  flushActiveEditorBuffer();
  const currentVfs = get(vfs);
  const fatalNow = fatalDiagnostics(validateAll(currentVfs)).length;
  if (fatalNow > 0) {
    status.set("Fix fatal diagnostics before exporting.");
    activeBottomTab.set("diagnostics");
    return;
  }
  try {
    const parent = await openDialog({
      directory: true,
      multiple: false,
      title: "Choose export destination folder",
    });
    if (typeof parent !== "string") return;
    const destination = `${parent.replace(/\/$/, "")}/${get(project)?.id ?? "game"}-web`;
    status.set("Exporting web game...");
    const resultStatus = await exportWebBundle(destination, currentVfs);
    status.set(resultStatus);
  } catch (error) {
    status.set(messageOf(error));
    activeBottomTab.set("output");
  }
}

export async function play() {
  flushActiveEditorBuffer();
  const currentVfs = get(vfs);
  const fatalNow = fatalDiagnostics(validateAll(currentVfs)).length;
  if (fatalNow > 0) {
    status.set("Fix fatal diagnostics before playing.");
    activeBottomTab.set("diagnostics");
    return;
  }
  try {
    output.set([]);
    runtimeDiagnostics.set([]);
    runtimeProblems.set([]);
    refreshProject();
    const resultStatus = await startPreview(currentVfs);
    status.set(resultStatus);
    previewRunning.set(true);
    activeBottomTab.set("output");
  } catch (error) {
    previewRunning.set(false);
    status.set(messageOf(error));
  }
}

export async function playFromCurrentScene() {
  flushActiveEditorBuffer();
  const currentVfs = get(vfs);
  const currentProject = parseProject(currentVfs).project;
  const scene = (currentProject?.scenes ?? []).find((decl) => decl.path === get(selectedPath));
  if (!currentProject || !scene) {
    status.set("Select a scene to play from.");
    activeMainTab.set("scene");
    return;
  }
  const previewProject = { ...currentProject, start_scene: scene.name };
  const previewVfs = writeText(currentVfs, "game.json", `${JSON.stringify(cleanUndefined(previewProject), null, 2)}\n`);
  const fatalNow = fatalDiagnostics(validateAll(previewVfs)).length;
  if (fatalNow > 0) {
    status.set("Fix fatal diagnostics before playing.");
    activeBottomTab.set("diagnostics");
    return;
  }
  try {
    output.set([]);
    runtimeDiagnostics.set([]);
    runtimeProblems.set([]);
    refreshProject();
    const resultStatus = await startPreview(previewVfs);
    status.set(`${resultStatus} Starting at ${scene.name}.`);
    previewRunning.set(true);
    activeBottomTab.set("output");
  } catch (error) {
    previewRunning.set(false);
    status.set(messageOf(error));
  }
}

export async function stop() {
  const resultStatus = await stopPreview();
  status.set(resultStatus);
  previewRunning.set(false);
}

export async function importZip(event: Event) {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  if (!confirmDiscardDirty(`Import ${file.name}?`)) {
    input.value = "";
    return;
  }
  try {
    const importedVfs = await vfsFromZip(file);
    openLoadedProject(importedVfs, {
      dirtyPaths: importedVfs.keys(),
      statusMessage: `Imported ${file.name}.`,
    });
  } catch (error) {
    status.set(messageOf(error));
  } finally {
    input.value = "";
  }
}

export async function importAssets(event: Event) {
  const input = event.target as HTMLInputElement;
  const files = [...(input.files ?? [])];
  if (files.length === 0) return;
  try {
    let next = get(vfs);
    const added: string[] = [];
    const sounds: Array<{ id: string; path: string }> = [];
    const music: Array<{ id: string; path: string }> = [];
    for (const file of files) {
      const isImage = /\.(png|jpg|jpeg)$/i.test(file.name);
      const isAudio = /\.(wav|ogg|mp3)$/i.test(file.name);
      if (!isImage && !isAudio) continue;
      const path = uniqueAssetPath(`${isAudio ? "assets/audio" : "assets/imports"}/${file.name}`, next);
      const bytes = new Uint8Array(await file.arrayBuffer());
      next = new Map(next).set(path, fileFromBytes(path, bytes));
      added.push(path);
      if (isAudio) {
        const id = slugify(file.name.replace(/\.[^.]+$/, "")).replaceAll("-", "_");
        const entry = { id, path: path.replace(/^assets\//, "") };
        if (/\.ogg$/i.test(file.name)) music.push(entry);
        else sounds.push(entry);
      }
    }
    if (added.length) recordHistory();
    vfs.set(next);
    if (sounds.length || music.length) {
      mutateProject((config) => {
        config.audio = {
          ...(config.audio ?? {}),
          sounds: [...(config.audio?.sounds ?? []), ...sounds],
          music: [...(config.audio?.music ?? []), ...music],
        };
      }, false);
    }
    dirty.update(d => new Set([...d, ...added]));
    refreshProject();
    status.set(added.length
      ? `Imported ${added.length} asset${added.length === 1 ? "" : "s"}.`
      : "No supported image assets selected.");
  } catch (error) {
    status.set(messageOf(error));
  } finally {
    input.value = "";
  }
}

export async function createNewProject() {
  if (!confirmDiscardDirty("Create a new project?")) return;
  const title = get(newProjectTitle).trim() || "Untitled Game";
  const id = slugify(get(newProjectId) || title);
  const template = get(newProjectTemplate);
  try {
    const importedVfs = createBlankProject(id, title, template);
    openLoadedProject(importedVfs, {
      dirtyPaths: importedVfs.keys(),
      root: "",
      statusMessage: `${title} created. Choose a folder and save when ready.`,
    });
  } catch (error) {
    status.set(messageOf(error));
  }
}

export function createBlankProject(id: string, title: string, template = "exploration"): Vfs {
  let next: Vfs = new Map();
  const scene: SceneDocument = {
    name: "start",
    type: "exploration",
    size: { width: 800, height: 450 },
    background: { color: template === "visual_novel" ? "#171923" : "#1f2933" },
    entities: [
      {
        tag: "player",
        components: {
          Transform: { position: [96, 260], scale: [1, 1], rotation: 0 },
          Rect: { width: 28, height: 38, color: "#5b7fdb" },
          Layer: { order: 20, ySort: true },
          PlayerController: { speed: 130, mode: "smooth8" },
          BoxCollider: { width: 22, height: 24, offset: [3, 12] },
        },
      },
      {
        tag: "main_camera",
        components: {
          Transform: { position: [0, 0] },
          Camera: { offset: [400, 225], zoom: 1, followTag: "player", clampToScene: true, smoothing: 8 },
        },
      },
      {
        tag: "guide",
        components: {
          Transform: { position: [320, 250], scale: [1, 1], rotation: 0 },
          Rect: { width: 34, height: 48, color: "#6c7481" },
          Layer: { order: 20, ySort: true },
          BoxCollider: { width: 28, height: 36, offset: [3, 12] },
          Solid: { enabled: true },
          Interactable: {
            bounds: [294, 226, 86, 82],
            prompt: "Talk",
            repeatable: true,
            action: { startDialogue: { id: "intro", label: "hello" } },
          },
        },
      },
      {
        tag: "ending_marker",
        components: {
          Transform: { position: [672, 246], scale: [1, 1], rotation: 0 },
          Rect: { width: 52, height: 52, color: "#79a86b" },
          Layer: { order: 5, ySort: true },
          Trigger: {
            bounds: [660, 234, 76, 76],
            oneShot: true,
            actions: [
              { showMessage: { text: "You reached the end of the tiny starter game.", duration: 3 } },
              { setFlag: { name: "ending_reached", value: true } },
            ],
          },
        },
      },
    ],
  };
  const dialogue = {
    id: "intro",
    start: "hello",
    nodes: [
      { id: "hello", speaker: "Guide", text: "Welcome. Walk to the green marker when you are ready.", next: "choice" },
      {
        id: "choice",
        speaker: "Guide",
        text: "Need anything before you go?",
        choices: [
          { text: "Mark this place", next: "marked", actions: [{ setFlag: { name: "guide_met", value: true } }] },
          { text: "I am ready", next: "bye" },
        ],
      },
      { id: "marked", speaker: "Guide", text: "Done. The world remembers you were here." },
      { id: "bye", speaker: "Guide", text: "Then go on." },
    ],
  };
  const projectConfig: ProjectConfig = {
    id,
    title,
    version: "0.1.0",
    entry: { module: "main", class: "Game" },
    start_scene: "start",
    scenes: [{ name: "start", path: "assets/scenes/start.json" }],
    scripts: [{ name: "main", path: "assets/scripts/main.wren" }],
    dialogues: [{ name: "intro", path: "assets/dialogues/intro.json" }],
    combat: template === "combat" ? { path: "assets/combat/combat.json" } : undefined,
    window: { width: 800, height: 450, title },
  };

  next = writeText(next, "game.json", `${JSON.stringify(projectConfig, null, 2)}\n`);
  next = writeText(next, "assets/scenes/start.json", writeScene(scene));
  next = writeText(next, "assets/dialogues/intro.json", writeDialogue(dialogue));
  if (template === "combat") {
    next = writeText(next, "assets/combat/combat.json", writeCombat({
      actors: [
        { id: "hero", name: "Hero", side: "party", level: 1, hp: 20, mp: 4, attack: 5, defense: 2, speed: 6, skills: ["strike"] },
        { id: "slime", name: "Slime", side: "enemy", level: 1, hp: 10, mp: 0, attack: 3, defense: 1, speed: 3, skills: [] },
      ],
      skills: [
        { id: "strike", name: "Strike", kind: "damage", power: 4, mpCost: 0, target: "enemy" },
      ],
      encounters: [
        { id: "first_battle", party: ["hero"], enemies: ["slime"], rewards: { xp: 5, gold: 1 } },
      ],
    }));
  }
  next = writeText(next, "assets/scripts/main.wren", "import \"engine/api\" for Events\n\nclass Game {\n  static onBoot() {\n    Events.message(\"Welcome to your new game.\", 2)\n  }\n\n  static onUpdate(dt) {}\n}\n");
  return next;
}

export function openScriptTab() {
  const path = get(selectedPath);
  if (path.endsWith(".wren")) {
    activeMainTab.set("script");
    return;
  }
  const scriptDecls = get(project)?.scripts ?? [];
  const script = scriptDecls[0];
  if (script) selectFile(script.path, "script");
  else activeMainTab.set("script");
}

export function updateSceneField(path: string, field: string, value: any) {
  mutateScene(path, (scene) => {
    (scene as Record<string, unknown>)[field] = value;
  });
}

export type SceneAlignMode = "left" | "right" | "top" | "bottom" | "centerX" | "centerY" | "distributeX" | "distributeY";

export function addEntityPreset(path: string, preset: EntityPreset) {
  const parsed = parseScene(get(vfs), path).scene;
  if (!parsed) return;
  const center: [number, number] = [
    Math.round((parsed.size?.width ?? 800) / 2 - 24),
    Math.round((parsed.size?.height ?? 450) / 2 - 24),
  ];
  if (addSpecialPreset(path, preset, center)) return;
  let createdIndex = -1;
  mutateScene(path, (scene) => {
    const used = new Set((scene.entities ?? []).map((entity) => entity.tag).filter(Boolean) as string[]);
    const entity = presetEntity(preset, center, used);
    scene.entities = [...(scene.entities ?? []), entity];
    createdIndex = scene.entities.length - 1;
  });
  if (createdIndex >= 0) {
    selectedEntities.set({ scenePath: path, indices: [createdIndex] });
    selection.set({ type: "entity", scenePath: path, entityIndex: createdIndex });
  }
}

export function addEntityAt(path: string, position: [number, number]) {
  const parsed = parseScene(get(vfs), path).scene;
  if (!parsed) return;
  const used = new Set((parsed.entities ?? []).map((entity) => entity.tag).filter(Boolean) as string[]);
  let createdIndex = -1;
  mutateScene(path, (scene) => {
    scene.entities = [...(scene.entities ?? []), {
      tag: uniqueId("entity", used),
      components: {
        Transform: { position, scale: [1, 1], rotation: 0 },
        Rect: { width: 64, height: 48, color: "#5b7fdb" },
      },
    }];
    createdIndex = scene.entities.length - 1;
  });
  if (createdIndex >= 0) {
    selectedEntities.set({ scenePath: path, indices: [createdIndex] });
    selection.set({ type: "entity", scenePath: path, entityIndex: createdIndex });
  }
}

export function addEntityPresetAt(path: string, preset: EntityPreset, position: [number, number]) {
  const parsed = parseScene(get(vfs), path).scene;
  if (!parsed) return;
  if (addSpecialPreset(path, preset, position)) return;
  const used = new Set((parsed.entities ?? []).map((entity) => entity.tag).filter(Boolean) as string[]);
  let createdIndex = -1;
  mutateScene(path, (scene) => {
    const entity = presetEntity(preset, position, used);
    if (preset === "camera") {
      (entity.components.Transform as Record<string, unknown>).position = position;
    }
    scene.entities = [...(scene.entities ?? []), entity];
    createdIndex = scene.entities.length - 1;
  });
  if (createdIndex >= 0) {
    selectedEntities.set({ scenePath: path, indices: [createdIndex] });
    selection.set({ type: "entity", scenePath: path, entityIndex: createdIndex });
  }
}

export function updateProjectField(field: keyof ProjectConfig, value: unknown) {
  mutateProject((config) => {
    (config as Record<string, unknown>)[field] = value;
  });
}

export function updateWindowField(field: string, value: unknown) {
  mutateProject((config) => {
    config.window = { ...(config.window ?? {}), [field]: numericWindowField(field, value) };
  });
}

export function moveSelectedEntity(dir: number) {
  const current = get(selection);
  if (current.type === "file") return;
  mutateScene(current.scenePath, (scene) => {
    const from = current.entityIndex;
    const to = Math.max(0, Math.min(scene.entities.length - 1, from + dir));
    if (from === to) return;
    const [entity] = scene.entities.splice(from, 1);
    scene.entities.splice(to, 0, entity);
    selection.set(current.type === "component"
      ? { type: "component", scenePath: current.scenePath, entityIndex: to, component: current.component }
      : { type: "entity", scenePath: current.scenePath, entityIndex: to });
  });
}

export function duplicateEntity() {
  const current = get(selection);
  if (current.type === "file") return;
  mutateScene(current.scenePath, (scene) => {
    const clone = structuredClone(scene.entities[current.entityIndex]);
    scene.entities.splice(current.entityIndex + 1, 0, clone);
    selection.set({ type: "entity", scenePath: current.scenePath, entityIndex: current.entityIndex + 1 });
  });
}

export function deleteEntity() {
  const current = get(selection);
  if (current.type === "file") return;
  mutateScene(current.scenePath, (scene) => {
    scene.entities.splice(current.entityIndex, 1);
    selection.set({ type: "file", path: current.scenePath });
  });
}

export function deleteEntities(path: string, indices: number[]) {
  const selected = Array.from(new Set(indices)).sort((a, b) => b - a);
  if (selected.length === 0) return [];
  let nextSelection: number[] = [];
  mutateScene(path, (scene) => {
    const selectedAsc = [...selected].reverse();
    nextSelection = selectedAsc.reduce(
      (current, deleted) => nextSelectionAfterDelete(current, deleted, scene.entities.length),
      selectedAsc,
    );
    for (const index of selected) {
      scene.entities.splice(index, 1);
    }
  });
  if (nextSelection.length > 0) {
    selectedEntities.set({ scenePath: path, indices: nextSelection });
    selection.set({ type: "entity", scenePath: path, entityIndex: nextSelection[0] });
  } else {
    selectedEntities.set(undefined);
    selection.set({ type: "file", path });
  }
  return nextSelection;
}

export function duplicateEntities(path: string, indices: number[]) {
  const selected = Array.from(new Set(indices)).sort((a, b) => a - b);
  if (selected.length === 0) return [];
  let created: number[] = [];
  mutateScene(path, (scene) => {
    const clones = selected.map((index) => structuredClone(scene.entities[index])).filter(Boolean);
    scene.entities.push(...clones);
    created = clones.map((_, offset) => scene.entities.length - clones.length + offset);
  });
  if (created.length > 0) {
    selectedEntities.set({ scenePath: path, indices: created });
    selection.set({ type: "entity", scenePath: path, entityIndex: created[0] });
  }
  return created;
}

export function moveEntities(path: string, indices: number[], delta: [number, number], snapSize = 1, snap = false) {
  const selected = Array.from(new Set(indices)).sort((a, b) => a - b);
  if (selected.length === 0) return;
  mutateScene(path, (scene) => {
    moveEntityPositions(scene.entities, selected, delta, snapSize, snap);
  });
}

export function alignEntities(path: string, indices: number[], mode: SceneAlignMode) {
  const selected = Array.from(new Set(indices)).sort((a, b) => a - b);
  if (selected.length < 2) return;
  mutateScene(path, (scene) => {
    const transforms = selected
      .map((index) => ({ index, transform: scene.entities[index]?.components.Transform as Record<string, any> | undefined }))
      .filter((item) => item.transform && Array.isArray(item.transform.position));
    if (transforms.length < 2) return;
    const positions = transforms.map((item) => item.transform!.position as number[]);
    if (mode === "distributeX" || mode === "distributeY") {
      const axis = mode === "distributeX" ? 0 : 1;
      const sorted = transforms.sort((a, b) => Number(a.transform!.position[axis]) - Number(b.transform!.position[axis]));
      const first = Number(sorted[0].transform!.position[axis]);
      const last = Number(sorted[sorted.length - 1].transform!.position[axis]);
      const step = sorted.length > 1 ? (last - first) / (sorted.length - 1) : 0;
      sorted.forEach((item, offset) => {
        item.transform!.position[axis] = Math.round(first + step * offset);
      });
      return;
    }
    const target = mode === "left" ? Math.min(...positions.map((p) => Number(p[0])))
      : mode === "right" ? Math.max(...positions.map((p) => Number(p[0])))
      : mode === "top" ? Math.min(...positions.map((p) => Number(p[1])))
      : mode === "bottom" ? Math.max(...positions.map((p) => Number(p[1])))
      : mode === "centerX" ? Math.round(positions.reduce((sum, p) => sum + Number(p[0]), 0) / positions.length)
      : Math.round(positions.reduce((sum, p) => sum + Number(p[1]), 0) / positions.length);
    const axis = mode === "left" || mode === "right" || mode === "centerX" ? 0 : 1;
    for (const item of transforms) item.transform!.position[axis] = target;
  });
}

export function setEntitiesPosition(path: string, indices: number[], positions: Map<number, [number, number]>, snapSize = 1, snap = false) {
  const selected = Array.from(new Set(indices)).sort((a, b) => a - b);
  if (selected.length === 0) return;
  mutateScene(path, (scene) => {
    for (const index of selected) {
      const entity = scene.entities[index];
      const position = positions.get(index);
      if (!entity || !position) continue;
      setEntityEditorPosition(entity, snapPoint(position, snapSize, snap));
    }
  });
}

function addSpecialPreset(path: string, preset: EntityPreset, position: [number, number]): boolean {
  if (preset === "portal") {
    addPortalPair(path, position);
    return true;
  }
  if (preset === "npc") {
    addNpcWithDialogue(path, position);
    return true;
  }
  return false;
}

function addPortalPair(path: string, position: [number, number]) {
  const currentVfs = get(vfs);
  const currentProject = parseProject(currentVfs).project;
  const sceneDecls = currentProject?.scenes ?? [];
  const fromDecl = sceneDecls.find((scene) => scene.path === path);
  const toDecl = sceneDecls.find((scene) => scene.path !== path) ?? fromDecl;
  const fromScene = parseScene(currentVfs, path).scene;
  const toScene = toDecl ? parseScene(currentVfs, toDecl.path).scene : undefined;
  if (!fromDecl || !toDecl || !fromScene || !toScene) return;

  const next = new Map(currentVfs);
  const fromUsed = new Set((fromScene.entities ?? []).map((entity) => entity.tag).filter(Boolean) as string[]);
  const toUsed = new Set((toScene.entities ?? []).map((entity) => entity.tag).filter(Boolean) as string[]);
  const portalTag = uniqueId("portal", fromUsed);
  const returnPortalTag = uniqueId("return_portal", toUsed);
  const fromSpawnName = `from_${toDecl.name}`;
  const toSpawnName = `from_${fromDecl.name}`;
  const portalBounds: [number, number, number, number] = [position[0], position[1], 56, 96];
  const returnPosition: [number, number] = [48, Math.round((toScene.size?.height ?? 450) / 2 - 48)];

  fromScene.entities.push({
    tag: portalTag,
    components: {
      Transform: { position, scale: [1, 1], rotation: 0 },
      Rect: { width: 56, height: 96, color: "#315d68" },
      Layer: { order: 10, ySort: true },
      Portal: { bounds: portalBounds, scene: toDecl.name, spawn: toSpawnName },
    },
  });
  if (!fromScene.entities.some((entity) => (entity.components.SpawnPoint as any)?.name === fromSpawnName)) {
    fromScene.entities.push({
      tag: uniqueId("spawn", fromUsed),
      components: { Transform: { position: [position[0] - 64, position[1] + 40], scale: [1, 1], rotation: 0 }, SpawnPoint: { name: fromSpawnName } },
    });
  }

  if (!toScene.entities.some((entity) => (entity.components.SpawnPoint as any)?.name === toSpawnName)) {
    toScene.entities.push({
      tag: uniqueId("spawn", toUsed),
      components: { Transform: { position: [returnPosition[0] + 72, returnPosition[1] + 40], scale: [1, 1], rotation: 0 }, SpawnPoint: { name: toSpawnName } },
    });
  }
  if (toDecl.path !== path) {
    toScene.entities.push({
      tag: returnPortalTag,
      components: {
        Transform: { position: returnPosition, scale: [1, 1], rotation: 0 },
        Rect: { width: 56, height: 96, color: "#315d68" },
        Layer: { order: 10, ySort: true },
        Portal: { bounds: [returnPosition[0], returnPosition[1], 56, 96], scene: fromDecl.name, spawn: fromSpawnName },
      },
    });
  }

  recordHistory();
  next.set(path, { path, kind: "text", text: writeScene(fromScene) });
  if (toDecl.path !== path) next.set(toDecl.path, { path: toDecl.path, kind: "text", text: writeScene(toScene) });
  vfs.set(next);
  dirty.update((d) => new Set([...d, path, toDecl.path]));
  rawText.set(readText(get(vfs), path) ?? "");
  refreshProject();
  const index = fromScene.entities.findIndex((entity) => entity.tag === portalTag);
  if (index >= 0) {
    selectedEntities.set({ scenePath: path, indices: [index] });
    selection.set({ type: "entity", scenePath: path, entityIndex: index });
  }
  status.set(toDecl.path === path ? "Added portal." : `Added portal pair to ${toDecl.name}.`);
}

function addNpcWithDialogue(path: string, position: [number, number]) {
  const currentVfs = get(vfs);
  const currentProject = parseProject(currentVfs).project;
  const scene = parseScene(currentVfs, path).scene;
  if (!currentProject || !scene) return;

  const used = new Set((scene.entities ?? []).map((entity) => entity.tag).filter(Boolean) as string[]);
  const tag = uniqueId("npc", used);
  const dialogueId = tag;
  const dialoguePath = uniqueAssetPath(`assets/dialogues/${dialogueId}.json`, currentVfs);
  const dialogue = {
    id: dialogueId,
    start: "hello",
    nodes: [
      { id: "hello", speaker: "Guide", text: "This place is almost awake.", next: "choice" },
      {
        id: "choice",
        text: "What do you do?",
        choices: [
          { text: "Mark this place", next: "marked", actions: [{ setFlag: { name: `${dialogueId}_marked`, value: true } }] },
          { text: "Leave", next: "bye" },
        ],
      },
      { id: "marked", speaker: "Guide", text: "Good. Now the world can remember it." },
      { id: "bye", speaker: "Guide", text: "Then keep walking." },
    ],
  };
  scene.entities.push({
    tag,
    components: {
      Transform: { position, scale: [1, 1], rotation: 0 },
      Rect: { width: 34, height: 48, color: "#6c7481" },
      Layer: { order: 20, ySort: true },
      BoxCollider: { width: 28, height: 36, offset: [3, 12] },
      Solid: { enabled: true },
      Interactable: {
        bounds: [position[0] - 18, position[1] - 14, 70, 78],
        prompt: "Talk",
        repeatable: true,
        actions: [
          { playSound: { id: "interact", volume: 0.7 } },
          { startDialogue: { id: dialogueId, label: "hello" } },
        ],
      },
    },
  });

  const nextProject = structuredClone(currentProject);
  nextProject.dialogues = [...(nextProject.dialogues ?? []), { name: dialogueId, path: dialoguePath }];
  recordHistory();
  let next = writeText(currentVfs, path, writeScene(scene));
  next = writeText(next, dialoguePath, writeDialogue(dialogue));
  next = writeText(next, "game.json", `${JSON.stringify(cleanUndefined(nextProject), null, 2)}\n`);
  vfs.set(next);
  dirty.update((d) => new Set([...d, path, dialoguePath, "game.json"]));
  rawText.set(readText(get(vfs), path) ?? "");
  refreshProject();
  const index = scene.entities.findIndex((entity) => entity.tag === tag);
  if (index >= 0) {
    selectedEntities.set({ scenePath: path, indices: [index] });
    selection.set({ type: "entity", scenePath: path, entityIndex: index });
  }
  status.set("Added NPC and dialogue.");
}

export function updateEntityTag(tag: string) {
  mutateSelectedEntity((entity) => {
    if (tag.trim()) entity.tag = tag.trim();
    else delete entity.tag;
  });
}

export function addComponent(name: string) {
  mutateSelectedEntity((entity) => {
    entity.components[name] = defaultComponent(name);
  }, (current) => {
    selection.set({ type: "component", scenePath: current.scenePath, entityIndex: current.entityIndex, component: name });
  });
}

export function removeComponent(name?: string) {
  const current = get(selection);
  if (current.type === "file") return;
  const component = name ?? (current.type === "component" ? current.component : undefined);
  if (!component) return;
  mutateSelectedEntity((entity) => {
    delete entity.components[component];
  }, () => {
    selection.set({ type: "entity", scenePath: current.scenePath, entityIndex: current.entityIndex });
  });
}

export function updateComponent(name: string, value: Record<string, unknown>) {
  mutateSelectedEntity((entity) => {
    entity.components[name] = cleanUndefined(value);
  });
}

export function updateTriggerAction(action: Record<string, unknown>) {
  const trigger = componentValue("Trigger");
  updateComponent("Trigger", { ...trigger, action });
}

export function updateTriggerActionJson(text: string) {
  try {
    updateTriggerAction(JSON.parse(text));
  } catch (error) {
    status.set(`Invalid action JSON: ${messageOf(error)}`);
  }
}

export function updateStartDialogueLabel(label: string) {
  const action = componentValue("Trigger").action as any;
  const current = action?.startDialogue ?? {};
  updateTriggerAction({ startDialogue: cleanUndefined({ ...current, label: label || undefined }) });
}

export function updateStartDialogueId(id: string) {
  const action = componentValue("Trigger").action as any;
  const current = action?.startDialogue ?? {};
  updateTriggerAction({ startDialogue: cleanUndefined({ ...current, id: id || undefined }) });
}

export function isStartDialogueAction(action: any) {
  return Boolean(action && typeof action === "object" && action.startDialogue);
}

export function startDialogueId(action: any) {
  return String(action?.startDialogue?.id ?? "");
}

export function startDialogueLabel(action: any) {
  return String(action?.startDialogue?.label ?? "");
}

export function componentValue(component: string): Record<string, any> {
  const current = get(selection);
  if (current.type === "file") return {};
  const scene = parseScene(get(vfs), current.scenePath).scene;
  const value = scene?.entities[current.entityIndex]?.components?.[component];
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, any> : {};
}

export function typedComponent(comp: any) { return comp as any; }
export function array2(val: any, fallback: [number, number] = [0, 0]): [number, number] {
  return Array.isArray(val) && val.length >= 2 ? [Number(val[0]) || 0, Number(val[1]) || 0] : fallback;
}
export function array4(val: any, fallback: [number, number, number, number] = [0, 0, 0, 0]): [number, number, number, number] {
  return Array.isArray(val) && val.length >= 4
    ? [Number(val[0]) || 0, Number(val[1]) || 0, Number(val[2]) || 0, Number(val[3]) || 0]
    : fallback;
}
export function numberOf(val: unknown, fallback = 0) {
  const number = Number(val);
  return Number.isFinite(number) ? number : fallback;
}

export function createScene() {
  const name = slugify(get(newSceneName) || "new_scene").replaceAll("-", "_");
  const path = uniqueAssetPath(`assets/scenes/${name}.json`, get(vfs));
  const scene: SceneDocument = {
    name,
    type: "exploration",
    size: { width: 800, height: 450 },
    entities: [
      { tag: "main_camera", components: { Transform: { position: [0, 0] }, Camera: { offset: [400, 225], zoom: 1 } } },
    ],
  };
  recordHistory();
  vfs.set(writeText(get(vfs), path, writeScene(scene)));
  mutateProject((config) => {
    config.scenes = [...(config.scenes ?? []), { name, path }];
    config.start_scene ||= name;
  }, false);
  showCreateScene.set(false);
  newSceneName.set("new_scene");
  selectScene(path);
}

export function createScript() {
  const name = slugify(get(newScriptName) || "new_module").replaceAll("-", "_");
  const path = uniqueAssetPath(`assets/scripts/${name}.wren`, get(vfs));
  recordHistory();
  vfs.set(writeText(get(vfs), path, `class ${pascalCase(name)} {\n  construct new() {}\n}\n`));
  mutateProject((config) => {
    config.scripts = [...(config.scripts ?? []), { name, path }];
  }, false);
  showCreateScript.set(false);
  newScriptName.set("new_module");
  selectFile(path, "script");
}

export function createDialogue() {
  const name = slugify(get(newDialogueName) || "new_dialogue").replaceAll("-", "_");
  const path = uniqueAssetPath(`assets/dialogues/${name}.json`, get(vfs));
  recordHistory();
  const dialogue = { id: name, start: "start", nodes: [{ id: "start", speaker: "", text: "Hello." }] };
  vfs.set(writeText(get(vfs), path, writeDialogue(dialogue)));
  mutateProject((config) => {
    config.dialogues = [...(config.dialogues ?? []), { name, path }];
  }, false);
  showCreateDialogue.set(false);
  newDialogueName.set("new_dialogue");
  selectFile(path, "dialogue");
}

export function createCombatData(preferredPath?: string) {
  const path = preferredPath && !get(vfs).has(preferredPath)
    ? preferredPath
    : uniqueAssetPath("assets/combat/combat.json", get(vfs));
  const combat: CombatDocument = {
    actors: [
      { id: "hero", name: "Hero", side: "party", level: 1, hp: 20, mp: 4, attack: 5, defense: 2, speed: 6, skills: ["strike"] },
      { id: "slime", name: "Slime", side: "enemy", level: 1, hp: 10, mp: 0, attack: 3, defense: 1, speed: 3, skills: [] },
    ],
    skills: [
      { id: "strike", name: "Strike", kind: "damage", power: 4, mpCost: 0, target: "enemy" },
    ],
    encounters: [
      { id: "first_battle", party: ["hero"], enemies: ["slime"], rewards: { xp: 5, gold: 1 } },
    ],
  };

  recordHistory();
  vfs.set(writeText(get(vfs), path, writeCombat(combat)));
  mutateProject((config) => {
    config.combat = { path };
  }, false);
  markDirty(path);
  selectCombat(path);
}

function createDefaultDialogue() {
  const path = uniqueAssetPath("assets/dialogues/intro.json", get(vfs));
  const name = path.split("/").pop()?.replace(/\.json$/, "") ?? "intro";
  const dialogue = {
    id: name,
    start: "start",
    nodes: [{ id: "start", speaker: "", text: "Hello." }],
  };

  recordHistory();
  vfs.set(writeText(get(vfs), path, writeDialogue(dialogue)));
  mutateProject((config) => {
    config.dialogues = [...(config.dialogues ?? []), { name, path }];
  }, false);
  markDirty(path);
  refreshProject();
}

export function updateDialogueField(field: string, value: unknown) {
  mutateCurrentDialogue((dialogue) => {
    (dialogue as Record<string, unknown>)[field] = value;
  });
}

export function addDialogueNode() {
  let createdId = "";
  mutateCurrentDialogue((dialogue) => {
    const id = uniqueDialogueId("node", new Set(dialogue.nodes.map((node) => node.id)));
    createdId = id;
    dialogue.nodes.push({ id, text: "" });
    setDialogueNodePosition(dialogue, id, { x: 80 + dialogue.nodes.length * 24, y: 80 + dialogue.nodes.length * 24 });
  });
  return createdId;
}

export function deleteDialogueNode(index: number) {
  mutateCurrentDialogue((dialogue) => {
    deleteDialogueNodeAndClearLinks(dialogue, index);
  });
}

export function moveDialogueNode(index: number, dir: number) {
  mutateCurrentDialogue((dialogue) => {
    const to = Math.max(0, Math.min(dialogue.nodes.length - 1, index + dir));
    if (to === index) return;
    const [node] = dialogue.nodes.splice(index, 1);
    dialogue.nodes.splice(to, 0, node);
  });
}

export function updateDialogueNode(index: number, patch: Partial<DialogueNode>) {
  mutateCurrentDialogue((dialogue) => {
    if (patch.id !== undefined) {
      renameDialogueNodeId(dialogue, index, patch.id);
      const { id: _id, ...rest } = patch;
      dialogue.nodes[index] = cleanUndefined({ ...dialogue.nodes[index], ...rest }) as DialogueNode;
    } else {
      dialogue.nodes[index] = cleanUndefined({ ...dialogue.nodes[index], ...patch }) as DialogueNode;
    }
  });
}

export function addDialogueChoice(index: number) {
  mutateCurrentDialogue((dialogue) => {
    const node = dialogue.nodes[index];
    node.choices = [...(node.choices ?? []), { text: "Choice", next: "" }];
  });
}

export function updateDialogueChoice(nodeIndex: number, choiceIndex: number, patch: Partial<DialogueChoice>) {
  mutateCurrentDialogue((dialogue) => {
    const node = dialogue.nodes[nodeIndex];
    const choices = [...(node.choices ?? [])];
    choices[choiceIndex] = cleanUndefined({ ...choices[choiceIndex], ...patch }) as DialogueChoice;
    node.choices = choices;
  });
}

export function deleteDialogueChoice(nodeIndex: number, choiceIndex: number) {
  mutateCurrentDialogue((dialogue) => {
    const node = dialogue.nodes[nodeIndex];
    node.choices = (node.choices ?? []).filter((_, index) => index !== choiceIndex);
    if (node.choices.length === 0) delete node.choices;
  });
}

export function setDialogueAction(nodeIndex: number, actions: Array<Record<string, unknown>>) {
  updateDialogueNode(nodeIndex, { actions });
}

export function updateDialogueNodePosition(id: string, position: DialogueNodePosition) {
  mutateCurrentDialogue((dialogue) => {
    setDialogueNodePosition(dialogue, id, position);
  });
}

export function autoLayoutCurrentDialogue() {
  mutateCurrentDialogue((dialogue) => {
    setDialogueAutoLayout(dialogue);
  });
}

export function duplicateDialogueNode(index: number) {
  let createdId: string | undefined;
  mutateCurrentDialogue((dialogue) => {
    createdId = duplicateDialogueNodeInDocument(dialogue, index);
  });
  return createdId;
}

export function setDialogueStartNode(id: string) {
  mutateCurrentDialogue((dialogue) => {
    dialogue.start = id;
  });
}

export function updateDialogueNodeNext(index: number, next: string) {
  updateDialogueNode(index, { next: next || undefined });
}

export function updateDialogueChoiceNext(nodeIndex: number, choiceIndex: number, next: string) {
  updateDialogueChoice(nodeIndex, choiceIndex, { next: next || undefined });
}

export function slugify(text: string) { return text.toLowerCase().replace(/[^a-z0-9]+/g, "-"); }

function mutateProject(mutator: (config: ProjectConfig) => void, record = true) {
  const current = get(vfs);
  const parsed = parseProject(current).project;
  if (!parsed) return;
  const nextConfig = structuredClone(parsed);
  mutator(nextConfig);
  if (record) recordHistory();
  vfs.set(writeText(get(vfs), "game.json", `${JSON.stringify(cleanUndefined(nextConfig), null, 2)}\n`));
  markDirty("game.json");
  refreshProject();
}

export function mutateScene(path: string, mutator: (scene: SceneDocument) => void) {
  const parsed = parseScene(get(vfs), path).scene;
  if (!parsed) return;
  const nextScene = structuredClone(parsed);
  mutator(nextScene);
  recordHistory();
  vfs.set(writeText(get(vfs), path, writeScene(nextScene)));
  markDirty(path);
  rawText.set(readText(get(vfs), path) ?? "");
  refreshProject();
}

type EntitySelection = Exclude<Selection, { type: "file" }>;

function mutateSelectedEntity(mutator: (entity: SceneEntity) => void, after?: (current: EntitySelection) => void) {
  const current = get(selection);
  if (current.type === "file") return;
  mutateScene(current.scenePath, (scene) => {
    const entity = scene.entities[current.entityIndex];
    if (!entity) return;
    mutator(entity);
  });
  after?.(current);
}

function mutateCurrentDialogue(mutator: (dialogue: ReturnType<typeof parseDialogue>["dialogue"] & {}) => void) {
  const path = get(selectedPath);
  const parsed = parseDialogue(get(vfs), path).dialogue;
  if (!parsed) return;
  const nextDialogue = structuredClone(parsed);
  mutator(nextDialogue);
  recordHistory();
  vfs.set(writeText(get(vfs), path, writeDialogue(nextDialogue)));
  markDirty(path);
  rawText.set(readText(get(vfs), path) ?? "");
  refreshProject();
}

export function mutateCombat(mutator: (combat: CombatDocument) => void) {
  const path = get(project)?.combat?.path;
  if (!path) return;
  const parsed = parseCombat(get(vfs), path).combat;
  if (!parsed) return;
  const next = structuredClone(parsed);
  mutator(next);
  recordHistory();
  vfs.set(writeText(get(vfs), path, writeCombat(next)));
  markDirty(path);
  rawText.set(readText(get(vfs), path) ?? "");
  refreshProject();
}

function presetEntity(preset: EntityPreset, center: [number, number], used: Set<string>): SceneEntity {
  switch (preset) {
    case "entity":
      return {
        tag: uniqueId("entity", used),
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Rect: { width: 64, height: 48, color: "#5b7fdb" },
          Layer: { order: 10, ySort: true },
        },
      };
    case "player":
      return {
        tag: uniqueId("player", used),
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Rect: { width: 32, height: 40, color: "#4aa382" },
          Layer: { order: 20, ySort: true },
          PlayerController: { speed: 120 },
          BoxCollider: { width: 18, height: 14, offset: [7, 24] },
          Solid: { enabled: true },
        },
      };
    case "wall":
      return {
        tag: uniqueId("wall", used),
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Rect: { width: 96, height: 32, color: "#4f5964" },
          Layer: { order: 10, ySort: true },
          BoxCollider: { width: 96, height: 32 },
          Solid: { enabled: true },
        },
      };
    case "trigger":
      return {
        tag: uniqueId("trigger", used),
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Trigger: {
            bounds: [center[0], center[1], 96, 64],
            oneShot: false,
            actions: [
              { playSound: { id: "interact", volume: 0.7 } },
              { showMessage: { text: "Hello", duration: 2 } },
            ],
          },
        },
      };
    case "enemy":
      return {
        tag: uniqueId("enemy", used),
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Rect: { width: 36, height: 36, color: "#b85d5d" },
          Layer: { order: 20, ySort: true },
          BoxCollider: { width: 32, height: 28, offset: [2, 8] },
          Solid: { enabled: true },
          Interactable: {
            bounds: [center[0] - 16, center[1] - 16, 68, 68],
            prompt: "Engage",
            repeatable: false,
            actions: [
              { playSound: { id: "interact", volume: 0.8 } },
              { startCombat: { encounter: "slime_duo" } },
            ],
          },
        },
      };
    case "camera":
      return {
        tag: uniqueId("camera", used),
        components: {
          Transform: { position: [0, 0], scale: [1, 1], rotation: 0 },
          Camera: { offset: [400, 225], zoom: 1 },
        },
      };
    case "locked_gate": {
      const tag = uniqueId("locked_gate", used);
      return {
        tag,
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Rect: { width: 72, height: 104, color: "#315d68" },
          Layer: { order: 10, ySort: true },
          BoxCollider: { width: 72, height: 104 },
          Solid: { enabled: true },
          Interactable: {
            bounds: [center[0] - 20, center[1] - 18, 112, 140],
            prompt: "Check gate",
            repeatable: true,
            actions: [
              { playSound: { id: "interact", volume: 0.6 } },
              { setFlag: { name: `${tag}_checked`, value: true } },
              { showMessage: { text: "The gate is locked. Something nearby may open it.", duration: 3 } },
            ],
          },
        },
      };
    }
    case "collectible": {
      const tag = uniqueId("collectible", used);
      return {
        tag,
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Circle: { radius: 12, color: "#ffd56f" },
          Layer: { order: 30, ySort: false },
          ParticleEmitter: { color: "#ffd56f", rate: 2, lifetime: 0.55, speed: 18, spread: 6.28, radius: 2 },
          Interactable: {
            bounds: [center[0] - 18, center[1] - 18, 52, 52],
            prompt: "Take",
            repeatable: false,
            actions: [
              { playSound: { id: "interact", volume: 0.8 } },
              { setFlag: { name: `${tag}_collected`, value: true } },
              { showMessage: { text: "Collected.", duration: 1.5 } },
              { setEntityActive: { tag, active: false } },
            ],
          },
        },
      };
    }
    case "ending":
      return {
        tag: uniqueId("ending", used),
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Rect: { width: 96, height: 72, color: "#f0d77a" },
          Layer: { order: 10, ySort: true },
          Trigger: {
            bounds: [center[0], center[1], 96, 72],
            oneShot: true,
            actions: [
              { playSound: { id: "portal", volume: 0.8 } },
              { setFlag: { name: "ending_reached", value: true } },
              { showMessage: { text: "Ending reached. The trail remembers you.", duration: 5 } },
            ],
          },
        },
      };
    case "portal":
    case "npc":
      return {
        tag: uniqueId("entity", used),
        components: {
          Transform: { position: center, scale: [1, 1], rotation: 0 },
          Rect: { width: 64, height: 48, color: "#5b7fdb" },
          Layer: { order: 10, ySort: true },
        },
      };
  }
}

function cleanUndefined<T>(value: T): T {
  if (Array.isArray(value)) return value.map(cleanUndefined) as T;
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined).map(([key, entry]) => [key, cleanUndefined(entry)])
  ) as T;
}

function numericWindowField(field: string, value: unknown) {
  return field === "width" || field === "height" ? Math.max(1, Number(value) || 1) : value;
}

function uniqueId(prefix: string, used: Set<string>) {
  let index = used.size + 1;
  let id = `${prefix}_${index}`;
  while (used.has(id)) {
    index += 1;
    id = `${prefix}_${index}`;
  }
  return id;
}

function pascalCase(text: string) {
  return text.split(/[^a-z0-9]/i).filter(Boolean).map((part) => part[0]?.toUpperCase() + part.slice(1)).join("") || "Module";
}
