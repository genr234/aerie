<script lang="ts">
  import {
    ArrowLeft,
    ImagePlus,
    RotateCcw,
    RotateCw,
    Save,
    Download,
    Play as PlayIcon,
    Square,
  } from "@lucide/svelte";

  import {
    project,
    dirty,
    vfs,
    diagnostics,
    previewRunning,
    canUndo,
    canRedo,
  } from "../lib/stores";

  import {
    saveFolder,
    undo,
    redo,
    importAssets,
    exportZip,
    exportWeb,
    play,
    stop,
    closeProjectToProjects,
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
  <div class="toolbar">
    <button
      class="tool-button"
      on:click={closeProjectToProjects}
      title="Projects"
      aria-label="Projects"
    >
      <ArrowLeft size={16} aria-hidden="true" />
      <span>Projects</span>
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
