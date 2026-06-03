<script lang="ts">
  import {
    FileArchive,
    FilePlus2,
    FolderOpen,
    Upload,
  } from "@lucide/svelte";

  import {
    newProjectId,
    newProjectTemplate,
    newProjectTitle,
    projectRoot,
    status,
  } from "../lib/stores";
  import {
    chooseProjectFolder,
    createNewProject,
    importZip,
    loadSample,
    openFolder,
    slugify,
  } from "../lib/actions";
</script>

<main class="projects-screen">
  <section class="projects-panel" aria-label="Projects">
    <div class="projects-heading">
      <strong>Aerie</strong>
      <span>Projects</span>
    </div>

    <div class="project-sections">
      <section class="project-section" aria-label="Open project">
        <h2>Open Project</h2>
        <div class="project-folder-row">
          <input placeholder="/path/to/project" bind:value={$projectRoot} />
          <button
            class="tool-button"
            on:click={chooseProjectFolder}
            title="Browse"
            aria-label="Browse"
          >
            <FolderOpen size={16} aria-hidden="true" />
            <span>Browse</span>
          </button>
          <button
            class="tool-button primary"
            on:click={openFolder}
            title="Open folder"
            aria-label="Open folder"
          >
            <Upload size={16} aria-hidden="true" />
            <span>Open</span>
          </button>
        </div>

        <div class="project-actions-row">
          <label
            class="file-button tool-button"
            title="Import zip"
            aria-label="Import zip"
          >
            <FileArchive size={16} aria-hidden="true" />
            <span>Import Zip</span>
            <input type="file" accept=".zip,application/zip" on:change={importZip} />
          </label>
          <button
            class="tool-button"
            on:click={loadSample}
            title="Load reference"
            aria-label="Load reference"
          >
            <FolderOpen size={16} aria-hidden="true" />
            <span>Reference</span>
          </button>
        </div>
      </section>

      <section class="project-section" aria-label="New project">
        <h2>New Project</h2>
        <div class="new-project-grid">
          <label>
            Title
            <input
              bind:value={$newProjectTitle}
              on:input={() => ($newProjectId = slugify($newProjectTitle))}
            />
          </label>
          <label>
            Project ID
            <input bind:value={$newProjectId} />
          </label>
          <label>
            Template
            <select bind:value={$newProjectTemplate}>
              <option value="tiny">Tiny Story</option>
              <option value="choice">Dialogue Choice</option>
              <option value="two-room">Two-Room Adventure</option>
              <option value="blank">Blank Scene</option>
            </select>
          </label>
        </div>
        <button
          class="tool-button primary create-project-button"
          on:click={createNewProject}
          title="Create project"
          aria-label="Create project"
        >
          <FilePlus2 size={16} aria-hidden="true" />
          <span>Create Project</span>
        </button>
      </section>
    </div>

    <p class="project-status">{$status}</p>
  </section>
</main>
