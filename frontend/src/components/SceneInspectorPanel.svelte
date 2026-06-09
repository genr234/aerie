<script lang="ts">
  import { Copy, Plus, Trash2 } from "@lucide/svelte";
  import { selectedEntities } from "../lib/sceneEditor";
  import {
    addComponent,
    array2,
    array4,
    deleteEntities,
    duplicateEntities,
    isStartDialogueAction,
    numberOf,
    removeComponent,
    startDialogueId,
    startDialogueLabel,
    updateComponent,
    updateEntityTag,
  } from "../lib/actions";
  import { COMPONENT_CATEGORIES, componentsForCategory } from "../lib/componentRegistry";
  import { combatDecl, selection, paths, sceneDecls, dialogueDecls, vfs } from "../lib/stores";
  import { parseCombat, parseDialogue } from "../lib/project";
  import type { SceneDocument, SceneEntity } from "../lib/types";

  let { scene, scenePath }: { scene: SceneDocument; scenePath: string } = $props();
  let componentToAdd = $state("");
  let openComponents = $state<Record<string, boolean>>({});

  let selected = $derived($selectedEntities?.scenePath === scenePath ? $selectedEntities.indices : []);
  let selectedIndex = $derived(selected[0]);
  let selectedEntity = $derived(selected.length === 1 ? scene.entities[selectedIndex] : undefined);
  let assetPaths = $derived($paths.filter((path) => path.startsWith("assets/") && /\.(png|jpg|jpeg)$/i.test(path)));
  let combatEncounters = $derived($combatDecl?.path ? parseCombat($vfs, $combatDecl.path).combat?.encounters ?? [] : []);

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

  function updateAction(component: "Trigger" | "Interactable", action: Record<string, unknown>) {
    const current = getComponent(selectedEntity, component);
    const next: Record<string, unknown> = { ...current, action };
    delete next.actions;
    updateComponent(component, next);
  }

  function updateActionsJson(component: "Trigger" | "Interactable", text: string) {
    try {
      const parsed = JSON.parse(text);
      const current = getComponent(selectedEntity, component);
      if (Array.isArray(parsed)) {
        const next: Record<string, unknown> = { ...current, actions: parsed };
        delete next.action;
        updateComponent(component, next);
      } else {
        const next: Record<string, unknown> = { ...current, action: parsed };
        delete next.actions;
        updateComponent(component, next);
      }
    } catch {
      // Keep the last valid action when the user is midway through editing JSON.
    }
  }

  function actionJson(component: "Trigger" | "Interactable") {
    const current = getComponent(selectedEntity, component);
    return JSON.stringify(current.actions ?? current.action ?? {}, null, 2);
  }

  function updateDialogueActionField(component: "Trigger" | "Interactable", field: "id" | "label", value: string) {
    const current = getComponent(selectedEntity, component);
    const action = current.action as any;
    const dialogue = action?.startDialogue ?? {};
    updateAction(component, { startDialogue: { ...dialogue, [field]: value || undefined } });
  }

  function dialogueNodeOptions(action: any) {
    const id = startDialogueId(action) || $dialogueDecls[0]?.name;
    const decl = $dialogueDecls.find((dialogue) => dialogue.name === id);
    if (!decl) return [];
    return parseDialogue($vfs, decl.path).dialogue?.nodes ?? [];
  }

  function startCombatAction() {
    return { startCombat: { encounter: combatEncounters[0]?.id ?? "" } };
  }

  function isStartCombatAction(action: any) {
    return Boolean(action && typeof action === "object" && action.startCombat);
  }

  function updateCombatActionEncounter(component: "Trigger" | "Interactable", value: string) {
    updateAction(component, { startCombat: { encounter: value } });
  }

  function updateJsonField(component: string, field: string, text: string, fallback: unknown) {
    try {
      updateSimple(component, { [field]: JSON.parse(text) });
    } catch {
      updateSimple(component, { [field]: fallback });
    }
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
                <label>Frames <input type="number" min="1" value={numberOf(data.frames, 1)} onchange={(event) => updateSimple("Sprite", { frames: Number(event.currentTarget.value) })} /></label>
                <label>FPS <input type="number" step="0.1" value={numberOf(data.fps, 1)} onchange={(event) => updateSimple("Sprite", { fps: Number(event.currentTarget.value) })} /></label>
                <label><input type="checkbox" checked={data.loop !== false} onchange={(event) => updateSimple("Sprite", { loop: event.currentTarget.checked })} /> Loop</label>
              {:else if component === "Rect"}
                <label>Width <input type="number" value={numberOf(data.width, 64)} onchange={(event) => updateSimple("Rect", { width: Number(event.currentTarget.value) })} /></label>
                <label>Height <input type="number" value={numberOf(data.height, 48)} onchange={(event) => updateSimple("Rect", { height: Number(event.currentTarget.value) })} /></label>
                <label>Color <input type="color" value={String(data.color ?? "#ffffff").slice(0, 7)} onchange={(event) => updateSimple("Rect", { color: event.currentTarget.value })} /></label>
              {:else if component === "Circle"}
                <label>Radius <input type="number" value={numberOf(data.radius, 16)} onchange={(event) => updateSimple("Circle", { radius: Number(event.currentTarget.value) })} /></label>
                <label>Color <input type="color" value={String(data.color ?? "#ffffff").slice(0, 7)} onchange={(event) => updateSimple("Circle", { color: event.currentTarget.value })} /></label>
              {:else if component === "Layer"}
                <label>Order <input type="number" value={numberOf(data.order, 0)} onchange={(event) => updateSimple("Layer", { order: Number(event.currentTarget.value) })} /></label>
                <label><input type="checkbox" checked={Boolean(data.ySort)} onchange={(event) => updateSimple("Layer", { ySort: event.currentTarget.checked })} /> Y-sort children</label>
              {:else if component === "Camera"}
                {@const offset = array2(data.offset, [400, 225])}
                <label>Offset X <input type="number" value={offset[0]} onchange={(event) => updateSimple("Camera", { offset: [Number(event.currentTarget.value), offset[1]] })} /></label>
                <label>Offset Y <input type="number" value={offset[1]} onchange={(event) => updateSimple("Camera", { offset: [offset[0], Number(event.currentTarget.value)] })} /></label>
                <label>Zoom <input type="number" step="0.1" value={numberOf(data.zoom, 1)} onchange={(event) => updateSimple("Camera", { zoom: Number(event.currentTarget.value) })} /></label>
                <label>Rotation <input type="number" value={numberOf(data.rotation, 0)} onchange={(event) => updateSimple("Camera", { rotation: Number(event.currentTarget.value) })} /></label>
                <label>Smoothing <input type="number" step="0.1" value={numberOf(data.smoothing, 12)} onchange={(event) => updateSimple("Camera", { smoothing: Number(event.currentTarget.value) })} /></label>
                <label><input type="checkbox" checked={data.clampToScene !== false} onchange={(event) => updateSimple("Camera", { clampToScene: event.currentTarget.checked })} /> Clamp to scene</label>
                <label>Follow Tag <input value={String(data.followTag ?? "")} onchange={(event) => updateSimple("Camera", { followTag: event.currentTarget.value || undefined })} /></label>
              {:else if component === "PlayerController"}
                <label>Speed <input type="number" value={numberOf(data.speed, 100)} onchange={(event) => updateSimple("PlayerController", { speed: Number(event.currentTarget.value) })} /></label>
                <label>Mode <select value={String(data.mode ?? "smooth4")} onchange={(event) => updateSimple("PlayerController", { mode: event.currentTarget.value })}><option value="smooth4">smooth4</option><option value="smooth8">smooth8</option><option value="grid4">grid4</option></select></label>
                <label>Step Size <input type="number" value={numberOf(data.stepSize, 16)} onchange={(event) => updateSimple("PlayerController", { stepSize: Number(event.currentTarget.value) })} /></label>
                <label>Step Time <input type="number" step="0.01" value={numberOf(data.stepTime, 0.12)} onchange={(event) => updateSimple("PlayerController", { stepTime: Number(event.currentTarget.value) })} /></label>
              {:else if component === "Solid"}
                <label><input type="checkbox" checked={data.enabled !== false} onchange={(event) => updateSimple("Solid", { enabled: event.currentTarget.checked })} /> Enabled</label>
              {:else if component === "BoxCollider"}
                {@const offset = array2(data.offset, [0, 0])}
                <label>Width <input type="number" value={numberOf(data.width, 32)} onchange={(event) => updateSimple("BoxCollider", { width: Number(event.currentTarget.value), offset })} /></label>
                <label>Height <input type="number" value={numberOf(data.height, 24)} onchange={(event) => updateSimple("BoxCollider", { height: Number(event.currentTarget.value), offset })} /></label>
                <label>Offset X <input type="number" value={offset[0]} onchange={(event) => updateSimple("BoxCollider", { offset: [Number(event.currentTarget.value), offset[1]] })} /></label>
                <label>Offset Y <input type="number" value={offset[1]} onchange={(event) => updateSimple("BoxCollider", { offset: [offset[0], Number(event.currentTarget.value)] })} /></label>
              {:else if component === "Trigger"}
                {@const bounds = array4(data.bounds, [0, 0, 80, 80])}
                <label>X <input type="number" value={bounds[0]} onchange={(event) => updateSimple("Trigger", { bounds: [Number(event.currentTarget.value), bounds[1], bounds[2], bounds[3]] })} /></label>
                <label>Y <input type="number" value={bounds[1]} onchange={(event) => updateSimple("Trigger", { bounds: [bounds[0], Number(event.currentTarget.value), bounds[2], bounds[3]] })} /></label>
                <label>Width <input type="number" value={bounds[2]} onchange={(event) => updateSimple("Trigger", { bounds: [bounds[0], bounds[1], Number(event.currentTarget.value), bounds[3]] })} /></label>
                <label>Height <input type="number" value={bounds[3]} onchange={(event) => updateSimple("Trigger", { bounds: [bounds[0], bounds[1], bounds[2], Number(event.currentTarget.value)] })} /></label>
                <label><input type="checkbox" checked={Boolean(data.oneShot)} onchange={(event) => updateSimple("Trigger", { oneShot: event.currentTarget.checked })} /> One shot</label>
                <div class="action-buttons"><button type="button" onclick={() => updateAction("Trigger", { showMessage: { text: "Hello", duration: 2 } })}>showMessage</button><button type="button" onclick={() => updateAction("Trigger", { changeScene: { name: $sceneDecls[0]?.name ?? "" } })}>changeScene</button><button type="button" onclick={() => updateAction("Trigger", { setFlag: { name: "flag", value: true } })}>setFlag</button><button type="button" onclick={() => updateAction("Trigger", { startDialogue: {} })}>startDialogue</button><button type="button" disabled={combatEncounters.length === 0} title={combatEncounters.length === 0 ? "Create a combat encounter first" : "Start combat"} onclick={() => updateAction("Trigger", startCombatAction())}>startCombat</button></div>
                {#if isStartDialogueAction(data.action)}
                  <label>Dialogue <select value={startDialogueId(data.action)} onchange={(event) => updateDialogueActionField("Trigger", "id", event.currentTarget.value)}><option value="">First declared dialogue</option>{#each $dialogueDecls as dialogue}<option value={dialogue.name}>{dialogue.name}</option>{/each}</select></label>
                  <label>Dialogue Node <select value={startDialogueLabel(data.action)} onchange={(event) => updateDialogueActionField("Trigger", "label", event.currentTarget.value)}><option value="">Start node</option>{#each dialogueNodeOptions(data.action) as node}<option value={node.id}>{node.id}</option>{/each}</select></label>
                {/if}
                {#if isStartCombatAction(data.action)}
                  <label>Encounter <select value={String(data.action.startCombat?.encounter ?? "")} onchange={(event) => updateCombatActionEncounter("Trigger", event.currentTarget.value)}>{#each combatEncounters as encounter}<option value={encounter.id}>{encounter.id}</option>{/each}</select></label>
                {/if}
                <label>Action JSON <textarea rows="4" value={actionJson("Trigger")} onchange={(event) => updateActionsJson("Trigger", event.currentTarget.value)}></textarea></label>
              {:else if component === "Interactable"}
                {@const bounds = array4(data.bounds, [0, 0, 80, 80])}
                <label>X <input type="number" value={bounds[0]} onchange={(event) => updateSimple("Interactable", { bounds: [Number(event.currentTarget.value), bounds[1], bounds[2], bounds[3]] })} /></label>
                <label>Y <input type="number" value={bounds[1]} onchange={(event) => updateSimple("Interactable", { bounds: [bounds[0], Number(event.currentTarget.value), bounds[2], bounds[3]] })} /></label>
                <label>Width <input type="number" value={bounds[2]} onchange={(event) => updateSimple("Interactable", { bounds: [bounds[0], bounds[1], Number(event.currentTarget.value), bounds[3]] })} /></label>
                <label>Height <input type="number" value={bounds[3]} onchange={(event) => updateSimple("Interactable", { bounds: [bounds[0], bounds[1], bounds[2], Number(event.currentTarget.value)] })} /></label>
                <label>Prompt <input value={String(data.prompt ?? "")} onchange={(event) => updateSimple("Interactable", { prompt: event.currentTarget.value || undefined })} /></label>
                <label><input type="checkbox" checked={data.repeatable !== false} onchange={(event) => updateSimple("Interactable", { repeatable: event.currentTarget.checked })} /> Repeatable</label>
                <div class="action-buttons"><button type="button" onclick={() => updateAction("Interactable", { showMessage: { text: "Hello", duration: 2 } })}>showMessage</button><button type="button" onclick={() => updateAction("Interactable", { changeScene: { name: $sceneDecls[0]?.name ?? "" } })}>changeScene</button><button type="button" onclick={() => updateAction("Interactable", { setFlag: { name: "flag", value: true } })}>setFlag</button><button type="button" onclick={() => updateAction("Interactable", { startDialogue: {} })}>startDialogue</button><button type="button" disabled={combatEncounters.length === 0} title={combatEncounters.length === 0 ? "Create a combat encounter first" : "Start combat"} onclick={() => updateAction("Interactable", startCombatAction())}>startCombat</button></div>
                {#if isStartDialogueAction(data.action)}
                  <label>Dialogue <select value={startDialogueId(data.action)} onchange={(event) => updateDialogueActionField("Interactable", "id", event.currentTarget.value)}><option value="">First declared dialogue</option>{#each $dialogueDecls as dialogue}<option value={dialogue.name}>{dialogue.name}</option>{/each}</select></label>
                  <label>Dialogue Node <select value={startDialogueLabel(data.action)} onchange={(event) => updateDialogueActionField("Interactable", "label", event.currentTarget.value)}><option value="">Start node</option>{#each dialogueNodeOptions(data.action) as node}<option value={node.id}>{node.id}</option>{/each}</select></label>
                {/if}
                {#if isStartCombatAction(data.action)}
                  <label>Encounter <select value={String(data.action.startCombat?.encounter ?? "")} onchange={(event) => updateCombatActionEncounter("Interactable", event.currentTarget.value)}>{#each combatEncounters as encounter}<option value={encounter.id}>{encounter.id}</option>{/each}</select></label>
                {/if}
                <label>Action JSON <textarea rows="4" value={actionJson("Interactable")} onchange={(event) => updateActionsJson("Interactable", event.currentTarget.value)}></textarea></label>
              {:else if component === "Portal"}
                {@const bounds = array4(data.bounds, [0, 0, 80, 80])}
                <label>X <input type="number" value={bounds[0]} onchange={(event) => updateSimple("Portal", { bounds: [Number(event.currentTarget.value), bounds[1], bounds[2], bounds[3]] })} /></label>
                <label>Y <input type="number" value={bounds[1]} onchange={(event) => updateSimple("Portal", { bounds: [bounds[0], Number(event.currentTarget.value), bounds[2], bounds[3]] })} /></label>
                <label>Width <input type="number" value={bounds[2]} onchange={(event) => updateSimple("Portal", { bounds: [bounds[0], bounds[1], Number(event.currentTarget.value), bounds[3]] })} /></label>
                <label>Height <input type="number" value={bounds[3]} onchange={(event) => updateSimple("Portal", { bounds: [bounds[0], bounds[1], bounds[2], Number(event.currentTarget.value)] })} /></label>
                <label>Scene <select value={String(data.scene ?? "")} onchange={(event) => updateSimple("Portal", { scene: event.currentTarget.value })}><option value="">-- Scene --</option>{#each $sceneDecls as scene}<option value={scene.name}>{scene.name}</option>{/each}</select></label>
                <label>Spawn <input value={String(data.spawn ?? "")} onchange={(event) => updateSimple("Portal", { spawn: event.currentTarget.value || undefined })} /></label>
              {:else if component === "SpawnPoint"}
                <label>Name <input value={String(data.name ?? "")} onchange={(event) => updateSimple("SpawnPoint", { name: event.currentTarget.value })} /></label>
              {:else if component === "Animation"}
                <label>Current <input value={String(data.current ?? "idle")} onchange={(event) => updateSimple("Animation", { current: event.currentTarget.value || undefined })} /></label>
                <label>Clips JSON <textarea rows="5" value={JSON.stringify(data.clips ?? [], null, 2)} onchange={(event) => updateJsonField("Animation", "clips", event.currentTarget.value, [])}></textarea></label>
              {:else if component === "Tilemap"}
                <label>Columns <input type="number" min="1" value={numberOf(data.columns, 8)} onchange={(event) => updateSimple("Tilemap", { columns: Number(event.currentTarget.value) })} /></label>
                <label>Rows <input type="number" min="1" value={numberOf(data.rows, 6)} onchange={(event) => updateSimple("Tilemap", { rows: Number(event.currentTarget.value) })} /></label>
                <label>Tile W <input type="number" min="1" value={numberOf(data.tileWidth, 16)} onchange={(event) => updateSimple("Tilemap", { tileWidth: Number(event.currentTarget.value) })} /></label>
                <label>Tile H <input type="number" min="1" value={numberOf(data.tileHeight, 16)} onchange={(event) => updateSimple("Tilemap", { tileHeight: Number(event.currentTarget.value) })} /></label>
                <label>Palette JSON <textarea rows="3" value={JSON.stringify(data.palette ?? ["#5f8f5f"], null, 2)} onchange={(event) => updateJsonField("Tilemap", "palette", event.currentTarget.value, ["#5f8f5f"])}></textarea></label>
                <label>Solid Tiles JSON <textarea rows="3" value={JSON.stringify(data.solidTiles ?? [], null, 2)} onchange={(event) => updateJsonField("Tilemap", "solidTiles", event.currentTarget.value, [])}></textarea></label>
                <label>Tiles JSON <textarea rows="5" value={JSON.stringify(data.tiles ?? [], null, 2)} onchange={(event) => updateJsonField("Tilemap", "tiles", event.currentTarget.value, [])}></textarea></label>
              {:else if component === "ParticleEmitter"}
                <label>Color <input type="color" value={String(data.color ?? "#ffffff").slice(0, 7)} onchange={(event) => updateSimple("ParticleEmitter", { color: event.currentTarget.value })} /></label>
                <label>Rate <input type="number" step="0.1" value={numberOf(data.rate, 0)} onchange={(event) => updateSimple("ParticleEmitter", { rate: Number(event.currentTarget.value) })} /></label>
                <label>Lifetime <input type="number" step="0.1" value={numberOf(data.lifetime, 0.6)} onchange={(event) => updateSimple("ParticleEmitter", { lifetime: Number(event.currentTarget.value) })} /></label>
                <label>Speed <input type="number" step="0.1" value={numberOf(data.speed, 40)} onchange={(event) => updateSimple("ParticleEmitter", { speed: Number(event.currentTarget.value) })} /></label>
                <label>Spread <input type="number" step="0.01" value={numberOf(data.spread, 6.28)} onchange={(event) => updateSimple("ParticleEmitter", { spread: Number(event.currentTarget.value) })} /></label>
                <label>Radius <input type="number" step="0.1" value={numberOf(data.radius, 2)} onchange={(event) => updateSimple("ParticleEmitter", { radius: Number(event.currentTarget.value) })} /></label>
                <label>Burst <input type="number" value={numberOf(data.burst, 12)} onchange={(event) => updateSimple("ParticleEmitter", { burst: Number(event.currentTarget.value) })} /></label>
              {:else if component === "Tween"}
                {@const to = array2(data.to, [128, 128])}
                <label>To X <input type="number" value={to[0]} onchange={(event) => updateSimple("Tween", { to: [Number(event.currentTarget.value), to[1]] })} /></label>
                <label>To Y <input type="number" value={to[1]} onchange={(event) => updateSimple("Tween", { to: [to[0], Number(event.currentTarget.value)] })} /></label>
                <label>Duration <input type="number" step="0.1" value={numberOf(data.duration, 1)} onchange={(event) => updateSimple("Tween", { duration: Number(event.currentTarget.value) })} /></label>
                <label><input type="checkbox" checked={Boolean(data.loop)} onchange={(event) => updateSimple("Tween", { loop: event.currentTarget.checked })} /> Loop</label>
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
