<script lang="ts">
  import CodeEditor from "./CodeEditor.svelte";
  import { rawText, selectedPath } from "../lib/stores";
  import { updateScript } from "../lib/actions";
</script>

<div class="script-workbench">
  <section>
    <div class="panel-title">
      <h2>Script Editor: {$selectedPath}</h2>
      <div class="panel-actions">
        <button class="primary" on:click={() => updateScript($rawText)}>Save</button>
      </div>
    </div>
    <CodeEditor
      value={$rawText}
      path={$selectedPath}
      on:change={(e) => ($rawText = e.detail)}
      on:save={() => updateScript($rawText)}
    />
  </section>
</div>
