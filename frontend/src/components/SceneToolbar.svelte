<script lang="ts">
  import { Bot, Camera, ChevronDown, DoorOpen, Flag, Gem, Grid3x3, Hand, LockKeyhole, MessageCircle, MousePointer2, Plus, Shield, Swords, Tags, Zap, BoxSelect, Crosshair } from "@lucide/svelte";
  import { activeTool, canvasZoom, gridSize, overlayVisibility, placementPreset, snapEnabled, type EntityPreset, type OverlayVisibility } from "../lib/sceneEditor";
  import { updateSceneField } from "../lib/actions";
  import type { SceneDocument } from "../lib/types";

  let { scene, scenePath }: { scene: SceneDocument; scenePath: string } = $props();
  const presets: Array<[EntityPreset, typeof Plus, string]> = [
    ["entity", Plus, "Place entity"],
    ["player", Bot, "Place player"],
    ["wall", Shield, "Place wall"],
    ["trigger", Zap, "Place trigger"],
    ["enemy", Swords, "Place enemy"],
    ["camera", Camera, "Place camera"],
    ["portal", DoorOpen, "Place portal pair"],
    ["npc", MessageCircle, "Place NPC dialogue"],
    ["locked_gate", LockKeyhole, "Place locked gate"],
    ["collectible", Gem, "Place collectible"],
    ["ending", Flag, "Place ending"],
  ];

  function place(preset: EntityPreset) {
    placementPreset.set(preset);
    activeTool.set("place");
  }

  function zoomBy(factor: number) {
    canvasZoom.update((zoom) => Math.max(0.1, Math.min(5, Math.round(zoom * factor * 100) / 100)));
  }

  function setBackground(value: string) {
    updateSceneField(scenePath, "background", { ...(scene.background ?? {}), color: value });
  }

  function toggleOverlay(name: keyof OverlayVisibility) {
    overlayVisibility.update((current) => ({ ...current, [name]: !current[name] }));
  }

  function closeMenu(event: MouseEvent) {
    const menu = (event.currentTarget as HTMLElement).closest("details");
    if (menu instanceof HTMLDetailsElement) menu.open = false;
  }
</script>

<header class="scene-local-toolbar">
  <div class="scene-title-strip">
    <strong>{scene.name}</strong>
    <span>{scene.size?.width ?? 800} x {scene.size?.height ?? 450}</span>
  </div>
  <div class="segmented">
    <button class:active={$activeTool === "select"} title="Select" onclick={() => activeTool.set("select")}><MousePointer2 size={15} /></button>
    <button class:active={$activeTool === "pan"} title="Pan" onclick={() => activeTool.set("pan")}><Hand size={15} /></button>
  </div>
  <details class="toolbar-menu">
    <summary title="Place entities">
      <Plus size={15} />
      <span>Place</span>
      <ChevronDown size={14} />
    </summary>
    <div class="toolbar-menu-panel">
    {#each presets as [preset, Icon, title]}
      <button class:active={$activeTool === "place" && $placementPreset === preset} title={title} onclick={(event) => { place(preset); closeMenu(event); }}>
        <Icon size={15} />
        <span>{title.replace("Place ", "")}</span>
      </button>
    {/each}
    </div>
  </details>
  <label class="compact-color-label" title="Background color">
    <input type="color" value={scene.background?.color ?? "#1a1d23"} onchange={(event) => setBackground(event.currentTarget.value)} />
  </label>
  <details class="toolbar-menu">
    <summary title="View options">
      <Grid3x3 size={15} />
      <span>View</span>
      <ChevronDown size={14} />
    </summary>
    <div class="toolbar-menu-panel">
    <button class:active={$snapEnabled} title="Snap to grid" onclick={() => snapEnabled.update((value) => !value)}><Crosshair size={15} /><span>Snap to grid</span></button>
    <label class="toolbar-menu-field">
      <span>Grid size</span>
    <input class="grid-size-input" type="number" min="2" max="128" value={$gridSize} onchange={(event) => gridSize.set(Math.max(2, Number(event.currentTarget.value) || 16))} />
    </label>
    <button class:active={$overlayVisibility.labels} title="Labels" onclick={() => toggleOverlay("labels")}><Tags size={15} /><span>Labels</span></button>
    <button class:active={$overlayVisibility.bounds} title="Bounds" onclick={() => toggleOverlay("bounds")}><BoxSelect size={15} /><span>Bounds</span></button>
    <button class:active={$overlayVisibility.triggers} title="Triggers" onclick={() => toggleOverlay("triggers")}><Zap size={15} /><span>Triggers</span></button>
    <button class:active={$overlayVisibility.cameras} title="Cameras" onclick={() => toggleOverlay("cameras")}><Camera size={15} /><span>Cameras</span></button>
    <button class:active={$overlayVisibility.markers} title="Markers" onclick={() => toggleOverlay("markers")}><Grid3x3 size={15} /><span>Markers</span></button>
    </div>
  </details>
  <div class="zoom-cluster">
    <button title="Zoom out" onclick={() => zoomBy(0.8)}>-</button>
    <button title="Reset zoom" onclick={() => canvasZoom.set(1)}>{Math.round($canvasZoom * 100)}%</button>
    <button title="Zoom in" onclick={() => zoomBy(1.25)}>+</button>
  </div>
</header>
