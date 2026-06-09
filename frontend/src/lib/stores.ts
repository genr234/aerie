import { writable, derived } from "svelte/store";
import type { 
  Vfs, 
  ProjectConfig, 
  Selection, 
  Diagnostic,
  SceneDocument,
  SceneEntity
} from './types';
import type { PreviewLog } from './previewRuntime';

export type MainTab = "scene" | "script" | "dialogue" | "combat" | "settings" | "raw" | "asset";
export type BottomTab = "diagnostics" | "output" | "problems";
export type AppScreen = "projects" | "editor";

export type DragState = {
  scenePath: string;
  entityIndex: number;
  startX: number;
  startY: number;
  original: [number, number];
};

export type RuntimeProblem = {
  severity: "error" | "warning" | "info";
  source: string;
  message: string;
  raw: string;
};

// Core State
export const vfs = writable<Vfs>(new Map());
export const dirty = writable<Set<string>>(new Set());
export const undoStack = writable<Vfs[]>([]);
export const redoStack = writable<Vfs[]>([]);
export const projectRoot = writable<string>("");
export const project = writable<ProjectConfig | undefined>(undefined);

// UI State
export const currentScreen = writable<AppScreen>("projects");
export const selection = writable<Selection>({ type: "file", path: "game.json" });
export const selectedPath = writable<string>("game.json");
export const rawText = writable<string>("");
export const activeMainTab = writable<MainTab>("scene");
export const activeBottomTab = writable<BottomTab>("diagnostics");
export const status = writable<string>("Create a project or open a folder to begin.");
export const previewRunning = writable<boolean>(false);
export const showGrid = writable<boolean>(true);
export const panelCollapsed = writable<boolean>(false);
export const inspectorCollapsed = writable<boolean>(false);
export const dragState = writable<DragState | undefined>(undefined);

// Modal/Form State
export const newProjectTitle = writable<string>("Untitled Game");
export const newProjectId = writable<string>("untitled-game");
export const newProjectTemplate = writable<string>("exploration");

export const showCreateScene = writable<boolean>(false);
export const newSceneName = writable<string>("new_scene");

export const showCreateScript = writable<boolean>(false);
export const newScriptName = writable<string>("new_module");

export const showCreateDialogue = writable<boolean>(false);
export const newDialogueName = writable<string>("new_dialogue");

export const assetRenameName = writable<string>("");

// Diagnostics and Output
export const diagnostics = writable<Diagnostic[]>([]);
export const runtimeDiagnostics = writable<Diagnostic[]>([]);
export const output = writable<PreviewLog[]>([]);
export const runtimeProblems = writable<RuntimeProblem[]>([]);

// Derived State
export const paths = derived(vfs, $vfs => Array.from($vfs.keys()).sort());
export const sceneDecls = derived(project, $project => $project?.scenes ?? []);
export const scriptDecls = derived(project, $project => $project?.scripts ?? []);
export const dialogueDecls = derived(project, $project => $project?.dialogues ?? []);
export const combatDecl = derived(project, $project => $project?.combat);

export const canUndo = derived(undoStack, $stack => $stack.length > 0);
export const canRedo = derived(redoStack, $stack => $stack.length > 0);
