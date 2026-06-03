<script lang="ts">
  import { createEventDispatcher } from "svelte";
  import { ArrowLeftToLine, ArrowRightToLine, Copy, Trash2, Plus, PanelRightOpen, PanelRightClose } from "@lucide/svelte";
  import { selection, vfs, paths, sceneDecls, dialogueDecls } from "../lib/stores";
  import {
    moveSelectedEntity, duplicateEntity, deleteEntity, updateEntityTag,
    addComponent, removeComponent, updateComponent, updateTriggerAction,
    updateTriggerActionJson, updateStartDialogueLabel, updateStartDialogueId,
    isStartDialogueAction, startDialogueId, startDialogueLabel,
    array2, array4, numberOf
  } from "../lib/actions";
  import { COMPONENTS } from "../lib/project";
  import { parseScene } from "../lib/project";
  import type { SceneEntity } from "../lib/types";

  export let collapsed = false;
  const dispatch = createEventDispatcher<{ toggleCollapse: void }>();

  $: scenePath = $selection.type !== "file" ? $selection.scenePath : undefined;
  $: selectedScene = scenePath ? parseScene($vfs, scenePath).scene : undefined;
  $: selectedEntity = selectedScene && $selection.type !== "file" ? selectedScene.entities[$selection.entityIndex] : undefined;
  $: selectedComponentName = $selection.type === "component" ? $selection.component : undefined;
  $: assetPaths = $paths.filter((path) => path.startsWith("assets/") && /\.(png|jpg|jpeg)$/i.test(path));
  $: entityKey = $selection.type !== "file" ? `${$selection.scenePath}:${$selection.entityIndex}` : null;

  // Extract component value from the already-reactive selectedEntity — avoids
  // get()-based store reads so Svelte can track the dependency chain correctly.
  function getComponent(entity: SceneEntity | undefined, name: string): Record<string, any> {
    if (!entity) return {};
    const value = entity.components[name];
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, any> : {};
  }

  function selectComponent(component: string) {
    if ($selection.type === "file") return;
    $selection = {
      type: "component",
      scenePath: $selection.scenePath,
      entityIndex: $selection.entityIndex,
      component,
    };
  }
