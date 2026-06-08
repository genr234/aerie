import { derived, writable } from "svelte/store";
import type { SceneDocument, SceneEntity } from "./types";

export type SceneEditorTool = "select" | "pan" | "place";
export type EntityPreset = "entity" | "player" | "wall" | "trigger" | "enemy" | "camera" | "portal" | "npc" | "locked_gate" | "collectible" | "ending";

export type OverlayVisibility = {
  labels: boolean;
  bounds: boolean;
  triggers: boolean;
  cameras: boolean;
  markers: boolean;
};

export type SceneEditorSelection = {
  scenePath: string;
  indices: number[];
};

export type EntityDisplay = {
  x: number;
  y: number;
  width: number;
  height: number;
  color: string;
  visualType: "empty" | "rect" | "circle" | "sprite" | "tilemap";
  tag?: string;
  textureName: string;
  componentNames: string[];
  hasPlayer: boolean;
  hasSolid: boolean;
  hasCamera: boolean;
  hasTrigger: boolean;
  hasPortal: boolean;
  hasSpawn: boolean;
  actionBounds?: [number, number, number, number];
  actionBoundsKind?: "Trigger" | "Interactable" | "Portal";
  triggerBounds?: [number, number, number, number];
  colliderBounds?: [number, number, number, number];
  cameraOffset?: [number, number];
};

export const selectedEntities = writable<SceneEditorSelection | undefined>(undefined);
export const activeTool = writable<SceneEditorTool>("select");
export const placementPreset = writable<EntityPreset>("entity");
export const snapEnabled = writable(true);
export const gridSize = writable(16);
export const canvasZoom = writable(1);
export const overlayVisibility = writable<OverlayVisibility>({
  labels: true,
  bounds: true,
  triggers: true,
  cameras: true,
  markers: true,
});
export const lockedEntities = writable<Record<string, number[]>>({});
export const hiddenEntities = writable<Record<string, number[]>>({});
export const viewportPan = writable<Record<string, { x: number; y: number }>>({});

export const selectedEntitySet = derived(selectedEntities, ($selected) => {
  return new Set($selected?.indices ?? []);
});

export function normalizeSelection(scenePath: string, indices: number[], entityCount: number): SceneEditorSelection | undefined {
  const unique = Array.from(new Set(indices))
    .filter((index) => Number.isInteger(index) && index >= 0 && index < entityCount)
    .sort((a, b) => a - b);
  return unique.length > 0 ? { scenePath, indices: unique } : undefined;
}

export function nextSelectionAfterDelete(selected: number[], deleted: number, entityCountBefore: number): number[] {
  const remaining = selected
    .filter((index) => index !== deleted)
    .map((index) => (index > deleted ? index - 1 : index));
  if (remaining.length > 0) return Array.from(new Set(remaining)).sort((a, b) => a - b);
  const nextCount = Math.max(0, entityCountBefore - 1);
  if (nextCount === 0) return [];
  return [Math.min(deleted, nextCount - 1)];
}

export function snapValue(value: number, size: number, enabled = true): number {
  if (!enabled || size <= 1) return Math.round(value);
  return Math.round(value / size) * size;
}

export function snapPoint(point: [number, number], size: number, enabled = true): [number, number] {
  return [snapValue(point[0], size, enabled), snapValue(point[1], size, enabled)];
}

export function moveEntityPositions(
  entities: SceneEntity[],
  indices: number[],
  delta: [number, number],
  snapSize = 1,
  snap = false,
) {
  for (const index of indices) {
    const entity = entities[index];
    if (!entity) continue;
    const display = entityDisplay(entity);
    setEntityEditorPosition(entity, snapPoint([display.x + delta[0], display.y + delta[1]], snapSize, snap));
  }
}

export function setEntityEditorPosition(entity: SceneEntity, position: [number, number]) {
  if (entity.components?.Transform !== undefined) {
    const transform = ensureTransform(entity);
    transform.position = position;
    return;
  }

  for (const componentName of ["Trigger", "Interactable", "Portal"]) {
    const component = objectOf(entity.components?.[componentName]);
    const bounds = tuple4(component.bounds);
    if (!bounds) continue;
    component.bounds = [position[0], position[1], bounds[2], bounds[3]];
    entity.components[componentName] = component;
    return;
  }

  const transform = ensureTransform(entity);
  transform.position = position;
}

