<script lang="ts">
  import { selection, showGrid, vfs } from '../lib/stores';
  import { mutateScene } from '../lib/actions';
  import type { SceneDocument, SceneEntity } from '../lib/types';

  let {
    scene,
    scenePath,
    zoom = $bindable(1.0),
  }: {
    scene: SceneDocument;
    scenePath: string;
    zoom: number;
  } = $props();

  // Entity drag state
  let dragIndex = $state(-1);
  let dragPos = $state<[number, number] | null>(null);
  let dragPointerStart = $state({ x: 0, y: 0 });
  let dragEntityStart = $state([0, 0]);
  let hasDragged = $state(false);

  // Pan state
  let scrollEl = $state<HTMLDivElement>();
  let isPanning = $state(false);
  let panStartScroll = $state({ x: 0, y: 0 });
  let panStartPointer = $state({ x: 0, y: 0 });

  const MIN_DRAG = 3;

  // Scene metrics
  let sceneWidth = $derived(scene.size?.width ?? 800);
  let sceneHeight = $derived(scene.size?.height ?? 450);
  let bgColor = $derived(scene.background?.color ?? '#1a1d23');

  // --- Texture blob URL cache ---
  // Non-reactive cache so template rendering can resolve blob URLs without
  // mutating Svelte state during derived/template evaluation.
  const textureUrlCache = new Map<string, string>();
  let lastVfs: Map<string, any> | null = null;

  function resolveTexturePath(texture: string): string | undefined {
    const currentVfs = $vfs;
    // Try the path as-is first, then with assets/ prefix
    const candidates = [texture];
    if (!texture.startsWith('assets/')) {
      candidates.push(`assets/${texture}`);
    }
    for (const candidate of candidates) {
      if (currentVfs.has(candidate)) return candidate;
    }
    return undefined;
  }

  function getTextureUrl(texture: string): string | undefined {
    const resolvedPath = resolveTexturePath(texture);
    if (!resolvedPath) return undefined;

    // Bust cache if VFS changed
    if (lastVfs !== $vfs) {
      for (const url of textureUrlCache.values()) {
        URL.revokeObjectURL(url);
      }
      textureUrlCache.clear();
      lastVfs = $vfs;
    }

    const cached = textureUrlCache.get(resolvedPath);
    if (cached) return cached;

    const file = $vfs.get(resolvedPath);
    if (!file || file.kind !== 'binary' || !file.bytes) return undefined;

    // Detect mime type from extension
    const lower = resolvedPath.toLowerCase();
    const mime = lower.endsWith('.png') ? 'image/png'
      : lower.endsWith('.jpg') || lower.endsWith('.jpeg') ? 'image/jpeg'
      : lower.endsWith('.gif') ? 'image/gif'
      : lower.endsWith('.webp') ? 'image/webp'
      : 'image/png';

    const blob = new Blob([file.bytes as BlobPart], { type: mime });
    const url = URL.createObjectURL(blob);
    textureUrlCache.set(resolvedPath, url);
    return url;
  }

  // --- Entity display ---

  function getTransform(entity: SceneEntity): Record<string, any> | undefined {
    return entity.components?.Transform as Record<string, any> | undefined;
  }

  function entityDisplay(entity: SceneEntity, index: number) {
    const t = getTransform(entity);
    const x = Number(t?.position?.[0]) || 0;
    const y = Number(t?.position?.[1]) || 0;

    const pos = index === dragIndex && dragPos ? dragPos : [x, y];

    const rect = entity.components?.Rect as Record<string, any> | undefined;
    const circle = entity.components?.Circle as Record<string, any> | undefined;
    const sprite = entity.components?.Sprite as Record<string, any> | undefined;
    const camera = entity.components?.Camera as Record<string, any> | undefined;
    const trigger = entity.components?.Trigger as Record<string, any> | undefined;
    const hasPlayer = entity.components?.PlayerController !== undefined;

    let visualType = 'empty';
    let width = 32;
    let height = 32;
    let color = '#7f8b93';
    let textureName = '';
    let textureUrl: string | undefined;

    if (rect) {
      visualType = 'rect';
      width = Number(rect.width) || 64;
      height = Number(rect.height) || 48;
      color = String(rect.color ?? '#ffffff');
    } else if (circle) {
      visualType = 'circle';
      const r = Number(circle.radius) || 16;
      width = r * 2;
      height = r * 2;
      color = String(circle.color ?? '#ffffff');
    } else if (sprite) {
      visualType = 'sprite';
      textureName = String(sprite.texture ?? '');
      textureUrl = getTextureUrl(textureName);
      // Size to the image's natural size, or use frame size, or default
      const fw = Number(sprite.frameWidth) || 0;
      const fh = Number(sprite.frameHeight) || 0;
      width = fw > 0 ? fw : (textureUrl ? 48 : 48);
      height = fh > 0 ? fh : (textureUrl ? 48 : 48);
    }

    const scaleX = Number(t?.scale?.[0]) || 1;
    const scaleY = Number(t?.scale?.[1]) || 1;

    return {
      x: pos[0],
      y: pos[1],
      width: Math.max(8, width * scaleX),
      height: Math.max(8, height * scaleY),
      color,
      visualType,
      tag: entity.tag,
      camera,
      trigger,
      hasPlayer,
      textureName,
      textureUrl,
    };
  }

  function clampZoom(z: number): number {
    return Math.max(0.1, Math.min(5.0, Math.round(z * 100) / 100));
  }

  function handleWheel(event: WheelEvent) {
    if (event.ctrlKey || event.metaKey) {
      event.preventDefault();
      const delta = -event.deltaY * 0.002;
      zoom = clampZoom(zoom * (1 + delta));
    }
  }

  // --- Entity pointer handler ---

  function handleEntityPointerDown(
    event: PointerEvent,
    index: number,
    display: ReturnType<typeof entityDisplay>,
  ) {
    event.preventDefault();
    event.stopPropagation();

    const el = event.currentTarget as HTMLElement;
    el.setPointerCapture(event.pointerId);

    dragIndex = index;
    dragPointerStart = { x: event.clientX, y: event.clientY };
    dragEntityStart = [display.x, display.y];
    dragPos = [display.x, display.y];
    hasDragged = false;

    selection.set({ type: 'entity', scenePath, entityIndex: index });
  }

  // --- Canvas-level pointer handlers (pan + entity drag move/up) ---

  function handleCanvasPointerDown(event: PointerEvent) {
    if (event.button === 1) {
      event.preventDefault();
      startPan(event);
      return;
    }

    const target = event.target as HTMLElement;
    if (
      target.classList.contains('scene-canvas') ||
      target.classList.contains('scene-canvas-stage')
    ) {
      startPan(event);
    }
  }

  function startPan(event: PointerEvent) {
    if (!scrollEl) return;
    const el = event.currentTarget as HTMLElement;
    el.setPointerCapture(event.pointerId);

    isPanning = true;
    panStartScroll = { x: scrollEl.scrollLeft, y: scrollEl.scrollTop };
    panStartPointer = { x: event.clientX, y: event.clientY };
  }

  function handlePointerMove(event: PointerEvent) {
    if (dragIndex >= 0) {
      const dx = (event.clientX - dragPointerStart.x) / zoom;
      const dy = (event.clientY - dragPointerStart.y) / zoom;

      const newX = Math.round(dragEntityStart[0] + dx);
      const newY = Math.round(dragEntityStart[1] + dy);

      if (Math.abs(dx) >= MIN_DRAG || Math.abs(dy) >= MIN_DRAG) {
        hasDragged = true;
      }

      dragPos = [newX, newY];
      return;
    }

    if (isPanning && scrollEl) {
      const dx = event.clientX - panStartPointer.x;
      const dy = event.clientY - panStartPointer.y;
      scrollEl.scrollLeft = panStartScroll.x - dx;
      scrollEl.scrollTop = panStartScroll.y - dy;
    }
  }

  function handlePointerUp(event: PointerEvent) {
    if (dragIndex >= 0) {
      const el = event.currentTarget as HTMLElement;
      if (el && typeof el.releasePointerCapture === 'function') {
        el.releasePointerCapture(event.pointerId);
      }

      if (hasDragged && dragPos) {
        const finalPos = dragPos;
        const entityIndex = dragIndex;
        const path = scenePath;

        mutateScene(path, (s) => {
          const entity = s.entities[entityIndex];
          if (!entity) return;
          let transform = entity.components?.Transform as
            | Record<string, any>
            | undefined;
          if (!transform) {
            transform = { position: finalPos, scale: [1, 1], rotation: 0 };
            if (!entity.components) entity.components = {};
            entity.components['Transform'] = transform;
          } else {
            transform.position = finalPos;
          }
        });
      }

      dragIndex = -1;
      dragPos = null;
      hasDragged = false;
      return;
    }

    if (isPanning) {
      const el = event.currentTarget as HTMLElement;
      if (el && typeof el.releasePointerCapture === 'function') {
        el.releasePointerCapture(event.pointerId);
      }
      isPanning = false;
    }
  }

  function handleCanvasClick(event: MouseEvent) {
    const target = event.target as HTMLElement;
    if (
      target.classList.contains('scene-canvas') ||
      target.classList.contains('scene-canvas-stage')
    ) {
      selection.set({ type: 'file', path: scenePath });
    }
  }

  function handleDoubleClick(event: MouseEvent) {
    const target = event.target as HTMLElement;
    if (
      target.classList.contains('scene-canvas') ||
      target.classList.contains('scene-canvas-stage')
    ) {
      zoom = 1.0;
    }
  }

  function handleContextMenu(event: MouseEvent) {
    event.preventDefault();
  }

  // Cleanup blob URLs on component teardown
  $effect(() => {
    return () => {
      for (const url of textureUrlCache.values()) {
        URL.revokeObjectURL(url);
      }
      textureUrlCache.clear();
    };
  });
