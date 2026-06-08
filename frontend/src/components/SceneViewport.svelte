<script lang="ts">
  import { selection, vfs } from "../lib/stores";
  import { addEntityAt, addEntityPresetAt, setEntitiesPosition } from "../lib/actions";
  import {
    activeTool,
    canvasZoom,
    entityDisplay,
    gridSize,
    hiddenEntities,
    lockedEntities,
    overlayVisibility,
    placementPreset,
    selectedEntities,
    selectedEntitySet,
    snapEnabled,
    snapPoint,
  } from "../lib/sceneEditor";
  import type { SceneDocument, SceneEntity } from "../lib/types";

  let { scene, scenePath }: { scene: SceneDocument; scenePath: string } = $props();
  let scrollEl = $state<HTMLDivElement>();
  let canvasEl = $state<HTMLDivElement>();
  let drag = $state<{
    pointer: number;
    start: { x: number; y: number };
    positions: Map<number, [number, number]>;
    indices: number[];
    moving: boolean;
  } | null>(null);
  let pan = $state<{ pointer: number; x: number; y: number; scrollLeft: number; scrollTop: number } | null>(null);

  const MIN_DRAG = 3;
  let sceneWidth = $derived(scene.size?.width ?? 800);
  let sceneHeight = $derived(scene.size?.height ?? 450);
  let bgColor = $derived(scene.background?.color ?? "#1a1d23");
  let hidden = $derived(new Set($hiddenEntities[scenePath] ?? []));
  let locked = $derived(new Set($lockedEntities[scenePath] ?? []));

  const textureUrlCache = new Map<string, string>();
  let lastVfs: Map<string, any> | null = null;

  function getTextureUrl(entity: SceneEntity) {
    const display = entityDisplay(entity);
    if (!display.textureName) return undefined;
    const currentVfs = $vfs;
    const candidates = [display.textureName, display.textureName.startsWith("assets/") ? display.textureName : `assets/${display.textureName}`];
    const path = candidates.find((candidate) => currentVfs.has(candidate));
    if (!path) return undefined;
    if (lastVfs !== currentVfs) {
      for (const url of textureUrlCache.values()) URL.revokeObjectURL(url);
      textureUrlCache.clear();
      lastVfs = currentVfs;
    }
    const cached = textureUrlCache.get(path);
    if (cached) return cached;
    const file = currentVfs.get(path);
    if (!file || file.kind !== "binary" || !file.bytes) return undefined;
    const mime = path.toLowerCase().endsWith(".jpg") || path.toLowerCase().endsWith(".jpeg") ? "image/jpeg" : "image/png";
    const url = URL.createObjectURL(new Blob([file.bytes as BlobPart], { type: mime }));
    textureUrlCache.set(path, url);
    return url;
  }

  function displayFor(entity: SceneEntity, index: number) {
    const display = entityDisplay(entity);
    if (drag?.moving && drag.positions.has(index)) {
      const start = drag.positions.get(index)!;
      display.x = start[0] + (drag.start ? 0 : 0);
    }
    return display;
  }

  function livePosition(index: number, display: ReturnType<typeof entityDisplay>): [number, number] {
    if (!drag?.moving || !drag.positions.has(index)) return [display.x, display.y];
    const start = drag.positions.get(index)!;
    return snapPoint([
      start[0] + (dragLiveDelta[0] ?? 0),
      start[1] + (dragLiveDelta[1] ?? 0),
    ], $gridSize, $snapEnabled);
  }

  function scenePoint(event: PointerEvent | MouseEvent): [number, number] {
    const rect = canvasEl?.getBoundingClientRect();
    if (!rect) return [0, 0];
    return [(event.clientX - rect.left) / $canvasZoom, (event.clientY - rect.top) / $canvasZoom];
  }

  function choose(index: number, event: PointerEvent) {
    const current = $selectedEntities?.scenePath === scenePath ? $selectedEntities.indices : [];
    let indices = [index];
    if (event.metaKey || event.ctrlKey) {
      indices = current.includes(index) ? current.filter((item) => item !== index) : [...current, index];
    } else if (event.shiftKey && current.length > 0) {
      const anchor = current[current.length - 1];
      const from = Math.min(anchor, index);
      const to = Math.max(anchor, index);
      indices = Array.from({ length: to - from + 1 }, (_, offset) => from + offset);
    }
    selectedEntities.set(indices.length ? { scenePath, indices } : undefined);
    selection.set({ type: "entity", scenePath, entityIndex: index });
    return indices;
  }

  function pointerDownEntity(event: PointerEvent, index: number) {
    event.preventDefault();
    event.stopPropagation();
    if ($activeTool === "place") {
      placeAtPointer(event);
      return;
    }
    if (locked.has(index)) return;
    const indices = choose(index, event).filter((item) => !locked.has(item));
    const positions = new Map<number, [number, number]>();
    for (const item of indices) {
      const display = entityDisplay(scene.entities[item]);
      positions.set(item, [display.x, display.y]);
    }
    (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
    drag = { pointer: event.pointerId, start: { x: event.clientX, y: event.clientY }, positions, indices, moving: false };
  }

  function pointerDownCanvas(event: PointerEvent) {
    if ($activeTool === "place") {
      placeAtPointer(event);
      return;
    }
    if ($activeTool === "pan" || event.button === 1 || event.altKey) {
      startPan(event);
      return;
    }
    selectedEntities.set(undefined);
    selection.set({ type: "file", path: scenePath });
  }

  function placeAtPointer(event: PointerEvent) {
    const point = snapPoint(scenePoint(event), $gridSize, $snapEnabled);
    if ($placementPreset === "entity") addEntityAt(scenePath, point);
    else addEntityPresetAt(scenePath, $placementPreset, point);
    activeTool.set("select");
  }

  function startPan(event: PointerEvent) {
    if (!scrollEl) return;
    event.preventDefault();
    (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
    pan = { pointer: event.pointerId, x: event.clientX, y: event.clientY, scrollLeft: scrollEl.scrollLeft, scrollTop: scrollEl.scrollTop };
  }

  function pointerMove(event: PointerEvent) {
    if (drag) {
      const dx = (event.clientX - drag.start.x) / $canvasZoom;
      const dy = (event.clientY - drag.start.y) / $canvasZoom;
      drag.moving ||= Math.abs(dx) >= MIN_DRAG || Math.abs(dy) >= MIN_DRAG;
      dragLiveDelta = [dx, dy];
      return;
    }
    if (pan && scrollEl) {
      scrollEl.scrollLeft = pan.scrollLeft - (event.clientX - pan.x);
      scrollEl.scrollTop = pan.scrollTop - (event.clientY - pan.y);
    }
  }

  function pointerUp(event: PointerEvent) {
    if (drag) {
      if (drag.moving) {
        const dx = (event.clientX - drag.start.x) / $canvasZoom;
        const dy = (event.clientY - drag.start.y) / $canvasZoom;
        const next = new Map<number, [number, number]>();
        for (const [index, position] of drag.positions) next.set(index, [position[0] + dx, position[1] + dy]);
        setEntitiesPosition(scenePath, drag.indices, next, $gridSize, $snapEnabled);
      }
      drag = null;
      dragLiveDelta = [0, 0];
    }
    if (pan) pan = null;
  }

  let dragLiveDelta = $state<[number, number]>([0, 0]);

  function wheel(event: WheelEvent) {
    if (event.ctrlKey || event.metaKey) {
      event.preventDefault();
      const delta = -event.deltaY * 0.002;
      canvasZoom.update((zoom) => Math.max(0.1, Math.min(5, Math.round(zoom * (1 + delta) * 100) / 100)));
    }
  }

  $effect(() => {
    return () => {
      for (const url of textureUrlCache.values()) URL.revokeObjectURL(url);
      textureUrlCache.clear();
    };
  });
</script>

<div class="scene-viewport" bind:this={scrollEl} onwheel={wheel}>
  <div class="scene-canvas-stage" style="width: {sceneWidth * $canvasZoom}px; height: {sceneHeight * $canvasZoom}px;">
    <div
      bind:this={canvasEl}
      class="scene-canvas"
      class:show-grid={$overlayVisibility.markers}
      class:panning={Boolean(pan) || $activeTool === "pan"}
      style="width: {sceneWidth}px; height: {sceneHeight}px; background-color: {bgColor}; transform: scale({$canvasZoom}); --grid-size: {$gridSize}px;"
      onpointerdown={pointerDownCanvas}
      onpointermove={pointerMove}
      onpointerup={pointerUp}
      role="application"
      aria-label="{scene.name} viewport"
    >
      {#each scene.entities as entity, index}
        {@const display = displayFor(entity, index)}
        {@const live = livePosition(index, display)}
        {@const textureUrl = getTextureUrl(entity)}
        {#if !hidden.has(index)}
          <div
            class="scene-object"
            class:selected={$selectedEntitySet.has(index)}
            class:locked={locked.has(index)}
            style="left: {live[0]}px; top: {live[1]}px; width: {display.width}px; height: {display.height}px;"
            onpointerdown={(event) => pointerDownEntity(event, index)}
            role="button"
            tabindex="0"
            aria-label={display.tag ?? `Entity ${index + 1}`}
          >
            {#if display.visualType === "rect"}
              <div class="entity-rect" style="background-color: {display.color};"></div>
            {:else if display.visualType === "tilemap"}
              <div class="entity-tilemap" style="--tile-color: {display.color};"></div>
            {:else if display.visualType === "circle"}
              <div class="entity-circle" style="background-color: {display.color};"></div>
            {:else if display.visualType === "sprite"}
              {#if textureUrl}
                <img class="entity-sprite-img" src={textureUrl} alt={display.textureName} draggable="false" />
              {:else}
                <div class="sprite-placeholder"><span class="sprite-label">{display.textureName.split("/").pop() ?? "sprite"}</span></div>
              {/if}
            {:else}
              <div class="entity-empty"><span class="empty-icon">?</span></div>
            {/if}
            {#if $overlayVisibility.labels || $selectedEntitySet.has(index)}
              <span class="entity-tag">{display.tag ?? `E${index + 1}`} {#if $selectedEntitySet.has(index)}{Math.round(display.x)}, {Math.round(display.y)}{/if}</span>
            {/if}
            {#if $overlayVisibility.cameras && display.hasCamera}
              {@const camOffset = display.cameraOffset ?? [400, 225]}
              <div class="camera-viewport" style="left: {camOffset[0] - sceneWidth / 2 - display.x}px; top: {camOffset[1] - sceneHeight / 2 - display.y}px; width: {sceneWidth}px; height: {sceneHeight}px;"></div>
              <div class="camera-icon"></div>
            {/if}
            {#if $overlayVisibility.triggers && display.actionBounds}
              <div class="trigger-overlay" style="left: {display.actionBounds[0] - live[0]}px; top: {display.actionBounds[1] - live[1]}px; width: {display.actionBounds[2]}px; height: {display.actionBounds[3]}px;"><span class="trigger-label">{display.actionBoundsKind}</span></div>
            {/if}
            {#if $overlayVisibility.bounds && display.colliderBounds}
              <div class="collider-overlay" style="left: {display.colliderBounds[0] - display.x}px; top: {display.colliderBounds[1] - display.y}px; width: {display.colliderBounds[2]}px; height: {display.colliderBounds[3]}px;"></div>
            {/if}
            {#if $overlayVisibility.markers && display.hasPlayer}<div class="player-indicator"></div>{/if}
            {#if $overlayVisibility.markers && display.hasSolid}<div class="solid-indicator">Solid</div>{/if}
            {#if $overlayVisibility.markers && (display.hasPortal || display.hasSpawn)}<div class="marker-indicator">{display.hasPortal ? "Portal" : "Spawn"}</div>{/if}
          </div>
        {/if}
      {/each}
    </div>
  </div>
</div>
