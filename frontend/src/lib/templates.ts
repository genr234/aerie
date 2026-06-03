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
    const scenes =
      template === "two-room"
        ? twoRoomScenes()
        : template === "tiny" || template === "choice"
          ? tinyStoryScenes()
          : blankScenes();
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

  export function tinyStoryScenes(): SceneDocument[] {
    return [
      {
        name: "crossroads",
        type: "exploration",
        size: { width: 800, height: 450 },
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
              Transform: { position: [96, 208] },
              Sprite: { texture: "reference-game/player.png" },
              PlayerController: { speed: 115 },
            },
          },
          {
            tag: "path",
            components: {
              Transform: { position: [0, 260] },
              Rect: { width: 800, height: 74, color: "#d9d0a3" },
            },
          },
          {
            tag: "stone",
            components: {
              Transform: { position: [548, 205] },
              Rect: { width: 70, height: 64, color: "#7a7f87" },
            },
          },
          {
            tag: "stone_glow",
            components: {
              Transform: { position: [582, 200] },
              Circle: { radius: 8, color: "#f7d96b" },
            },
          },
          {
            tag: "stone_trigger",
            components: {
              Trigger: {
                bounds: [520, 180, 130, 120],
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
              Transform: { position: [120, 220] },
              Sprite: { texture: "reference-game/player.png" },
              PlayerController: { speed: 115 },
            },
          },
          {
            tag: "grass",
            components: {
              Transform: { position: [0, 275] },
              Rect: { width: 800, height: 80, color: "#89b36d" },
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
              Transform: { position: [128, 220] },
              Sprite: { texture: "reference-game/player.png" },
              PlayerController: { speed: 115 },
            },
          },
        ],
      },
    ];
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
    Events.message("Walk to the lit stone.", 3)
  }

  static onUpdate(dt) {
    if (State.getFlag("stone_touched") && !State.getFlag("crossroads_done")) {
      State.set("crossroads_done", true)
      Events.message("The stone remembers you. The path opens.", 3)
      Scene.go("clearing")
    }
  }

  static onDraw() {
    UI.text(18, 18, "Tiny Story")
  }
}
`;
  }

  export function dialogueChoiceScript(): string {
    return `import "engine/api" for Events, State, Scene, UI, Save

class Game {
  static onBoot() {
    State.set("stone_touched", false)
    Events.message("This template includes assets/dialogues/stone_choice.json.", 4)
  }

  static onUpdate(dt) {
    if (State.getFlag("stone_touched")) {
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
    Events.message("Cross edge triggers to move between rooms. Press save from your script with Save.write(\"slot1\").", 4)
  }

  static onUpdate(dt) {}

  static onDraw() {
    var place = Scene.currentIndex() == Scene.findIndex("clearing") ? "Clearing" : "Crossroads"
    UI.text(18, 18, "Two-Room Adventure | %(place)")
  }
}
`;
  }

  export function blankScript(): string {
    return `import "engine/api" for Events, State, Scene, UI, Save

class Game {
  static onBoot() {
    Events.message("Your story starts here.", 3)
  }

  static onUpdate(dt) {}

  static onDraw() {
    UI.text(18, 18, "Start")
  }
}
`;
  }
