<script lang="ts">
  import {
    FileArchive,
    FilePlus2,
    FolderOpen,
    ImagePlus,
    RotateCcw,
    RotateCw,
    Save,
    Upload,
    Download,
    Play as PlayIcon,
    Square,
  } from "@lucide/svelte";

  import {
    project,
    dirty,
    projectRoot,
    vfs,
    showNewProject,
    diagnostics,
    selectedPath,
    previewRunning,
    canUndo,
    canRedo,
  } from "../lib/stores";

  import {
    chooseProjectFolder,
    openFolder,
    saveFolder,
    loadSample,
    undo,
    redo,
    importZip,
    importAssets,
    exportZip,
    exportWeb,
    play,
    stop,
  } from "../lib/actions";
  import { fatalDiagnostics } from "../lib/project";

  $: dirtyCount = $dirty.size; // We can improve hasUnsavedEditorBuffer check later
  $: fatalCount = fatalDiagnostics($diagnostics).length;
</script>

<header class="command-bar">
  <div class="brand">
    <strong>Aerie</strong>
    <span
      >{$project?.title ?? "No project"}{dirtyCount
        ? ` - ${dirtyCount} unsaved`
        : ""}</span
    >
  </div>
  <div class="path-tools">
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
      class="tool-button"
      on:click={openFolder}
      title="Open folder"
      aria-label="Open folder"
    >
      <Upload size={16} aria-hidden="true" />
      <span>Open</span>
    </button>
    <button
      class="tool-button"
      on:click={saveFolder}
      disabled={$vfs.size === 0}
      title="Save project"
      aria-label="Save project"
    >
      <Save size={16} aria-hidden="true" />
      <span>Save</span>
    </button>
  </div>
  <div class="toolbar">
    <button
      class="tool-button"
      on:click={() => ($showNewProject = true)}
      title="New project"
      aria-label="New project"
    >
      <FilePlus2 size={16} aria-hidden="true" />
      <span>New Project</span>
    </button>
    <button
      class="tool-button"
      on:click={loadSample}
      title="Load reference"
      aria-label="Load reference"
    >
      <FolderOpen size={16} aria-hidden="true" />
      <span>Reference</span>
    </button>
    <button
      class="icon-button"
      on:click={undo}
      disabled={!$canUndo}
      title="Undo"
      aria-label="Undo"
    >
      <RotateCcw size={16} aria-hidden="true" />
    </button>
    <button
      class="icon-button"
      on:click={redo}
      disabled={!$canRedo}
      title="Redo"
      aria-label="Redo"
    >
      <RotateCw size={16} aria-hidden="true" />
    </button>
    <label
      class="file-button tool-button"
      title="Import zip"
      aria-label="Import zip"
    >
      <FileArchive size={16} aria-hidden="true" />
      <span>Import Zip</span>
      <input type="file" accept=".zip,application/zip" on:change={importZip} />
    </label>
    <label
      class="file-button tool-button"
      title="Import assets"
      aria-label="Import assets"
    >
      <ImagePlus size={16} aria-hidden="true" />
      <span>Assets</span>
      <input
        type="file"
        accept="image/png,image/jpeg"
        multiple
        on:change={importAssets}
      />
    </label>
    <button
      class="tool-button"
      on:click={exportZip}
      disabled={$vfs.size === 0}
      title="Export source project"
      aria-label="Export source project"
    >
      <Download size={16} aria-hidden="true" />
      <span>Source</span>
    </button>
    <button
      class="tool-button"
      on:click={exportWeb}
      disabled={$vfs.size === 0 || fatalCount > 0}
      title="Export playable web game"
      aria-label="Export playable web game"
    >
      <Download size={16} aria-hidden="true" />
      <span>Web Game</span>
    </button>
    <button
      class="icon-button"
      on:click={play}
      disabled={$vfs.size === 0 || fatalCount > 0 || $previewRunning}
      title="Play"
      aria-label="Play"
    >
      <PlayIcon size={16} aria-hidden="true" />
    </button>
    <button
      class="icon-button"
      on:click={stop}
      disabled={!$previewRunning}
      title="Stop"
      aria-label="Stop"
    >
      <Square size={16} aria-hidden="true" />
    </button>
  </div>
</header>
