import type { Vfs, ProjectConfig, SceneDocument, DialogueDocument } from './types';
import { fileFromBytes, writeText } from './vfs';
import { writeScene } from './project';

  export async function createTemplateProject(
    id: string,
    title: string,
    template: "tiny" | "choice" | "two-room" | "blank",
  ): Promise<Vfs> {
    let next: Vfs = new Map();
    const playerBytes = new Uint8Array(
      await (
        await fetch("/reference/assets/reference-game/player.png")
      ).arrayBuffer(),
    );
    next.set(
      "assets/reference-game/player.png",
      fileFromBytes("assets/reference-game/player.png", playerBytes),
    );
    for (const audioPath of ["interact.wav", "portal.wav", "ambient.ogg"]) {
      const bytes = new Uint8Array(
        await (
          await fetch(`/reference/assets/audio/${audioPath}`)
        ).arrayBuffer(),
      );
      next.set(`assets/audio/${audioPath}`, fileFromBytes(`assets/audio/${audioPath}`, bytes));
    }
    const scenes =
      template === "two-room"
        ? twoRoomScenes()
        : template === "tiny" || template === "choice"
          ? tinyStoryScenes()
          : blankScenes();
    applyRenderLayers(scenes);
    const dialogues =
      template === "choice"
        ? [choiceDialogue()]
        : template === "two-room"
          ? [twoRoomDialogue()]
          : [];
    const projectConfig: ProjectConfig = {
      id,
      title,
      version: "0.1.0",
      entry: { module: "main", class: "Game" },
      start_scene: scenes[0].name,
      scenes: scenes.map((scene) => ({
        name: scene.name,
        path: `assets/scenes/${scene.name}.json`,
      })),
      scripts: [{ name: "main", path: "assets/scripts/main.wren" }],
      dialogues: dialogues.map((dialogue) => ({
        name: dialogue.id,
        path: `assets/dialogues/${dialogue.id}.json`,
      })),
      combat: { path: "assets/combat/combat.json" },
      audio: {
        sounds: [
          { id: "interact", path: "audio/interact.wav" },
          { id: "portal", path: "audio/portal.wav" },
        ],
        music: [{ id: "ambient", path: "audio/ambient.ogg" }],
      },
      window: { width: 800, height: 450, title },
    };
    next = writeText(
      next,
      "game.json",
      `${JSON.stringify(projectConfig, null, 2)}\n`,
    );
    for (const scene of scenes)
      next = writeText(
        next,
        `assets/scenes/${scene.name}.json`,
        writeScene(scene),
      );
    for (const dialogue of dialogues)
      next = writeText(
        next,
        `assets/dialogues/${dialogue.id}.json`,
        `${JSON.stringify(dialogue, null, 2)}\n`,
      );
    next = writeText(
      next,
      "assets/combat/combat.json",
      `${JSON.stringify(defaultCombat(), null, 2)}\n`,
    );
    next = writeText(
      next,
      "assets/scripts/main.wren",
      template === "tiny"
        ? tinyStoryScript()
        : template === "choice"
          ? dialogueChoiceScript()
          : template === "two-room"
            ? twoRoomScript()
            : blankScript(),
    );
    return next;
  }

  function applyRenderLayers(scenes: SceneDocument[]): void {
    for (const scene of scenes) {
      for (const entity of scene.entities) {
        const layer = defaultLayerFor(entity);
        if (layer) entity.components.Layer = layer;
      }
    }
  }

  function defaultLayerFor(entity: SceneDocument["entities"][number]): { order: number; ySort: boolean } | undefined {
    const components = entity.components ?? {};
    if (!components.Transform) return undefined;
    if (!components.Sprite && !components.Rect && !components.Circle && !components.Tilemap && !components.ParticleEmitter) return undefined;
    const tag = entity.tag ?? "";
    if (tag.includes("camera")) return undefined;
    if (tag.includes("bank") || tag === "grass" || tag === "tree_line" || tag.includes("path") || tag === "lit_floor" || tag === "ground" || tag === "trail") return { order: -20, ySort: false };
    if (tag.includes("pool") || tag.includes("light") || tag.includes("core") || tag.includes("glow")) return { order: 30, ySort: false };
    if (tag === "player") return { order: 20, ySort: true };
    if (components.Rect || components.Sprite || components.Circle) return { order: 10, ySort: true };
    return { order: 0, ySort: false };
  }

  export function tinyStoryScenes(): SceneDocument[] {
    return [
      {
        name: "crossroads",
        type: "exploration",
        size: { width: 800, height: 450 },
        background: { color: "#182a2f" },
        entities: [
          {
            tag: "main_camera",
            components: {
              Transform: { position: [0, 0] },
              Camera: { offset: [400, 225], zoom: 1, followTag: "player" },
            },
          },
          {
            tag: "player",
            components: {
              Transform: { position: [96, 238] },
              Sprite: { texture: "reference-game/player.png" },
              PlayerController: { speed: 125 },
            },
          },
          {
            tag: "moon_pool",
            components: {
              Transform: { position: [64, 56] },
              Circle: { radius: 54, color: "#d8f1ff" },
            },
          },
          {
            tag: "north_bank",
            components: {
              Transform: { position: [0, 0] },
              Rect: { width: 800, height: 178, color: "#243f38" },
            },
          },
          {
            tag: "south_bank",
            components: {
              Transform: { position: [0, 330] },
              Rect: { width: 800, height: 120, color: "#1f3a34" },
            },
          },
          {
            tag: "path",
            components: {
              Transform: { position: [0, 252] },
              Rect: { width: 800, height: 82, color: "#b8a777" },
            },
          },
          {
            tag: "north_path",
            components: {
              Transform: { position: [344, 136] },
              Rect: { width: 98, height: 164, color: "#a99767" },
            },
          },
          {
            tag: "waystone",
            components: {
              Transform: { position: [548, 196] },
              Rect: { width: 72, height: 76, color: "#6c7481" },
            },
          },
          {
            tag: "waystone_core",
            components: {
              Transform: { position: [584, 213] },
              Circle: { radius: 16, color: "#ffe28a" },
            },
          },
          {
            tag: "gate_hint",
            components: {
              Transform: { position: [704, 184] },
              Rect: { width: 50, height: 120, color: "#315d68" },
            },
          },
          {
            tag: "stone_trigger",
            components: {
              Trigger: {
                bounds: [510, 170, 152, 132],
                oneShot: true,
                action: { setFlag: { name: "stone_touched", value: true } },
              },
            },
          },
        ],
      },
      {
        name: "clearing",
        type: "exploration",
        size: { width: 800, height: 450 },
        background: { color: "#1b3034" },
        entities: [
          {
            tag: "main_camera",
            components: {
              Transform: { position: [0, 0] },
              Camera: { offset: [400, 225], zoom: 1, followTag: "player" },
            },
          },
          {
            tag: "player",
            components: {
              Transform: { position: [124, 245] },
              Sprite: { texture: "reference-game/player.png" },
              PlayerController: { speed: 125 },
            },
          },
          {
            tag: "grass",
            components: {
              Transform: { position: [0, 256] },
              Rect: { width: 800, height: 194, color: "#5f8f5f" },
            },
          },
          {
            tag: "lit_floor",
            components: {
              Transform: { position: [248, 246] },
              Rect: { width: 330, height: 110, color: "#9ab96d" },
            },
          },
          {
            tag: "lantern_gate",
            components: {
              Transform: { position: [560, 164] },
              Rect: { width: 96, height: 132, color: "#315d68" },
            },
          },
          {
            tag: "gate_light",
            components: {
              Transform: { position: [608, 176] },
              Circle: { radius: 18, color: "#ffe28a" },
            },
          },
          {
            tag: "arrival_message",
            components: {
              Trigger: {
                bounds: [280, 220, 240, 140],
                oneShot: true,
                action: {
                  showMessage: {
                    text: "Lanterns mark the safe ground. The trail can grow from here.",
                    duration: 4,
                  },
                },
              },
            },
          },
          {
            tag: "trail_ending",
            components: {
              Transform: { position: [356, 164] },
              Rect: { width: 116, height: 48, color: "#f0d77a" },
              Trigger: {
                bounds: [340, 150, 148, 84],
                oneShot: true,
                actions: [
                  { playSound: { id: "portal", volume: 0.8 } },
                  { setFlag: { name: "ending_reached", value: true } },
                  { showMessage: { text: "The lantern trail is awake. Ending reached.", duration: 5 } },
                ],
              },
            },
          },
        ],
      },
    ];
  }

  export function blankScenes(): SceneDocument[] {
    return [
      {
        name: "start",
        type: "exploration",
        size: { width: 800, height: 450 },
        background: { color: "#1b2830" },
        entities: [
          {
            tag: "main_camera",
            components: {
              Transform: { position: [0, 0] },
              Camera: { offset: [400, 225], zoom: 1, followTag: "player" },
            },
          },
          {
            tag: "player",
            components: {
              Transform: { position: [120, 226] },
              Sprite: { texture: "reference-game/player.png" },
              PlayerController: { speed: 120 },
            },
          },
          {
            tag: "ground",
            components: {
              Transform: { position: [0, 292] },
              Rect: { width: 800, height: 158, color: "#526f57" },
            },
          },
          {
            tag: "trail",
            components: {
              Transform: { position: [0, 246] },
              Rect: { width: 800, height: 74, color: "#b5a06d" },
            },
          },
          {
            tag: "signal_post",
            components: {
              Transform: { position: [512, 178] },
              Rect: { width: 42, height: 96, color: "#5f6872" },
              Solid: { enabled: true },
            },
          },
          {
            tag: "signal_light",
            components: {
              Transform: { position: [533, 174] },
              Circle: { radius: 14, color: "#ffd56f" },
              ParticleEmitter: {
                color: "#ffd56f",
                rate: 3,
                lifetime: 0.8,
                speed: 18,
                spread: 6.28,
                radius: 2,
              },
            },
          },
          {
            tag: "combat_trigger",
            components: {
              Trigger: {
                bounds: [500, 150, 90, 130],
                oneShot: true,
                action: { startCombat: { encounter: "slime_duo" } },
              },
            },
          },
          {
            tag: "ending",
            components: {
              Transform: { position: [660, 232] },
              Rect: { width: 92, height: 54, color: "#f0d77a" },
              Trigger: {
                bounds: [640, 210, 124, 96],
                oneShot: true,
                actions: [
                  { playSound: { id: "portal", volume: 0.8 } },
                  { setFlag: { name: "ending_reached", value: true } },
                  { showMessage: { text: "Ending reached.", duration: 4 } },
                ],
              },
            },
          },
        ],
      },
    ];
  }

  export function defaultCombat() {
    return {
      actors: [
        {
          id: "hero",
          name: "Hero",
          side: "party",
          level: 1,
          hp: 28,
          mp: 8,
          attack: 7,
          defense: 2,
          speed: 7,
          skills: ["fire"],
        },
        {
          id: "slime",
          name: "Slime",
          side: "enemy",
          level: 1,
          hp: 12,
          mp: 0,
          attack: 4,
          defense: 1,
          speed: 4,
          xp: 5,
        },
      ],
      skills: [
        {
          id: "fire",
          name: "Fire",
          kind: "damage",
          power: 6,
          mpCost: 3,
          target: "enemy",
          message: "A bright flame lands.",
        },
      ],
      encounters: [
        {
          id: "slime_duo",
          party: ["hero"],
          enemies: ["slime", "slime"],
          rewards: { xp: 10, gold: 3 },
        },
      ],
    };
  }

  export function twoRoomScenes(): SceneDocument[] {
    const scenes = tinyStoryScenes();
    scenes[0].entities.push({
      tag: "door_trigger",
      components: {
        Trigger: {
          bounds: [700, 170, 80, 140],
          oneShot: false,
          action: { changeScene: { name: "clearing" } },
        },
      },
    });
    scenes[1].entities.push({
      tag: "return_trigger",
      components: {
        Trigger: {
          bounds: [20, 170, 80, 140],
          oneShot: false,
          action: { changeScene: { name: "crossroads" } },
        },
      },
    });
    return scenes;
  }

  export function choiceDialogue(): DialogueDocument {
    return {
      id: "stone_choice",
      start: "intro",
      nodes: [
        {
          id: "intro",
          speaker: "Stone",
          text: "You found the old light. What do you ask of it?",
          choices: [
            {
              text: "Open the path",
              next: "open",
              actions: [{ setFlag: { name: "stone_touched", value: true } }],
            },
            {
              text: "Leave it quiet",
              next: "quiet",
              actions: [{ setFlag: { name: "stone_touched", value: false } }],
            },
          ],
        },
        {
          id: "open",
          speaker: "Stone",
          text: "Then walk. The clearing will know you.",
          actions: [{ changeScene: { name: "clearing" } }],
        },
        {
          id: "quiet",
          speaker: "Stone",
          text: "Then remember where silence lives.",
        },
      ],
    };
  }

  export function twoRoomDialogue(): DialogueDocument {
    return {
      id: "room_hint",
      start: "hint",
      nodes: [
        {
          id: "hint",
          speaker: "Guide",
          text: "Triggers at the edges move between rooms. Save before you cross if you want to return here.",
        },
        {
          id: "saved",
          speaker: "Guide",
          text: "Your route is now marked.",
          actions: [{ setFlag: { name: "route_marked", value: true } }],
        },
      ],
    };
  }

  export function tinyStoryScript(): string {
    return `import "engine/api" for Events, State, Scene, UI, Save

class Game {
  static onBoot() {
    State.set("stone_touched", false)
    State.set("crossroads_done", false)
    Events.playMusic("ambient", 0.8)
    Events.message("Follow the amber markers to wake the waystone.", 4)
  }

  static onUpdate(dt) {
    if (State.getFlag("stone_touched") && !State.getFlag("crossroads_done")) {
      State.set("crossroads_done", true)
      Events.playSound("interact", 0.8, false)
      Events.message("The waystone hums. A lantern gate opens east.", 4)
      Events.playSound("portal", 0.7, false)
      Scene.go("clearing")
    }
  }

  static onDraw() {
    var place = Scene.currentIndex() == Scene.findIndex("clearing") ? "Clearing" : "Crossroads"
    var touched = State.getFlag("stone_touched") ? "awake" : "sleeping"
    var ending = State.getFlag("ending_reached") ? "complete" : "open trail"
    UI.text(18, 18, "%(place) | waystone: %(touched) | %(ending)")
  }
}
`;
  }

  export function dialogueChoiceScript(): string {
    return `import "engine/api" for Events, State, Scene, UI, Save

class Game {
  static onBoot() {
    State.set("stone_touched", false)
    Events.playMusic("ambient", 0.8)
    Events.message("This template includes assets/dialogues/stone_choice.json.", 4)
  }

  static onUpdate(dt) {
    if (State.getFlag("stone_touched")) {
      Events.playSound("portal", 0.7, false)
      Events.message("Choice outcome: the path opens.", 2)
      State.set("stone_touched", false)
      Scene.go("clearing")
    }
  }

  static onDraw() {
    UI.text(18, 18, "Dialogue Choice")
  }
}
`;
  }

  export function twoRoomScript(): string {
    return `import "engine/api" for Events, State, Scene, UI, Save

class Game {
  static onBoot() {
    if (Save.exists("slot1")) Save.load("slot1")
    Events.playMusic("ambient", 0.8)
    Events.message("Cross edge triggers to move between rooms. Press save from your script with Save.write(\"slot1\").", 4)
  }

  static onUpdate(dt) {}

  static onDraw() {
    var place = Scene.currentIndex() == Scene.findIndex("clearing") ? "Clearing" : "Crossroads"
    var ending = State.getFlag("ending_reached") ? "complete" : "find the ending"
    UI.text(18, 18, "Two-Room Adventure | %(place) | %(ending)")
  }
}
`;
  }

  export function blankScript(): string {
    return `import "engine/api" for Events, State, Scene, UI, Save
import "engine/api" for Inventory, Quest, Combat, Entity, CameraFx

class Game {
  static onBoot() {
    Events.playMusic("ambient", 0.8)
    Events.message("Your story starts here.", 3)
    Inventory.add("spark", 1)
    Quest.start("first_steps")
    Combat.setHp("signal", 3)
  }

  static onUpdate(dt) {
    if (Inventory.has("spark", 1) && !Quest.isComplete("first_steps")) {
      Combat.damage("signal", 1)
      Events.playSound("interact", 0.8, false)
      Entity.emitParticles("signal_light", 8)
      CameraFx.shake(3, 0.15)
      Quest.complete("first_steps")
    }
  }

  static onDraw() {
    var hp = Combat.hp("signal")
    var ending = State.getFlag("ending_reached") ? "complete" : "find the ending"
    UI.text(18, 18, "Start | signal hp: %(hp) | %(ending)")
  }
}
`;
  }
