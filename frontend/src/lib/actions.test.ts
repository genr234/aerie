import { get } from "svelte/store";
import { beforeEach, describe, expect, it } from "vitest";
import { createBlankProject, openLoadedProject } from "./actions";
import {
  activeMainTab,
  currentScreen,
  dirty,
  projectRoot,
  redoStack,
  selectedPath,
  undoStack,
  vfs,
} from "./stores";
import { readText, writeText } from "./vfs";
import type { Vfs } from "./types";

function validProjectVfs(): Vfs {
  let next: Vfs = new Map();
  next = writeText(next, "game.json", JSON.stringify({
    id: "demo",
    title: "Demo",
    start_scene: "start",
    scenes: [{ name: "start", path: "assets/scenes/start.json" }],
    scripts: [{ name: "main", path: "assets/scripts/main.wren" }],
    entry: { module: "main", class: "Game" },
  }));
  next = writeText(next, "assets/scenes/start.json", JSON.stringify({
    name: "start",
    entities: [
      { tag: "player", components: { Transform: { position: [0, 0] }, PlayerController: { speed: 100 } } },
      { tag: "camera", components: { Camera: { offset: [400, 225] } } },
    ],
  }));
  next = writeText(next, "assets/scripts/main.wren", "class Game {}\n");
  return next;
}

function projectWithoutScenesVfs(): Vfs {
  return writeText(new Map(), "game.json", JSON.stringify({
    id: "empty",
    title: "Empty",
    scenes: [],
  }));
}

beforeEach(() => {
  vfs.set(new Map());
  dirty.set(new Set(["stale.json"]));
  undoStack.set([new Map()]);
  redoStack.set([new Map()]);
  selectedPath.set("stale.json");
  activeMainTab.set("raw");
  projectRoot.set("/stale");
  currentScreen.set("projects");
});

describe("openLoadedProject", () => {
  it("opens a VFS in the editor and selects the first scene", () => {
    openLoadedProject(validProjectVfs(), {
      root: "/tmp/demo",
      statusMessage: "Opened demo.",
    });

    expect(get(currentScreen)).toBe("editor");
    expect(get(projectRoot)).toBe("/tmp/demo");
    expect(get(selectedPath)).toBe("assets/scenes/start.json");
    expect(get(activeMainTab)).toBe("scene");
    expect(get(dirty)).toEqual(new Set());
    expect(get(undoStack)).toEqual([]);
    expect(get(redoStack)).toEqual([]);
  });

  it("falls back to game.json when no scene is declared", () => {
    openLoadedProject(projectWithoutScenesVfs(), {
      statusMessage: "Opened empty.",
    });

    expect(get(currentScreen)).toBe("editor");
    expect(get(selectedPath)).toBe("game.json");
    expect(get(activeMainTab)).toBe("scene");
  });

  it("marks supplied dirty paths for imported or newly-created projects", () => {
    const loadedVfs = validProjectVfs();

    openLoadedProject(loadedVfs, {
      dirtyPaths: loadedVfs.keys(),
      statusMessage: "Imported demo.",
    });

    expect(get(dirty)).toEqual(new Set(loadedVfs.keys()));
  });
});

describe("createBlankProject", () => {
  it("creates a playable Wren entry script with runtime hook names", () => {
    const created = createBlankProject("new-game", "New Game");
    const script = readText(created, "assets/scripts/main.wren") ?? "";

    expect(script).toContain('import "engine/api" for Events');
    expect(script).toContain("static onBoot()");
    expect(script).toContain("static onUpdate(dt)");
    expect(script).not.toContain("static init()");
    expect(script).not.toContain("static update(dt)");
  });
});