</script>

  <aside class="inspector" class:collapsed={collapsed}>
    <button class="inspector-collapse-btn" on:click={() => dispatch("toggleCollapse")} title={collapsed ? "Show inspector" : "Hide inspector"}>
      {#if collapsed}
        <PanelRightOpen size={16} aria-hidden="true" />
      {:else}
        <PanelRightClose size={16} aria-hidden="true" />
      {/if}
    </button>
    {#if !collapsed}

    <section>
      <h2>Inspector</h2>
      {#if selectedEntity && $selection.type !== "file"}
        {#key entityKey}
          <div class="inspector-actions">
            <button
              class="icon-button"
              on:click={() => moveSelectedEntity(-1)}
              title="Send backward"
              aria-label="Send backward"
              ><ArrowLeftToLine size={16} aria-hidden="true" /></button
            >
            <button
              class="icon-button"
              on:click={() => moveSelectedEntity(1)}
              title="Bring forward"
              aria-label="Bring forward"
              ><ArrowRightToLine size={16} aria-hidden="true" /></button
            >
            <button
              class="icon-button"
              on:click={duplicateEntity}
              title="Duplicate entity"
              aria-label="Duplicate entity"
              ><Copy size={16} aria-hidden="true" /></button
            >
            <button
              class="icon-button"
              on:click={deleteEntity}
              title="Delete entity"
              aria-label="Delete entity"
              ><Trash2 size={16} aria-hidden="true" /></button
            >
          </div>
          <label
            >Tag <input
              value={selectedEntity.tag ?? ""}
              on:change={(event) => updateEntityTag(event.currentTarget.value)}
            /></label
          >
          <div class="component-actions">
            {#each COMPONENTS as component}
              <button
                class:active={selectedComponentName === component}
                on:click={() =>
                  selectedEntity.components[component]
                    ? selectComponent(component)
                    : addComponent(component)}
                >{selectedEntity.components[component] ? component : `+ ${component}`}</button
              >
            {/each}
          </div>

          {#if selectedEntity.components.Transform}
            {@const transform = getComponent(selectedEntity, "Transform")}
            {@const position = array2(transform.position, [0, 0])}
            {@const scale = array2(transform.scale, [1, 1])}
            <fieldset>
              <legend>Transform</legend>
              <label
                >X <input
                  type="number"
                  value={position[0]}
                  on:change={(event) =>
                    updateComponent("Transform", {
                      ...transform,
                      position: [Number(event.currentTarget.value), position[1]],
                      scale,
                    })}
                /></label
              >
              <label
                >Y <input
                  type="number"
                  value={position[1]}
                  on:change={(event) =>
                    updateComponent("Transform", {
                      ...transform,
                      position: [position[0], Number(event.currentTarget.value)],
                      scale,
                    })}
                /></label
              >
              <label
                >Rotation <input
                  type="number"
                  value={numberOf(transform.rotation, 0)}
                  on:change={(event) =>
                    updateComponent("Transform", {
                      ...transform,
                      rotation: Number(event.currentTarget.value),
                      position,
                      scale,
                    })}
                /></label
              >
              <label
                >Scale X <input
                  type="number"
                  value={scale[0]}
                  step="0.1"
                  on:change={(event) =>
                    updateComponent("Transform", {
                      ...transform,
                      position,
                      scale: [Number(event.currentTarget.value), scale[1]],
                    })}
                /></label
              >
              <label
                >Scale Y <input
                  type="number"
                  value={scale[1]}
                  step="0.1"
                  on:change={(event) =>
                    updateComponent("Transform", {
                      ...transform,
                      position,
                      scale: [scale[0], Number(event.currentTarget.value)],
                    })}
                /></label
              >
            </fieldset>
          {/if}

          {#if selectedEntity.components.Sprite}
            {@const sprite = getComponent(selectedEntity, "Sprite")}
            <fieldset>
              <legend>Sprite</legend>
              <label
                >Texture
                <select
                  value={String(sprite.texture ?? "")}
                  on:change={(event) =>
                    updateComponent("Sprite", {
                      ...sprite,
                      texture: event.currentTarget.value || undefined,
                    })}
                >
                  <option value="">-- None --</option>
                  {#each assetPaths as asset}
                    <option value={asset.replace(/^assets\//, "")}
                      >{asset.replace(/^assets\//, "")}</option
                    >
                  {/each}
                </select>
              </label>
              <label
                ><input
                  type="checkbox"
                  checked={Boolean(sprite.flipX)}
                  on:change={(event) =>
                    updateComponent("Sprite", {
                      ...sprite,
                      flipX: event.currentTarget.checked,
                    })}
                /> Flip X</label
              >
              <label
                >Tint <input
                  value={String(sprite.tint ?? "")}
                  on:change={(event) =>
                    updateComponent("Sprite", {
                      ...sprite,
                      tint: event.currentTarget.value || undefined,
                    })}
                /></label
              >
              <label
                >Frame Width <input
                  type="number"
                  value={numberOf(sprite.frameWidth, 0)}
                  on:change={(event) =>
                    updateComponent("Sprite", {
                      ...sprite,
                      frameWidth: Number(event.currentTarget.value),
                    })}
                /></label
              >
              <label
                >Frame Height <input
                  type="number"
                  value={numberOf(sprite.frameHeight, 0)}
                  on:change={(event) =>
                    updateComponent("Sprite", {
                      ...sprite,
                      frameHeight: Number(event.currentTarget.value),
                    })}
                /></label
              >
              <label
                >Frames <input
                  type="number"
                  min="1"
                  value={numberOf(sprite.frames, 1)}
                  on:change={(event) =>
                    updateComponent("Sprite", {
                      ...sprite,
                      frames: Math.max(1, Number(event.currentTarget.value)),
                    })}
                /></label
              >
              <label
                >FPS <input
                  type="number"
                  min="0"
                  value={numberOf(sprite.fps, 0)}
                  on:change={(event) =>
                    updateComponent("Sprite", {
                      ...sprite,
                      fps: Number(event.currentTarget.value),
                    })}
                /></label
              >
              <label
                ><input
                  type="checkbox"
                  checked={sprite.loop !== false}
                  on:change={(event) =>
                    updateComponent("Sprite", {
                      ...sprite,
                      loop: event.currentTarget.checked,
                    })}
                /> Loop Animation</label
              >
            </fieldset>
          {/if}

          {#if selectedEntity.components.Rect}
            {@const rect = getComponent(selectedEntity, "Rect")}
            <fieldset>
              <legend>Rect</legend>
              <label
                >Width <input
                  type="number"
                  value={numberOf(rect.width, 64)}
                  on:change={(event) =>
                    updateComponent("Rect", {
                      ...rect,
                      width: Number(event.currentTarget.value),
                    })}
                /></label
              >
              <label
                >Height <input
                  type="number"
                  value={numberOf(rect.height, 48)}
                  on:change={(event) =>
                    updateComponent("Rect", {
                      ...rect,
                      height: Number(event.currentTarget.value),
                    })}
                /></label
              >
              <label
                >Color <input
                  value={String(rect.color ?? "#ffffff")}
                  on:change={(event) =>
                    updateComponent("Rect", {
                      ...rect,
                      color: event.currentTarget.value,
                    })}
                /></label
              >
            </fieldset>
          {/if}

          {#if selectedEntity.components.Circle}
            {@const circle = getComponent(selectedEntity, "Circle")}
            <fieldset>
              <legend>Circle</legend>
              <label
                >Radius <input
                  type="number"
                  value={numberOf(circle.radius, 16)}
                  on:change={(event) =>
                    updateComponent("Circle", {
                      ...circle,
                      radius: Number(event.currentTarget.value),
                    })}
                /></label
              >
              <label
                >Color <input
                  value={String(circle.color ?? "#ffffff")}
                  on:change={(event) =>
                    updateComponent("Circle", {
                      ...circle,
                      color: event.currentTarget.value,
                    })}
                /></label
              >
            </fieldset>
          {/if}

          {#if selectedEntity.components.Camera}
            {@const camera = getComponent(selectedEntity, "Camera")}
            {@const offset = array2(camera.offset, [400, 225])}
            <fieldset>
              <legend>Camera</legend>
              <label
                >Offset X <input
                  type="number"
                  value={offset[0]}
                  on:change={(event) =>
                    updateComponent("Camera", {
                      ...camera,
                      offset: [Number(event.currentTarget.value), offset[1]],
                    })}
                /></label
              >
              <label
                >Offset Y <input
                  type="number"
                  value={offset[1]}
                  on:change={(event) =>
                    updateComponent("Camera", {
                      ...camera,
                      offset: [offset[0], Number(event.currentTarget.value)],
                    })}
                /></label
              >
              <label
                >Zoom <input
                  type="number"
                  step="0.1"
                  value={numberOf(camera.zoom, 1)}
                  on:change={(event) =>
                    updateComponent("Camera", {
                      ...camera,
                      zoom: Number(event.currentTarget.value),
                    })}
                /></label
              >
              <label
                >Follow Tag <input
                  value={String(camera.followTag ?? "")}
                  on:change={(event) =>
                    updateComponent("Camera", {
                      ...camera,
                      followTag: event.currentTarget.value || undefined,
                    })}
                /></label
              >
            </fieldset>
          {/if}

          {#if selectedEntity.components.PlayerController}
            {@const controller = getComponent(selectedEntity, "PlayerController")}
            <fieldset>
              <legend>Player Controller</legend>
              <label
                >Speed <input
                  type="number"
                  value={numberOf(controller.speed, 100)}
                  on:change={(event) =>
                    updateComponent("PlayerController", {
                      ...controller,
                      speed: Number(event.currentTarget.value),
                    })}
                /></label
              >
            </fieldset>
          {/if}

          {#if selectedEntity.components.Trigger}
            {@const trigger = getComponent(selectedEntity, "Trigger")}
            {@const bounds = array4(trigger.bounds, [0, 0, 80, 80])}
            <fieldset>
              <legend>Trigger</legend>
              <label
                >X <input
                  type="number"
                  value={bounds[0]}
                  on:change={(event) =>
                    updateComponent("Trigger", {
                      ...trigger,
                      bounds: [
                        Number(event.currentTarget.value),
                        bounds[1],
                        bounds[2],
                        bounds[3],
                      ],
                    })}
                /></label
              >
              <label
                >Y <input
                  type="number"
                  value={bounds[1]}
                  on:change={(event) =>
                    updateComponent("Trigger", {
                      ...trigger,
                      bounds: [
                        bounds[0],
                        Number(event.currentTarget.value),
                        bounds[2],
                        bounds[3],
                      ],
                    })}
                /></label
              >
              <label
                >Width <input
                  type="number"
                  value={bounds[2]}
                  on:change={(event) =>
                    updateComponent("Trigger", {
                      ...trigger,
                      bounds: [
                        bounds[0],
                        bounds[1],
                        Number(event.currentTarget.value),
                        bounds[3],
                      ],
                    })}
                /></label
              >
              <label
                >Height <input
                  type="number"
                  value={bounds[3]}
                  on:change={(event) =>
                    updateComponent("Trigger", {
                      ...trigger,
                      bounds: [
                        bounds[0],
                        bounds[1],
                        bounds[2],
                        Number(event.currentTarget.value),
                      ],
                    })}
                /></label
              >
              <label
                ><input
                  type="checkbox"
                  checked={Boolean(trigger.oneShot)}
                  on:change={(event) =>
                    updateComponent("Trigger", {
                      ...trigger,
                      oneShot: event.currentTarget.checked,
                    })}
                /> One shot</label
              >
              <div class="action-buttons">
                <button
                  on:click={() =>
                    updateTriggerAction({
                      showMessage: { text: "Hello", duration: 2 },
                    })}>showMessage</button
                >
                <button
                  on:click={() =>
                    updateTriggerAction({
                      changeScene: { name: $sceneDecls[0]?.name ?? "" },
                    })}>changeScene</button
                >
                <button
                  on:click={() =>
                    updateTriggerAction({
                      setFlag: { name: "flag", value: true },
                    })}>setFlag</button
                >
                <button
                  on:click={() => updateTriggerAction({ startDialogue: {} })}
                  >startDialogue</button
                >
              </div>
              {#if isStartDialogueAction(trigger.action)}
                <label
                  >Dialogue
                  <select
                    value={startDialogueId(trigger.action)}
                    on:change={(event) =>
                      updateStartDialogueId(event.currentTarget.value)}
                  >
                    <option value="">First declared dialogue</option>
                    {#each $dialogueDecls as dialogue}
                      <option value={dialogue.name}>{dialogue.name}</option>
                    {/each}
                  </select>
                </label>
                <label
                  >Dialogue Label <input
                    value={startDialogueLabel(trigger.action)}
                    on:change={(event) =>
                      updateStartDialogueLabel(event.currentTarget.value)}
                  /></label
                >
              {/if}
              <label
                >Action JSON <textarea
                  class="component-json"
                  value={JSON.stringify(trigger.action ?? {}, null, 2)}
                  on:change={(event) =>
                    updateTriggerActionJson(event.currentTarget.value)}
                ></textarea></label
              >
            </fieldset>
          {/if}

          {#if selectedComponentName}
            <button
              class="tool-button"
              on:click={() => removeComponent(selectedComponentName)}
              title={`Remove ${selectedComponentName}`}
              aria-label={`Remove ${selectedComponentName}`}
            >
              <Trash2 size={16} aria-hidden="true" />
              <span>Remove {selectedComponentName}</span>
            </button>
          {/if}
        {/key}
      {:else}
        <p>Select an entity in the scene.</p>
      {/if}
    </section>
    {/if}
  </aside>
