<script lang="ts">
  import { onDestroy } from "svelte";
  import { selectedPath, vfs } from "../lib/stores";

  let objectUrl = "";
  let lastPath = "";
  let lastFile: unknown;

  $: file = $vfs.get($selectedPath);

  $: {
    if (lastPath !== $selectedPath || lastFile !== file) {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      objectUrl = "";
      lastPath = $selectedPath;
      lastFile = file;

      if (file?.kind === "binary" && file.bytes) {
        const lower = $selectedPath.toLowerCase();
        const mime = lower.endsWith(".jpg") || lower.endsWith(".jpeg")
          ? "image/jpeg"
          : "image/png";
        const bytes = Uint8Array.from(file.bytes);
        objectUrl = URL.createObjectURL(new Blob([bytes], { type: mime }));
      }
    }
  }

  onDestroy(() => {
    if (objectUrl) URL.revokeObjectURL(objectUrl);
  });
</script>

<div class="asset-preview">
  {#if objectUrl}
    <img src={objectUrl} alt={$selectedPath} />
  {:else}
    <div class="empty-state">No image selected.</div>
  {/if}
  <div class="asset-actions">
    <label>
      File
      <input value={$selectedPath} readonly />
    </label>
  </div>
</div>
