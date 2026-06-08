<script lang="ts">
  import { Eye, EyeOff, Lock, Unlock, Search, Trash2, Copy } from "@lucide/svelte";
  import { hiddenEntities, lockedEntities, selectedEntities, selectedEntitySet } from "../lib/sceneEditor";
  import { deleteEntities, duplicateEntities } from "../lib/actions";
  import { selection } from "../lib/stores";
  import { entityDisplay } from "../lib/sceneEditor";
  import type { SceneDocument } from "../lib/types";

  let { scene, scenePath }: { scene: SceneDocument; scenePath: string } = $props();
  let query = $state("");

  let hidden = $derived(new Set($hiddenEntities[scenePath] ?? []));
  let locked = $derived(new Set($lockedEntities[scenePath] ?? []));
  let rows = $derived(scene.entities.map((entity, index) => ({ entity, index, display: entityDisplay(entity) }))
    .filter((row) => {
      const needle = query.trim().toLowerCase();
      if (!needle) return true;
      return (row.entity.tag ?? `entity ${row.index + 1}`).toLowerCase().includes(needle)
        || row.display.componentNames.some((name) => name.toLowerCase().includes(needle));
    }));

  function choose(index: number, event: MouseEvent) {
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
  }

  function chooseWithKeyboard(index: number, event: KeyboardEvent) {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    selectedEntities.set({ scenePath, indices: [index] });
    selection.set({ type: "entity", scenePath, entityIndex: index });
  }

  function toggleRecord(store: typeof hiddenEntities, index: number) {
    store.update((record) => {
      const next = new Set(record[scenePath] ?? []);
      if (next.has(index)) next.delete(index);
      else next.add(index);
      return { ...record, [scenePath]: [...next] };
    });
  }

  function selectedOr(index: number) {
    return $selectedEntities?.scenePath === scenePath && $selectedEntities.indices.length > 0 ? $selectedEntities.indices : [index];
  }
</script>

<aside class="scene-outliner">
  <header>
    <strong>Entities</strong>
    <span>{scene.entities.length}</span>
  </header>
  <label class="scene-search">
    <Search size={14} aria-hidden="true" />
    <input bind:value={query} placeholder="Search entities" />
  </label>
  <div class="entity-rows">
    {#each rows as row (row.index)}
      <div
        class="entity-row"
        class:selected={$selectedEntitySet.has(row.index)}
        class:hidden={hidden.has(row.index)}
        onclick={(event) => choose(row.index, event)}
        onkeydown={(event) => chooseWithKeyboard(row.index, event)}
        role="button"
        tabindex="0"
      >
        <span class="entity-row-name">{row.entity.tag ?? `Entity ${row.index + 1}`}</span>
        <span class="entity-row-meta">{Math.round(row.display.x)}, {Math.round(row.display.y)}</span>
        <span class="entity-row-badges">
          {#each row.display.componentNames.slice(0, 4) as name}
            <span>{name.replace(/[a-z]/g, "") || name.slice(0, 2)}</span>
          {/each}
        </span>
        <span class="entity-row-actions">
          <button class="mini-icon" title={hidden.has(row.index) ? "Show in editor" : "Hide in editor"} onclick={(event) => { event.stopPropagation(); toggleRecord(hiddenEntities, row.index); }}>
            {#if hidden.has(row.index)}<EyeOff size={13} />{:else}<Eye size={13} />{/if}
          </button>
          <button class="mini-icon" title={locked.has(row.index) ? "Unlock" : "Lock"} onclick={(event) => { event.stopPropagation(); toggleRecord(lockedEntities, row.index); }}>
            {#if locked.has(row.index)}<Lock size={13} />{:else}<Unlock size={13} />{/if}
          </button>
          <button class="mini-icon" title="Duplicate" onclick={(event) => { event.stopPropagation(); duplicateEntities(scenePath, selectedOr(row.index)); }}><Copy size={13} /></button>
          <button class="mini-icon" title="Delete" onclick={(event) => { event.stopPropagation(); deleteEntities(scenePath, selectedOr(row.index)); }}><Trash2 size={13} /></button>
        </span>
      </div>
    {/each}
  </div>
</aside>
