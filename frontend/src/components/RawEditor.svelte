<script lang="ts">
  import { vfs, selectedPath, rawText } from "../lib/stores";
  import { saveRaw, selectFile } from "../lib/actions";
</script>

<div class="raw-editor">
  <div class="panel-title">
    <h2>Raw File</h2>
    <div class="panel-actions">
      <button
        class="primary"
        on:click={saveRaw}
        disabled={!$vfs.get($selectedPath) || $vfs.get($selectedPath)?.kind !== "text"}
      >
        Save
      </button>
    </div>
  </div>
  {#if $vfs.get($selectedPath)?.kind === "text"}
    <textarea
      class="code-textarea"
      bind:value={$rawText}
      on:keydown|stopPropagation
    ></textarea>
  {:else if $selectedPath}
    <div class="binary-state">Selected file is binary.</div>
  {:else}
    <div class="empty-state">No file selected.</div>
  {/if}
</div>
