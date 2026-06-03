import { get } from 'svelte/store';
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import {
  vfs, projectRoot, project, dirty, status, undoStack, redoStack,
  diagnostics, runtimeDiagnostics, activeBottomTab, activeMainTab,
  selection, selectedPath, rawText, assetRenameName, output, previewRunning,
  newProjectTitle, newProjectId, newProjectTemplate,
  showCreateScene, showCreateScript, showCreateDialogue,
  newSceneName, newScriptName, newDialogueName, currentScreen
} from './stores';
import {
  openProjectFolder, saveProjectFolder, exportWebBundle, startPreview, stopPreview
} from './previewRuntime';
import {
  loadReferenceProject, vfsFromZip, downloadZip, fileFromBytes, readText, writeText
} from './vfs';
import {
  parseProject, validateAll, fatalDiagnostics, parseScene, parseDialogue,
  writeScene, writeDialogue
} from './project';
import {
  deleteDialogueNodeAndClearLinks,
  duplicateDialogueNode as duplicateDialogueNodeInDocument,
  renameDialogueNodeId,
  setDialogueAutoLayout,
  setDialogueNodePosition,
  uniqueDialogueId,
} from './dialogueGraph';
import { createTemplateProject } from './templates';
import type { MainTab } from './stores';
import type { DialogueChoice, DialogueNode, DialogueNodePosition, ProjectConfig, SceneDocument, SceneEntity, Selection, Vfs } from './types';

type OpenLoadedProjectOptions = {
  dirtyPaths?: Iterable<string>;
  root?: string;
  statusMessage: string;
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
  tab?: MainTab
) {
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

export function selectScene(path: string) {
  selectedPath.set(path);
  rawText.set(readText(get(vfs), path) ?? "");
  selection.set({ type: "file", path });
  activeMainTab.set("scene");
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
  selectScene((p?.scenes ?? [])[0]?.path ?? "game.json");
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

// Commands
export async function loadSample() {
  if (!confirmDiscardDirty("Load the reference project?")) return;
  try {
    const loadedVfs = await loadReferenceProject();
    openLoadedProject(loadedVfs, {
      root: "",
      statusMessage: "Reference project loaded.",
    });
  } catch (error) {
    status.set(messageOf(error));
  }
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
    for (const file of files) {
      if (!/\.(png|jpg|jpeg)$/i.test(file.name)) continue;
      const path = uniqueAssetPath(`assets/imports/${file.name}`, next);
      const bytes = new Uint8Array(await file.arrayBuffer());
      next = new Map(next).set(path, fileFromBytes(path, bytes));
      added.push(path);
    }
    if (added.length) recordHistory();
    vfs.set(next);
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
  const title = get(newProjectTitle).trim() || "Tiny Story";
  const id = slugify(get(newProjectId) || title);
  try {
    const importedVfs = await createTemplateProject(id, title, get(newProjectTemplate));
    openLoadedProject(importedVfs, {
      dirtyPaths: importedVfs.keys(),
      root: "",
      statusMessage: `${title} created. Choose a folder and save when ready.`,
    });
  } catch (error) {
    status.set(messageOf(error));
  }
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

function defaultComponent(name: string): Record<string, unknown> {
  switch (name) {
    case "Transform": return { position: [0, 0], scale: [1, 1], rotation: 0 };
    case "Sprite": return { texture: "reference-game/player.png" };
    case "Circle": return { radius: 16, color: "#ffffff" };
    case "Rect": return { width: 64, height: 48, color: "#ffffff" };
    case "Camera": return { offset: [400, 225], zoom: 1 };
    case "PlayerController": return { speed: 100 };
    case "Solid": return { enabled: true };
    case "Animation": return { current: "idle", clips: [{ name: "idle", start: 0, frames: 1, fps: 1, loop: true }] };
    case "Tilemap": return { columns: 8, rows: 6, tileWidth: 16, tileHeight: 16, tiles: Array(48).fill(0), solidTiles: [1], palette: ["#5f8f5f"] };
    case "ParticleEmitter": return { color: "#ffffff", rate: 0, lifetime: 0.6, speed: 40, spread: 6.28, radius: 2, burst: 12 };
    case "Tween": return { to: [128, 128], duration: 1, loop: false };
    case "Trigger": return { bounds: [0, 0, 80, 80], oneShot: false, action: { showMessage: { text: "Hello", duration: 2 } } };
    default: return {};
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