</script>

<div class="scene-scroll" bind:this={scrollEl} onwheel={handleWheel}>
  <div
    class="scene-canvas-stage"
    style="width: {sceneWidth * zoom}px; height: {sceneHeight * zoom}px; position: relative;"
  >
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
    <div
      class="scene-canvas"
      class:show-grid={$showGrid}
      class:panning={isPanning}
      style="position: absolute; top: 0; left: 0;
             width: {sceneWidth}px; height: {sceneHeight}px;
             background-color: {bgColor};
             transform: scale({zoom}); transform-origin: 0 0;"
      onpointerdown={handleCanvasPointerDown}
      onpointermove={handlePointerMove}
      onpointerup={handlePointerUp}
      onclick={handleCanvasClick}
      onkeydown={() => {}}
      ondblclick={handleDoubleClick}
      oncontextmenu={handleContextMenu}
      role="application"
      aria-label="{scene.name} canvas"
    >
      {#each scene.entities as entity, i}
        {@const d = entityDisplay(entity, i)}
        <div
          class="scene-object"
          class:selected={$selection.type !== 'file' && $selection.scenePath === scenePath && $selection.entityIndex === i}
          class:dragging={dragIndex === i && hasDragged}
          style="left: {d.x}px; top: {d.y}px; width: {d.width}px; height: {d.height}px;"
          onpointerdown={(e) => handleEntityPointerDown(e, i, d)}
          role="button"
          tabindex="0"
          aria-label={d.tag ?? `Entity ${i + 1}`}
        >
          {#if d.visualType === 'rect'}
            <div
              class="entity-rect"
              style="background-color: {d.color};"
            ></div>
          {:else if d.visualType === 'circle'}
            <div
              class="entity-circle"
              style="background-color: {d.color};"
            ></div>
          {:else if d.visualType === 'sprite'}
            {#if d.textureUrl}
              <img
                class="entity-sprite-img"
                src={d.textureUrl}
                alt={d.textureName}
                draggable="false"
              />
            {:else}
              <div class="sprite-placeholder" title={d.textureName}>
                <span class="sprite-label"
                  >{d.textureName.split('/').pop() ?? 'sprite'}</span
                >
              </div>
            {/if}
          {:else}
            <div class="entity-empty">
              <span class="empty-icon">?</span>
            </div>
          {/if}

          <!-- Camera viewport overlay -->
          {#if d.camera}
            {@const camOffset = Array.isArray(d.camera.offset)
              ? (d.camera.offset as number[])
              : [400, 225]}
            <div
              class="camera-viewport"
              style="left: {camOffset[0] - sceneWidth / 2 - d.x}px;
                     top: {camOffset[1] - sceneHeight / 2 - d.y}px;
                     width: {sceneWidth}px;
                     height: {sceneHeight}px;"
            ></div>
            <div class="camera-icon"></div>
          {/if}

          <!-- Trigger bounds overlay -->
          {#if d.trigger}
            {@const bounds = Array.isArray(d.trigger.bounds)
              ? (d.trigger.bounds as number[])
              : [0, 0, 80, 80]}
            <div
              class="trigger-overlay"
              style="left: {bounds[0] - d.x}px;
                     top: {bounds[1] - d.y}px;
                     width: {bounds[2]}px;
                     height: {bounds[3]}px;"
            >
              <span class="trigger-label">Trigger</span>
            </div>
          {/if}

          <!-- Player indicator -->
          {#if d.hasPlayer}
            <div class="player-indicator"></div>
          {/if}

          <!-- Entity tag label -->
          <span class="entity-tag">{d.tag ?? `E${i + 1}`}</span>
        </div>
      {/each}
    </div>
  </div>
</div>
