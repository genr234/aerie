<script lang="ts">
  import { X } from "@lucide/svelte";
  import {
    showCreateScene, newSceneName,
    showCreateScript, newScriptName,
    showCreateDialogue, newDialogueName
  } from "../lib/stores";
  import {
    createScene, createScript, createDialogue
  } from "../lib/actions";
</script>

{#if $showCreateScene}
  <div class="modal-backdrop" role="presentation">
    <section class="modal" aria-label="New scene">
      <div class="panel-title">
        <h2>New Scene</h2>
        <button
          class="icon-button"
          on:click={() => ($showCreateScene = false)}
          title="Close"
          aria-label="Close"><X size={16} aria-hidden="true" /></button
        >
      </div>
      <label
        >Name
        <input bind:value={$newSceneName} />
      </label>
      <div class="modal-actions">
        <button on:click={() => ($showCreateScene = false)}>Cancel</button>
        <button class="primary" on:click={createScene}>Create</button>
      </div>
    </section>
  </div>
{/if}

{#if $showCreateScript}
  <div class="modal-backdrop" role="presentation">
    <section class="modal" aria-label="New script">
      <div class="panel-title">
        <h2>New Script</h2>
        <button
          class="icon-button"
          on:click={() => ($showCreateScript = false)}
          title="Close"
          aria-label="Close"><X size={16} aria-hidden="true" /></button
        >
      </div>
      <label
        >Module Name
        <input bind:value={$newScriptName} />
      </label>
      <div class="modal-actions">
        <button on:click={() => ($showCreateScript = false)}>Cancel</button>
        <button class="primary" on:click={createScript}>Create</button>
      </div>
    </section>
  </div>
{/if}

{#if $showCreateDialogue}
  <div class="modal-backdrop" role="presentation">
    <section class="modal" aria-label="New dialogue">
      <div class="panel-title">
        <h2>New Dialogue</h2>
        <button
          class="icon-button"
          on:click={() => ($showCreateDialogue = false)}
          title="Close"
          aria-label="Close"><X size={16} aria-hidden="true" /></button
        >
      </div>
      <label
        >Name
        <input bind:value={$newDialogueName} />
      </label>
      <div class="modal-actions">
        <button on:click={() => ($showCreateDialogue = false)}>Cancel</button>
        <button class="primary" on:click={createDialogue}>Create</button>
      </div>
    </section>
  </div>
{/if}
