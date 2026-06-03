<script lang="ts">
  import { X } from "@lucide/svelte";
  import {
    showNewProject, newProjectTitle, newProjectId, newProjectTemplate,
    showCreateScene, newSceneName,
    showCreateScript, newScriptName,
    showCreateDialogue, newDialogueName
  } from "../lib/stores";
  import {
    createNewProject, createScene, createScript, createDialogue, slugify
  } from "../lib/actions";
</script>

{#if $showNewProject}
  <div class="modal-backdrop" role="presentation">
    <section class="modal" aria-label="New project">
      <div class="panel-title">
        <h2>New Project</h2>
        <button
          class="icon-button"
          on:click={() => ($showNewProject = false)}
          title="Close"
          aria-label="Close"><X size={16} aria-hidden="true" /></button
        >
      </div>
      <label
        >Title
        <input
          bind:value={$newProjectTitle}
          on:input={() => ($newProjectId = slugify($newProjectTitle))}
        />
      </label>
      <label
        >Project ID
        <input bind:value={$newProjectId} />
      </label>
      <label
        >Template
        <select bind:value={$newProjectTemplate}>
          <option value="tiny">Tiny Story</option>
          <option value="choice">Dialogue Choice</option>
          <option value="two-room">Two-Room Adventure</option>
          <option value="blank">Blank Scene</option>
        </select>
      </label>
      <div class="modal-actions">
        <button on:click={() => ($showNewProject = false)}>Cancel</button>
        <button class="primary" on:click={createNewProject}>Create</button>
      </div>
    </section>
  </div>
{/if}

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
