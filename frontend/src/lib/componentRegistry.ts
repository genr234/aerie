export type ComponentCategory = "Core" | "Rendering" | "Gameplay" | "Feel";

export type ComponentDefinition = {
  name: string;
  category: ComponentCategory;
  description: string;
  create: () => Record<string, unknown>;
};

export const COMPONENT_DEFINITIONS: ComponentDefinition[] = [
  {
    name: "Transform",
    category: "Core",
    description: "Position, rotation, and scale.",
    create: () => ({ position: [0, 0], scale: [1, 1], rotation: 0 }),
  },
  {
    name: "Sprite",
    category: "Rendering",
    description: "Draw an image or sprite sheet frame.",
    create: () => ({ texture: "reference-game/player.png" }),
  },
  {
    name: "Circle",
    category: "Rendering",
    description: "Draw a filled circle.",
    create: () => ({ radius: 16, color: "#ffffff" }),
  },
  {
    name: "Rect",
    category: "Rendering",
    description: "Draw a filled rectangle.",
    create: () => ({ width: 64, height: 48, color: "#ffffff" }),
  },
  {
    name: "Camera",
    category: "Core",
    description: "2D camera with follow, smoothing, and bounds clamp.",
    create: () => ({ offset: [400, 225], zoom: 1, smoothing: 12, clampToScene: true }),
  },
  {
    name: "PlayerController",
    category: "Gameplay",
    description: "Player movement input.",
    create: () => ({ speed: 100, mode: "smooth4" }),
  },
  {
    name: "Solid",
    category: "Gameplay",
    description: "Blocks player movement when paired with bounds.",
    create: () => ({ enabled: true }),
  },
  {
    name: "BoxCollider",
    category: "Gameplay",
    description: "Collision rectangle with optional offset.",
    create: () => ({ width: 32, height: 24, offset: [0, 0] }),
  },
  {
    name: "Interactable",
    category: "Gameplay",
    description: "Press interact near bounds to run actions.",
    create: () => ({
      bounds: [0, 0, 80, 80],
      prompt: "Interact",
      repeatable: true,
      action: { showMessage: { text: "Hello", duration: 2 } },
    }),
  },
  {
    name: "Portal",
    category: "Gameplay",
    description: "Touch bounds to change scene and optional spawn.",
    create: () => ({ bounds: [0, 0, 80, 80], scene: "", spawn: "" }),
  },
  {
    name: "SpawnPoint",
    category: "Gameplay",
    description: "Named landing point for portals.",
    create: () => ({ name: "from_scene" }),
  },
  {
    name: "Animation",
    category: "Feel",
    description: "Named sprite animation clips.",
    create: () => ({ current: "idle", clips: [{ name: "idle", start: 0, frames: 1, fps: 1, loop: true }] }),
  },
  {
    name: "Tilemap",
    category: "Rendering",
    description: "Simple color tile grid.",
    create: () => ({ columns: 8, rows: 6, tileWidth: 16, tileHeight: 16, tiles: Array(48).fill(0), solidTiles: [1], palette: ["#5f8f5f"] }),
  },
  {
    name: "ParticleEmitter",
    category: "Feel",
    description: "Ambient or burst particles.",
    create: () => ({ color: "#ffffff", rate: 0, lifetime: 0.6, speed: 40, spread: 6.28, radius: 2, burst: 12 }),
  },
  {
    name: "Tween",
    category: "Feel",
    description: "Move an entity toward a target.",
    create: () => ({ to: [128, 128], duration: 1, loop: false }),
  },
  {
    name: "Trigger",
    category: "Gameplay",
    description: "Run actions when the player enters bounds.",
    create: () => ({ bounds: [0, 0, 80, 80], oneShot: false, action: { showMessage: { text: "Hello", duration: 2 } } }),
  },
];

export const COMPONENTS = COMPONENT_DEFINITIONS.map((definition) => definition.name);

export const COMPONENT_CATEGORIES: ComponentCategory[] = ["Core", "Rendering", "Gameplay", "Feel"];

export function componentsForCategory(category: ComponentCategory): ComponentDefinition[] {
  return COMPONENT_DEFINITIONS.filter((definition) => definition.category === category);
}

export function defaultComponent(name: string): Record<string, unknown> {
  return structuredClone(COMPONENT_DEFINITIONS.find((definition) => definition.name === name)?.create() ?? {});
}
