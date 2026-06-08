import { describe, expect, it } from "vitest";
import { entityDisplay, moveEntityPositions, nextSelectionAfterDelete, snapPoint } from "./sceneEditor";
import type { SceneEntity } from "./types";

describe("scene editor helpers", () => {
  it("computes display bounds for rect, circle, sprite, and tilemap entities", () => {
    expect(entityDisplay({
      tag: "wall",
      components: { Transform: { position: [10, 20], scale: [2, 1] }, Rect: { width: 12, height: 8, color: "#123456" } },
    })).toMatchObject({ x: 10, y: 20, width: 24, height: 8, visualType: "rect", color: "#123456" });

    expect(entityDisplay({
      components: { Transform: { position: [0, 0] }, Circle: { radius: 6 } },
    })).toMatchObject({ width: 12, height: 12, visualType: "circle" });

    expect(entityDisplay({
      components: { Transform: { position: [0, 0] }, Sprite: { texture: "hero.png", frameWidth: 32, frameHeight: 48 } },
    })).toMatchObject({ width: 32, height: 48, visualType: "sprite", textureName: "hero.png" });

    expect(entityDisplay({
      components: { Transform: { position: [0, 0] }, Tilemap: { columns: 3, rows: 2, tileWidth: 16, tileHeight: 8 } },
    })).toMatchObject({ width: 48, height: 16, visualType: "tilemap" });
  });

  it("snaps points to a configurable grid", () => {
    expect(snapPoint([23, 25], 16, true)).toEqual([16, 32]);
    expect(snapPoint([23, 25], 16, false)).toEqual([23, 25]);
  });

  it("moves batches while preserving relative offsets", () => {
    const entities: SceneEntity[] = [
      { components: { Transform: { position: [10, 10] } } },
      { components: { Transform: { position: [30, 20] } } },
      { components: { Transform: { position: [50, 50] } } },
    ];
    moveEntityPositions(entities, [0, 1], [8, 8], 1, false);
    expect((entities[0].components.Transform as any).position).toEqual([18, 18]);
    expect((entities[1].components.Transform as any).position).toEqual([38, 28]);
    expect((entities[2].components.Transform as any).position).toEqual([50, 50]);
  });

  it("uses bounds as the display box for bound-driven entities without transforms", () => {
    expect(entityDisplay({
      tag: "east_portal",
      components: { Portal: { bounds: [720, 180, 48, 120], scene: "clearing" } },
    })).toMatchObject({
      x: 720,
      y: 180,
      width: 48,
      height: 120,
      actionBoundsKind: "Portal",
    });
  });

  it("moves bounds instead of adding transform for bound-driven entities", () => {
    const entities: SceneEntity[] = [
      { components: { Portal: { bounds: [10, 20, 80, 90], scene: "next" } } },
    ];
    moveEntityPositions(entities, [0], [5, 6], 1, false);
    expect((entities[0].components.Portal as any).bounds).toEqual([15, 26, 80, 90]);
    expect(entities[0].components.Transform).toBeUndefined();
  });

  it("adjusts selection indices after deletion", () => {
    expect(nextSelectionAfterDelete([1, 3], 1, 5)).toEqual([2]);
    expect(nextSelectionAfterDelete([2], 2, 4)).toEqual([2]);
    expect(nextSelectionAfterDelete([0], 0, 1)).toEqual([]);
  });
});
