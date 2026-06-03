import { describe, expect, it } from "vitest";
import { parseProject, validateAll } from "./project";
import { writeText } from "./vfs";
import type { Vfs } from "./types";

describe("project validation", () => {
  it("parses a minimal valid project", () => {
    let vfs: Vfs = new Map();
    vfs = writeText(vfs, "game.json", JSON.stringify({
      id: "demo",
      title: "Demo",
      start_scene: "start",
      scenes: [{ name: "start", path: "assets/scenes/start.json" }],
      scripts: [{ name: "main", path: "assets/scripts/main.wren" }],
      entry: { module: "main", class: "Game" },
    }));
    vfs = writeText(vfs, "assets/scenes/start.json", JSON.stringify({
      name: "start",
      entities: [
        { tag: "player", components: { Transform: { position: [0, 0] }, PlayerController: { speed: 100 } } },
        { tag: "camera", components: { Camera: { offset: [400, 225] } } },
      ],
    }));
    vfs = writeText(vfs, "assets/scripts/main.wren", "class Game {}\n");

    expect(parseProject(vfs).project?.id).toBe("demo");
    expect(validateAll(vfs).filter((diagnostic) => diagnostic.severity === "error")).toEqual([]);
  });
});