export function entityDisplay(entity: SceneEntity): EntityDisplay {
  const transform = objectOf(entity.components?.Transform);
  const hasTransform = entity.components?.Transform !== undefined;
  let position = array2(transform.position, [0, 0]);
  const scale = array2(transform.scale, [1, 1]);
  const rect = objectOf(entity.components?.Rect);
  const circle = objectOf(entity.components?.Circle);
  const sprite = objectOf(entity.components?.Sprite);
  const tilemap = objectOf(entity.components?.Tilemap);
  const trigger = objectOf(entity.components?.Trigger);
  const interactable = objectOf(entity.components?.Interactable);
  const portal = objectOf(entity.components?.Portal);
  const collider = objectOf(entity.components?.BoxCollider);
  const camera = objectOf(entity.components?.Camera);
  const actionBounds = tuple4(trigger.bounds) ?? tuple4(interactable.bounds) ?? tuple4(portal.bounds);
  const actionBoundsKind = tuple4(trigger.bounds) ? "Trigger" : tuple4(interactable.bounds) ? "Interactable" : tuple4(portal.bounds) ? "Portal" : undefined;

  let visualType: EntityDisplay["visualType"] = "empty";
  let width = 32;
  let height = 32;
  let color = "#7f8b93";
  let textureName = "";

  if (Object.keys(tilemap).length > 0) {
    visualType = "tilemap";
    width = numberOf(tilemap.columns, 1) * numberOf(tilemap.tileWidth, 16);
    height = numberOf(tilemap.rows, 1) * numberOf(tilemap.tileHeight, 16);
    color = String((tilemap.palette as string[] | undefined)?.[0] ?? "#5f8f5f");
  } else if (Object.keys(rect).length > 0) {
    visualType = "rect";
    width = numberOf(rect.width, 64);
    height = numberOf(rect.height, 48);
    color = String(rect.color ?? "#ffffff");
  } else if (Object.keys(circle).length > 0) {
    visualType = "circle";
    const radius = numberOf(circle.radius, 16);
    width = radius * 2;
    height = radius * 2;
    color = String(circle.color ?? "#ffffff");
  } else if (Object.keys(sprite).length > 0) {
    visualType = "sprite";
    textureName = String(sprite.texture ?? "");
    width = numberOf(sprite.frameWidth, 48) || 48;
    height = numberOf(sprite.frameHeight, 48) || 48;
  }

  if (!hasTransform && visualType === "empty" && actionBounds) {
    position = [actionBounds[0], actionBounds[1]];
    width = actionBounds[2];
    height = actionBounds[3];
  }

  return {
    x: position[0],
    y: position[1],
    width: Math.max(8, width * scale[0]),
    height: Math.max(8, height * scale[1]),
    color,
    visualType,
    tag: entity.tag,
    textureName,
    componentNames: Object.keys(entity.components ?? {}),
    hasPlayer: entity.components?.PlayerController !== undefined,
    hasSolid: entity.components?.Solid !== undefined,
    hasCamera: entity.components?.Camera !== undefined,
    hasTrigger: entity.components?.Trigger !== undefined,
    hasPortal: entity.components?.Portal !== undefined,
    hasSpawn: entity.components?.SpawnPoint !== undefined,
    actionBounds,
    actionBoundsKind,
    triggerBounds: tuple4(trigger.bounds),
    colliderBounds: tuple4(collider.width !== undefined ? [position[0] + numberOf(collider.offset?.[0], 0), position[1] + numberOf(collider.offset?.[1], 0), numberOf(collider.width, 32), numberOf(collider.height, 24)] : undefined),
    cameraOffset: tuple2(camera.offset),
  };
}

export function entityDisplays(scene: SceneDocument) {
  return scene.entities.map(entityDisplay);
}

function ensureTransform(entity: SceneEntity): Record<string, unknown> {
  if (!entity.components) entity.components = {};
  const current = objectOf(entity.components.Transform);
  entity.components.Transform = current;
  if (!Array.isArray(current.position)) current.position = [0, 0];
  if (!Array.isArray(current.scale)) current.scale = [1, 1];
  if (current.rotation === undefined) current.rotation = 0;
  return current;
}

function objectOf(value: unknown): Record<string, any> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, any> : {};
}

function array2(value: unknown, fallback: [number, number]): [number, number] {
  return Array.isArray(value) && value.length >= 2 ? [numberOf(value[0], fallback[0]), numberOf(value[1], fallback[1])] : fallback;
}

function tuple2(value: unknown): [number, number] | undefined {
  return Array.isArray(value) && value.length >= 2 ? [numberOf(value[0], 0), numberOf(value[1], 0)] : undefined;
}

function tuple4(value: unknown): [number, number, number, number] | undefined {
  return Array.isArray(value) && value.length >= 4
    ? [numberOf(value[0], 0), numberOf(value[1], 0), numberOf(value[2], 0), numberOf(value[3], 0)]
    : undefined;
}

function numberOf(value: unknown, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}
