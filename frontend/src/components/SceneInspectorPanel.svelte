<script lang="ts">
  import { Copy, Plus, Trash2 } from "@lucide/svelte";
  import { selectedEntities } from "../lib/sceneEditor";
  import { addComponent, array2, array4, deleteEntities, duplicateEntities, numberOf, removeComponent, updateComponent, updateEntityTag } from "../lib/actions";
  import { COMPONENT_CATEGORIES, componentsForCategory } from "../lib/componentRegistry";
  import { selection, paths } from "../lib/stores";
  import type { SceneDocument, SceneEntity } from "../lib/types";

  let { scene, scenePath }: { scene: SceneDocument; scenePath: string } = $props();
  let componentToAdd = $state("");
  let openComponents = $state<Record<string, boolean>>({});

  let selected = $derived($selectedEntities?.scenePath === scenePath ? $selectedEntities.indices : []);
  let selectedIndex = $derived(selected[0]);
  let selectedEntity = $derived(selected.length === 1 ? scene.entities[selectedIndex] : undefined);
  let assetPaths = $derived($paths.filter((path) => path.startsWith("assets/") && /\.(png|jpg|jpeg)$/i.test(path)));

  $effect(() => {
    componentToAdd = firstAvailableComponent(selectedEntity);
  });

  function firstAvailableComponent(entity: SceneEntity | undefined): string {
    if (!entity) return "";
    for (const category of COMPONENT_CATEGORIES) {
      for (const definition of componentsForCategory(category)) {
        if (!entity.components[definition.name]) return definition.name;
      }
    }
    return "";
  }

  function getComponent(entity: SceneEntity | undefined, name: string): Record<string, any> {
    const value = entity?.components[name];
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, any> : {};
  }

  function selectComponent(component: string) {
    if (selectedIndex === undefined) return;
    selection.set({ type: "component", scenePath, entityIndex: selectedIndex, component });
  }

  function addSelectedComponent() {
    if (!componentToAdd || selectedIndex === undefined) return;
    selection.set({ type: "entity", scenePath, entityIndex: selectedIndex });
    addComponent(componentToAdd);
    openComponents = { ...openComponents, [componentToAdd]: true };
  }

  function updateTransform(patch: Record<string, unknown>) {
    const transform = getComponent(selectedEntity, "Transform");
    updateComponent("Transform", { ...transform, ...patch });
  }

  function updateSimple(component: string, patch: Record<string, unknown>) {
    const current = getComponent(selectedEntity, component);
    updateComponent(component, { ...current, ...patch });
  }
</script>

