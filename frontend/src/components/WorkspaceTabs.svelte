<script lang="ts">
  import { activeMainTab, dialogueDecls, selectedPath, status } from '../lib/stores';
  import { selectFile, openScriptTab } from '../lib/actions';
</script>

<div class="tab-bar">
  <button
    class:active={$activeMainTab === "scene"}
    on:click={() => ($activeMainTab = "scene")}>Scene</button
  >
  <button class:active={$activeMainTab === "script"} on:click={openScriptTab}
    >Script</button
  >
  <button
    class:active={$activeMainTab === "dialogue"}
    on:click={() => {
        if ($selectedPath.endsWith(".json") && $selectedPath.includes("dialogues")) {
          $activeMainTab = "dialogue";
        } else {
          selectFile($dialogueDecls[0]?.path ?? $selectedPath, "dialogue");
        }
      }}
    >Dialogue</button
  >
  <button
    class:active={$activeMainTab === "settings"}
    on:click={() => ($activeMainTab = "settings")}>Project</button
  >
  <button
    class:active={$activeMainTab === "raw"}
    on:click={() => ($activeMainTab = "raw")}>Raw</button
  >
  <span>{$status}</span>
</div>
