import { describe, expect, it } from "vitest";
import { parseProject, validateAll } from "./project";
import { problemFromPreviewLog } from "./runtimeDiagnostics";
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

  it("accepts new gameplay components and action sequences", () => {
    let vfs: Vfs = new Map();
    vfs = writeText(vfs, "game.json", JSON.stringify({
      id: "demo",
      title: "Demo",
      start_scene: "start",
      scenes: [
        { name: "start", path: "assets/scenes/start.json" },
        { name: "next", path: "assets/scenes/next.json" },
      ],
      scripts: [{ name: "main", path: "assets/scripts/main.wren" }],
      entry: { module: "main", class: "Game" },
    }));
    vfs = writeText(vfs, "assets/scenes/start.json", JSON.stringify({
      name: "start",
      entities: [
        {
          tag: "player",
          components: {
            Transform: { position: [0, 0] },
            Sprite: { texture: "player.png" },
            Layer: { order: 20, ySort: true },
            PlayerController: { speed: 100, mode: "grid4", stepSize: 16, stepTime: 0.12 },
            BoxCollider: { width: 12, height: 10, offset: [2, 18] },
          },
        },
        { tag: "camera", components: { Camera: { offset: [400, 225], smoothing: 12, clampToScene: true, followTag: "player" } } },
        {
          tag: "stone",
          components: {
            Interactable: {
              bounds: [8, 8, 24, 24],
              prompt: "Inspect",
              repeatable: false,
              actions: [
                { playSound: { id: "interact", volume: 0.8 } },
                { setFlag: { name: "stone_seen", value: true } },
                { showMessage: { text: "The stone is warm.", duration: 2 } },
                { setEntityActive: { tag: "stone", active: false } },
              ],
            },
          },
        },
        { tag: "exit", components: { Portal: { bounds: [760, 0, 40, 450], scene: "next", spawn: "from_start" } } },
        { tag: "ending", components: { Trigger: { bounds: [300, 200, 80, 80], oneShot: true, action: { setFlag: { name: "ending_reached", value: true } } } } },
      ],
    }));
    vfs = writeText(vfs, "assets/scenes/next.json", JSON.stringify({
      name: "next",
      entities: [
        { tag: "player", components: { Transform: { position: [24, 24] }, PlayerController: { speed: 100 } } },
        { tag: "camera", components: { Camera: { offset: [400, 225], followTag: "player" } } },
        { tag: "spawn", components: { Transform: { position: [24, 24] }, SpawnPoint: { name: "from_start" } } },
      ],
    }));
    vfs = writeText(vfs, "assets/scripts/main.wren", "class Game {}\n");
    vfs = writeText(vfs, "assets/player.png", "");

    expect(validateAll(vfs).filter((diagnostic) => diagnostic.severity === "error")).toEqual([]);
    expect(validateAll(vfs).filter((diagnostic) => diagnostic.message.includes("unknown component"))).toEqual([]);
  });

  it("validates audio declarations", () => {
    let vfs: Vfs = new Map();
    vfs = writeText(vfs, "game.json", JSON.stringify({
      id: "demo",
      title: "Demo",
      start_scene: "start",
      scenes: [{ name: "start", path: "assets/scenes/start.json" }],
      scripts: [{ name: "main", path: "assets/scripts/main.wren" }],
      entry: { module: "main", class: "Game" },
      audio: {
        sounds: [{ id: "interact", path: "audio/interact.wav" }],
        music: [{ id: "ambient", path: "audio/ambient.ogg" }],
      },
    }));
    vfs = writeText(vfs, "assets/scenes/start.json", JSON.stringify({
      name: "start",
      entities: [
        { tag: "player", components: { Transform: { position: [0, 0] }, PlayerController: { speed: 100 } } },
        { tag: "camera", components: { Camera: { offset: [400, 225] } } },
      ],
    }));
    vfs = writeText(vfs, "assets/scripts/main.wren", "class Game {}\n");
    vfs = writeText(vfs, "assets/audio/interact.wav", "");
    vfs = writeText(vfs, "assets/audio/ambient.ogg", "");

    expect(validateAll(vfs).filter((diagnostic) => diagnostic.severity === "error")).toEqual([]);
  });

  it("reports playability issues for missing audio, missing encounter, and absent ending", () => {
    let vfs: Vfs = new Map();
    vfs = writeText(vfs, "game.json", JSON.stringify({
      id: "demo",
      title: "Demo",
      start_scene: "start",
      scenes: [{ name: "start", path: "assets/scenes/start.json" }],
      scripts: [{ name: "main", path: "assets/scripts/main.wren" }],
      entry: { module: "main", class: "Game" },
      combat: { path: "assets/combat/combat.json" },
      audio: { sounds: [{ id: "interact", path: "audio/interact.wav" }] },
    }));
    vfs = writeText(vfs, "assets/scenes/start.json", JSON.stringify({
      name: "start",
      entities: [
        { tag: "player", components: { Transform: { position: [0, 0] }, PlayerController: { speed: 100 } } },
        { tag: "camera", components: { Camera: { offset: [400, 225] } } },
        {
          tag: "bad",
          components: {
            Interactable: {
              bounds: [0, 0, 48, 48],
              actions: [
                { playSound: { id: "missing_sound" } },
                { startCombat: { encounter: "missing_encounter" } },
              ],
            },
          },
        },
      ],
    }));
    vfs = writeText(vfs, "assets/scripts/main.wren", "class Game {}\n");
    vfs = writeText(vfs, "assets/audio/interact.wav", "");
    vfs = writeText(vfs, "assets/combat/combat.json", JSON.stringify({
      actors: [
        { id: "hero", name: "Hero", side: "party", hp: 10, attack: 3, defense: 1, speed: 2 },
        { id: "slime", name: "Slime", side: "enemy", hp: 6, attack: 2, defense: 1, speed: 1 },
      ],
      skills: [],
      encounters: [{ id: "slime_duo", party: ["hero"], enemies: ["slime"] }],
    }));

    const messages = validateAll(vfs).map((diagnostic) => diagnostic.message);
    expect(messages).toContain("entities[0] has PlayerController but no BoxCollider");
    expect(messages).toContain("entities[2] references undeclared audio 'missing_sound'");
    expect(messages).toContain("entities[2] starts missing encounter 'missing_encounter'");
    expect(messages).toContain("Combat encounter 'slime_duo' is not started by any scene action or script");
    expect(messages).toContain("Project has no obvious ending action; add an Ending preset or set 'ending_reached'");
  });

  it("reports invalid new gameplay component references", () => {
    let vfs: Vfs = new Map();
    vfs = writeText(vfs, "game.json", JSON.stringify({
      id: "demo",
      title: "Demo",
      start_scene: "start",
      scenes: [
        { name: "start", path: "assets/scenes/start.json" },
        { name: "next", path: "assets/scenes/next.json" },
      ],
      scripts: [{ name: "main", path: "assets/scripts/main.wren" }],
      entry: { module: "main", class: "Game" },
    }));
    vfs = writeText(vfs, "assets/scenes/start.json", JSON.stringify({
      name: "start",
      entities: [
        { tag: "player", components: { Transform: { position: [0, 0] }, PlayerController: { mode: "floaty" } } },
        { tag: "camera", components: { Camera: { offset: [400, 225], clampToScene: "yes" } } },
        { tag: "bad_portal", components: { Portal: { bounds: [0, 0, 16, 16], scene: "missing", spawn: "missing_spawn" } } },
        { tag: "bad_interactable", components: { Interactable: { bounds: [0, 0, 16, 16], actions: [{ setFlag: { value: true } }] } } },
      ],
    }));
    vfs = writeText(vfs, "assets/scenes/next.json", JSON.stringify({
      name: "next",
      entities: [
        { tag: "player", components: { Transform: { position: [24, 24] }, PlayerController: { speed: 100 } } },
        { tag: "camera", components: { Camera: { offset: [400, 225], followTag: "player" } } },
      ],
    }));
    vfs = writeText(vfs, "assets/scripts/main.wren", "class Game {}\n");

    const messages = validateAll(vfs).map((diagnostic) => diagnostic.message);
    expect(messages).toContain("entities[0].PlayerController.mode must be smooth4, smooth8, or grid4");
    expect(messages).toContain("entities[1].Camera.clampToScene must be a boolean");
    expect(messages).toContain("entities[2].Portal targets missing scene 'missing'");
    expect(messages).toContain("entities[3].Interactable action has invalid shape");
  });
});

describe("runtime diagnostics", () => {
  it("turns preview stderr runtime lines into problems", () => {
    expect(problemFromPreviewLog({
      stream: "stderr",
      line: "[wren:runtime] main:12: Right operand must be a number.",
    })?.message).toContain("Right operand");
    expect(problemFromPreviewLog({
      stream: "stdout",
      line: "INFO: ok",
    })).toBeUndefined();
    expect(problemFromPreviewLog({
      stream: "stderr",
      line: "[wren->zig] showMessage 'Hello' (2.00s)",
    })).toBeUndefined();
    expect(problemFromPreviewLog({
      stream: "stderr",
      line: "INFO: DISPLAY: Device initialized successfully",
    })).toBeUndefined();
  });
});