<aside class="scene-inspector-panel">
  <header>
    <strong>Inspector</strong>
    <span>{selected.length === 0 ? "No selection" : selected.length === 1 ? "1 entity" : `${selected.length} entities`}</span>
  </header>

  {#if selected.length > 1}
    <section class="scene-inspector-empty">
      <p>{selected.length} entities selected.</p>
      <div class="inspector-actions">
        <button class="tool-button" onclick={() => duplicateEntities(scenePath, selected)}><Copy size={14} />Duplicate</button>
        <button class="tool-button" onclick={() => deleteEntities(scenePath, selected)}><Trash2 size={14} />Delete</button>
      </div>
    </section>
  {:else if selectedEntity}
    <section class="compact-section">
      <label>Tag <input value={selectedEntity.tag ?? ""} onchange={(event) => updateEntityTag(event.currentTarget.value)} /></label>
      <div class="inspector-actions">
        <button class="icon-button" title="Duplicate" onclick={() => duplicateEntities(scenePath, selected)}><Copy size={15} /></button>
        <button class="icon-button" title="Delete" onclick={() => deleteEntities(scenePath, selected)}><Trash2 size={15} /></button>
      </div>
    </section>

    {#if selectedEntity.components.Transform}
      {@const transform = getComponent(selectedEntity, "Transform")}
      {@const position = array2(transform.position, [0, 0])}
      {@const scale = array2(transform.scale, [1, 1])}
      <fieldset class="transform-card">
        <legend>Transform</legend>
        <label>X <input type="number" value={position[0]} onchange={(event) => updateTransform({ position: [Number(event.currentTarget.value), position[1]], scale })} /></label>
        <label>Y <input type="number" value={position[1]} onchange={(event) => updateTransform({ position: [position[0], Number(event.currentTarget.value)], scale })} /></label>
        <label>Rot <input type="number" value={numberOf(transform.rotation, 0)} onchange={(event) => updateTransform({ rotation: Number(event.currentTarget.value), position, scale })} /></label>
        <label>SX <input type="number" step="0.1" value={scale[0]} onchange={(event) => updateTransform({ position, scale: [Number(event.currentTarget.value), scale[1]] })} /></label>
        <label>SY <input type="number" step="0.1" value={scale[1]} onchange={(event) => updateTransform({ position, scale: [scale[0], Number(event.currentTarget.value)] })} /></label>
      </fieldset>
    {/if}

    <div class="component-add-row">
      <select bind:value={componentToAdd}>
        <option value="">All components added</option>
        {#each COMPONENT_CATEGORIES as category}
          {@const available = componentsForCategory(category).filter((definition) => !selectedEntity.components[definition.name])}
          {#if available.length > 0}
            <optgroup label={category}>
              {#each available as definition}<option value={definition.name}>{definition.name}</option>{/each}
            </optgroup>
          {/if}
        {/each}
      </select>
      <button class="icon-button" disabled={!componentToAdd} title="Add component" onclick={addSelectedComponent}><Plus size={15} /></button>
    </div>

    <div class="component-stack">
      {#each Object.keys(selectedEntity.components).filter((name) => name !== "Transform") as component}
        {@const data = getComponent(selectedEntity, component)}
        <section class="component-fold">
          <button class="component-fold-title" class:active={$selection.type === "component" && $selection.component === component} onclick={() => { openComponents = { ...openComponents, [component]: !(openComponents[component] ?? true) }; selectComponent(component); }}>
            <span>{component}</span>
            <small>{openComponents[component] === false ? "Closed" : "Open"}</small>
          </button>
          {#if openComponents[component] !== false}
            <div class="component-fields">
              {#if component === "Sprite"}
                <label>Texture <select value={String(data.texture ?? "")} onchange={(event) => updateSimple("Sprite", { texture: event.currentTarget.value || undefined })}><option value="">None</option>{#each assetPaths as asset}<option value={asset.replace(/^assets\//, "")}>{asset.replace(/^assets\//, "")}</option>{/each}</select></label>
                <label>Frame W <input type="number" value={numberOf(data.frameWidth, 0)} onchange={(event) => updateSimple("Sprite", { frameWidth: Number(event.currentTarget.value) })} /></label>
                <label>Frame H <input type="number" value={numberOf(data.frameHeight, 0)} onchange={(event) => updateSimple("Sprite", { frameHeight: Number(event.currentTarget.value) })} /></label>
              {:else if component === "Rect"}
                <label>Width <input type="number" value={numberOf(data.width, 64)} onchange={(event) => updateSimple("Rect", { width: Number(event.currentTarget.value) })} /></label>
                <label>Height <input type="number" value={numberOf(data.height, 48)} onchange={(event) => updateSimple("Rect", { height: Number(event.currentTarget.value) })} /></label>
                <label>Color <input value={String(data.color ?? "#ffffff")} onchange={(event) => updateSimple("Rect", { color: event.currentTarget.value })} /></label>
              {:else if component === "Circle"}
                <label>Radius <input type="number" value={numberOf(data.radius, 16)} onchange={(event) => updateSimple("Circle", { radius: Number(event.currentTarget.value) })} /></label>
                <label>Color <input value={String(data.color ?? "#ffffff")} onchange={(event) => updateSimple("Circle", { color: event.currentTarget.value })} /></label>
              {:else if component === "Camera"}
                {@const offset = array2(data.offset, [400, 225])}
                <label>Offset X <input type="number" value={offset[0]} onchange={(event) => updateSimple("Camera", { offset: [Number(event.currentTarget.value), offset[1]] })} /></label>
                <label>Offset Y <input type="number" value={offset[1]} onchange={(event) => updateSimple("Camera", { offset: [offset[0], Number(event.currentTarget.value)] })} /></label>
                <label>Zoom <input type="number" step="0.1" value={numberOf(data.zoom, 1)} onchange={(event) => updateSimple("Camera", { zoom: Number(event.currentTarget.value) })} /></label>
              {:else if component === "Trigger"}
                {@const bounds = array4(data.bounds, [0, 0, 80, 80])}
                <label>X <input type="number" value={bounds[0]} onchange={(event) => updateSimple("Trigger", { bounds: [Number(event.currentTarget.value), bounds[1], bounds[2], bounds[3]] })} /></label>
                <label>Y <input type="number" value={bounds[1]} onchange={(event) => updateSimple("Trigger", { bounds: [bounds[0], Number(event.currentTarget.value), bounds[2], bounds[3]] })} /></label>
                <label>Width <input type="number" value={bounds[2]} onchange={(event) => updateSimple("Trigger", { bounds: [bounds[0], bounds[1], Number(event.currentTarget.value), bounds[3]] })} /></label>
                <label>Height <input type="number" value={bounds[3]} onchange={(event) => updateSimple("Trigger", { bounds: [bounds[0], bounds[1], bounds[2], Number(event.currentTarget.value)] })} /></label>
                <label><input type="checkbox" checked={Boolean(data.oneShot)} onchange={(event) => updateSimple("Trigger", { oneShot: event.currentTarget.checked })} /> One shot</label>
                <label>Action JSON <textarea rows="4" value={JSON.stringify(data.action ?? data.actions ?? {}, null, 2)} onchange={(event) => { try { const parsed = JSON.parse(event.currentTarget.value); updateSimple("Trigger", Array.isArray(parsed) ? { actions: parsed, action: undefined } : { action: parsed, actions: undefined }); } catch {} }}></textarea></label>
              {:else if component === "Interactable"}
                {@const bounds = array4(data.bounds, [0, 0, 80, 80])}
                <label>X <input type="number" value={bounds[0]} onchange={(event) => updateSimple("Interactable", { bounds: [Number(event.currentTarget.value), bounds[1], bounds[2], bounds[3]] })} /></label>
                <label>Y <input type="number" value={bounds[1]} onchange={(event) => updateSimple("Interactable", { bounds: [bounds[0], Number(event.currentTarget.value), bounds[2], bounds[3]] })} /></label>
                <label>Width <input type="number" value={bounds[2]} onchange={(event) => updateSimple("Interactable", { bounds: [bounds[0], bounds[1], Number(event.currentTarget.value), bounds[3]] })} /></label>
                <label>Height <input type="number" value={bounds[3]} onchange={(event) => updateSimple("Interactable", { bounds: [bounds[0], bounds[1], bounds[2], Number(event.currentTarget.value)] })} /></label>
                <label>Prompt <input value={String(data.prompt ?? "")} onchange={(event) => updateSimple("Interactable", { prompt: event.currentTarget.value || undefined })} /></label>
                <label><input type="checkbox" checked={data.repeatable !== false} onchange={(event) => updateSimple("Interactable", { repeatable: event.currentTarget.checked })} /> Repeatable</label>
              {:else if component === "Portal"}
                {@const bounds = array4(data.bounds, [0, 0, 80, 80])}
                <label>X <input type="number" value={bounds[0]} onchange={(event) => updateSimple("Portal", { bounds: [Number(event.currentTarget.value), bounds[1], bounds[2], bounds[3]] })} /></label>
                <label>Y <input type="number" value={bounds[1]} onchange={(event) => updateSimple("Portal", { bounds: [bounds[0], Number(event.currentTarget.value), bounds[2], bounds[3]] })} /></label>
                <label>Width <input type="number" value={bounds[2]} onchange={(event) => updateSimple("Portal", { bounds: [bounds[0], bounds[1], Number(event.currentTarget.value), bounds[3]] })} /></label>
                <label>Height <input type="number" value={bounds[3]} onchange={(event) => updateSimple("Portal", { bounds: [bounds[0], bounds[1], bounds[2], Number(event.currentTarget.value)] })} /></label>
                <label>Scene <input value={String(data.scene ?? "")} onchange={(event) => updateSimple("Portal", { scene: event.currentTarget.value })} /></label>
                <label>Spawn <input value={String(data.spawn ?? "")} onchange={(event) => updateSimple("Portal", { spawn: event.currentTarget.value || undefined })} /></label>
              {:else}
                <textarea rows="5" value={JSON.stringify(data, null, 2)} onchange={(event) => { try { updateComponent(component, JSON.parse(event.currentTarget.value)); } catch {} }}></textarea>
              {/if}
              <button class="tool-button danger" onclick={() => removeComponent(component)}><Trash2 size={14} />Remove</button>
            </div>
          {/if}
        </section>
      {/each}
    </div>
  {:else}
    <section class="scene-inspector-empty">
      <p>Select an entity in the viewport or outliner.</p>
    </section>
  {/if}
</aside>
