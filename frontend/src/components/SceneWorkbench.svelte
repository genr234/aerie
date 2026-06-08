<script lang="ts">
  import { vfs, selectedPath, sceneDecls } from "../lib/stores";
  import { parseScene } from "../lib/project";
  import SceneOutliner from "./SceneOutliner.svelte";
  import SceneToolbar from "./SceneToolbar.svelte";
  import SceneViewport from "./SceneViewport.svelte";
  import SceneInspectorPanel from "./SceneInspectorPanel.svelte";

  let isDeclaredScene = $derived($sceneDecls.some((scene) => scene.path === $selectedPath));
  let selectedScene = $derived(isDeclaredScene ? parseScene($vfs, $selectedPath).scene : undefined);
</script>

<div class="scene-workbench">
  {#if selectedScene}
    <SceneToolbar scene={selectedScene} scenePath={$selectedPath} />
    <div class="scene-editor-grid">
      <SceneOutliner scene={selectedScene} scenePath={$selectedPath} />
      <SceneViewport scene={selectedScene} scenePath={$selectedPath} />
      <SceneInspectorPanel scene={selectedScene} scenePath={$selectedPath} />
    </div>
  {:else}
    <div class="empty-state">
      <div>
        <p>Select a scene to edit, or create a new one.</p>
        <p class="hint">Use File / New Scene or click a scene in the sidebar.</p>
      </div>
    </div>
  {/if}
</div>
