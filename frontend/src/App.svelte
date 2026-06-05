<script lang="ts">
  import { onMount } from "svelte";
  import CommandBar from "./components/CommandBar.svelte";
  import Sidebar from "./components/Sidebar.svelte";
  import BottomPanel from "./components/BottomPanel.svelte";
  import Inspector from "./components/Inspector.svelte";
  import Modals from "./components/Modals.svelte";
  import ProjectsScreen from "./components/ProjectsScreen.svelte";

  import SceneWorkbench from "./components/SceneWorkbench.svelte";
  import ScriptWorkbench from "./components/ScriptWorkbench.svelte";
  import DialogueWorkbench from "./components/DialogueWorkbench.svelte";
  import CombatWorkbench from "./components/CombatWorkbench.svelte";
  import SettingsWorkbench from "./components/SettingsWorkbench.svelte";
  import RawEditor from "./components/RawEditor.svelte";
  import AssetWorkbench from "./components/AssetWorkbench.svelte";

  import { listenPreviewLogs } from "./lib/previewRuntime";
  import { problemFromPreviewLog } from "./lib/runtimeDiagnostics";
  import {
    output,
    runtimeProblems,
    activeBottomTab,
    activeMainTab,
    panelCollapsed,
    inspectorCollapsed,
    currentScreen,
  } from "./lib/stores";

  function togglePanel() {
    panelCollapsed.update((v) => !v);
  }

  function toggleInspector() {
    inspectorCollapsed.update((v) => !v);
  }

  function dragMove(event: PointerEvent) {
    // If needed for future node drag mapping
  }

  function endDrag() {
    // If needed for future node drag mapping
  }

  onMount(() => {
    let disposed = false;
    let unlisten: (() => void) | undefined;
    void listenPreviewLogs((log) => {
      output.update((o) => [...o.slice(-300), log]);
      const problem = problemFromPreviewLog(log);
      if (problem) {
        runtimeProblems.update((items) => [...items, problem].slice(-100));
        activeBottomTab.set("problems");
      }
    }).then((cleanup) => {
      if (disposed) cleanup();
      else unlisten = cleanup;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  });
</script>

{#if $currentScreen === "projects"}
  <ProjectsScreen />
{:else}
  <main
    class="editor-shell"
    class:inspector-collapsed={$inspectorCollapsed}
    on:pointermove={dragMove}
    on:pointerup={endDrag}
  >
    <CommandBar />
    <Modals />

    <Sidebar />

    <section class="workspace" class:panel-collapsed={$panelCollapsed}>
      <div class="workbench">
        {#if $activeMainTab === "scene"}
          <SceneWorkbench />
        {:else if $activeMainTab === "script"}
          <ScriptWorkbench />
        {:else if $activeMainTab === "dialogue"}
          <DialogueWorkbench />
        {:else if $activeMainTab === "combat"}
          <CombatWorkbench />
        {:else if $activeMainTab === "settings"}
          <SettingsWorkbench />
        {:else if $activeMainTab === "raw"}
          <RawEditor />
        {:else if $activeMainTab === "asset"}
          <AssetWorkbench />
        {/if}
      </div>

      <BottomPanel collapsed={$panelCollapsed} on:toggleCollapse={togglePanel} />
    </section>

    <Inspector
      collapsed={$inspectorCollapsed}
      on:toggleCollapse={toggleInspector}
    />
  </main>
{/if}
