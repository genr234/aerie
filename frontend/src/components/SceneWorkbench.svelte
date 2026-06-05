<script lang="ts">
  import { Bot, Camera, Grid3x3, Plus, Shield, Swords, Zap, ZoomIn, ZoomOut } from "@lucide/svelte";
  import { vfs, selectedPath, selection, sceneDecls, showGrid } from "../lib/stores";
  import { parseScene } from "../lib/project";
  import { addEntityPreset, updateSceneField, type EntityPreset } from "../lib/actions";
  import SceneCanvas from "./SceneCanvas.svelte";
  import type { SceneEntity } from "../lib/types";

  let isDeclaredScene = $derived(
    $sceneDecls.some((scene) => scene.path === $selectedPath)
  );
  let selectedScene = $derived(
    isDeclaredScene
      ? parseScene($vfs, $selectedPath).scene
      : undefined
  );

  let canvasZoom = $state(1.0);

  let sceneWidth = $derived(selectedScene?.size?.width ?? 800);
  let sceneHeight = $derived(selectedScene?.size?.height ?? 450);

  function updateBackgroundColor(value: string) {
    if (!selectedScene) return;
    updateSceneField($selectedPath, "background", {
      ...(selectedScene.background ?? {}),
      color: value,
    });
  }

  function addEntity() {
    if (!selectedScene) return;
    const cx = Math.round(sceneWidth / 2 - 32);
    const cy = Math.round(sceneHeight / 2 - 24);

    const entity: SceneEntity = {
      tag: `entity_${(selectedScene.entities.length ?? 0) + 1}`,
      components: {
        Transform: { position: [cx, cy], scale: [1, 1], rotation: 0 },
        Rect: { width: 64, height: 48, color: "#5b7fdb" },
      },
    };
    updateSceneField($selectedPath, "entities", [
      ...(selectedScene.entities ?? []),
      entity,
    ]);

    selection.set({
      type: "entity",
      scenePath: $selectedPath,
      entityIndex: (selectedScene.entities?.length ?? 1) - 1,
    });
  }

  function addPreset(preset: EntityPreset) {
    addEntityPreset($selectedPath, preset);
  }

  function clampZoom(z: number): number {
    return Math.max(0.1, Math.min(5.0, Math.round(z * 100) / 100));
  }

  function zoomIn() {
    canvasZoom = clampZoom(canvasZoom * 1.25);
  }

  function zoomOut() {
    canvasZoom = clampZoom(canvasZoom / 1.25);
  }

  function fitToView() {
    canvasZoom = 1.0;
  }

  function toggleGrid() {
    showGrid.update((v) => !v);
  }
</script>

<div class="scene-workbench">
  {#if selectedScene}
    <div class="scene-toolbar">
      <div class="scene-toolbar-left">
        <strong class="scene-name">{selectedScene.name}</strong>
        <span class="scene-size">{sceneWidth} &times; {sceneHeight}</span>
      </div>

      <div class="scene-toolbar-right">
        <div class="preset-strip" aria-label="Entity presets">
          <button class="icon-button" onclick={() => addPreset("player")} title="Add player" aria-label="Add player">
            <Bot size={16} />
          </button>
          <button class="icon-button" onclick={() => addPreset("wall")} title="Add solid wall" aria-label="Add solid wall">
            <Shield size={16} />
          </button>
          <button class="icon-button" onclick={() => addPreset("trigger")} title="Add trigger" aria-label="Add trigger">
            <Zap size={16} />
          </button>
          <button class="icon-button" onclick={() => addPreset("enemy")} title="Add combat enemy" aria-label="Add combat enemy">
            <Swords size={16} />
          </button>
          <button class="icon-button" onclick={() => addPreset("camera")} title="Add camera" aria-label="Add camera">
            <Camera size={16} />
          </button>
        </div>

        <label class="compact-color-label" title="Background color">
          <input
            type="color"
            value={selectedScene.background?.color ?? "#1a1d23"}
            onchange={(e) => updateBackgroundColor(e.currentTarget.value)}
          />
        </label>

        <button
          class="icon-button"
          class:active={$showGrid}
          onclick={toggleGrid}
          title="Toggle grid"
          aria-label="Toggle grid"
        >
          <Grid3x3 size={16} />
        </button>

        <span class="zoom-separator"></span>

        <button
          class="icon-button"
          onclick={zoomOut}
          disabled={canvasZoom <= 0.1}
          title="Zoom out"
          aria-label="Zoom out"
        >
          <ZoomOut size={16} />
        </button>

        <button
          class="zoom-value"
          onclick={fitToView}
          title="Reset zoom (double-click canvas)"
          aria-label="Reset zoom"
        >
          {Math.round(canvasZoom * 100)}%
        </button>

        <button
          class="icon-button"
          onclick={zoomIn}
          disabled={canvasZoom >= 5.0}
          title="Zoom in"
          aria-label="Zoom in"
        >
          <ZoomIn size={16} />
        </button>

        <button class="tool-button primary" onclick={addEntity}>
          <Plus size={16} /> Add Entity
        </button>
      </div>
    </div>

    <SceneCanvas
      scene={selectedScene}
      scenePath={$selectedPath}
      bind:zoom={canvasZoom}
    />
  {:else}
    <div class="empty-state">
      <div>
        <p>Select a scene to edit, or create a new one.</p>
        <p class="hint">
          Use <strong>File &rarr; New Scene</strong> or click a scene in the
          sidebar.
        </p>
      </div>
    </div>
  {/if}
</div>
