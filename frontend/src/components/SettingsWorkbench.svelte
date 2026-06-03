<script lang="ts">
  import { project, selectedPath } from "../lib/stores";
  import { updateProjectField, updateWindowField, selectScene, selectFile } from "../lib/actions";
</script>

<div class="settings-grid">
  <label>Project Title <input value={$project?.title ?? ""} on:change={(e) => updateProjectField("title", e.currentTarget.value)} /></label>
  <label>Project ID <input value={$project?.id ?? ""} on:change={(e) => updateProjectField("id", e.currentTarget.value)} /></label>
  <label>Version <input value={$project?.version ?? ""} on:change={(e) => updateProjectField("version", e.currentTarget.value)} /></label>
  <label>Start Scene
    <select value={$project?.start_scene ?? ""} on:change={(e) => updateProjectField("start_scene", e.currentTarget.value)}>
      {#each $project?.scenes ?? [] as scene}
        <option value={scene.name}>{scene.name}</option>
      {/each}
    </select>
  </label>
  <label>Window Title <input value={$project?.window?.title ?? ""} on:change={(e) => updateWindowField("title", e.currentTarget.value)} /></label>
  <label>Window Width <input type="number" value={$project?.window?.width ?? 800} on:change={(e) => updateWindowField("width", e.currentTarget.value)} /></label>
  <label>Window Height <input type="number" value={$project?.window?.height ?? 450} on:change={(e) => updateWindowField("height", e.currentTarget.value)} /></label>
</div>
