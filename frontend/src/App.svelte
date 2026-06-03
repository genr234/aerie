<script lang="ts">
  import { onMount } from "svelte";
  import CommandBar from "./components/CommandBar.svelte";
  import Sidebar from "./components/Sidebar.svelte";
  import WorkspaceTabs from "./components/WorkspaceTabs.svelte";
  import BottomPanel from "./components/BottomPanel.svelte";
  import Inspector from "./components/Inspector.svelte";
  import Modals from "./components/Modals.svelte";
  
  import SceneWorkbench from "./components/SceneWorkbench.svelte";
  import ScriptWorkbench from "./components/ScriptWorkbench.svelte";
  import DialogueWorkbench from "./components/DialogueWorkbench.svelte";
  import SettingsWorkbench from "./components/SettingsWorkbench.svelte";
  import RawEditor from "./components/RawEditor.svelte";

  import { listenPreviewLogs } from "./lib/previewRuntime";
  import { output, runtimeDiagnostics, activeBottomTab, activeMainTab, panelCollapsed, inspectorCollapsed } from "./lib/stores";
  import { refreshProject } from "./lib/actions";

  function togglePanel() {
    panelCollapsed.update(v => !v);
  }

  function toggleInspector() {
    inspectorCollapsed.update(v => !v);
  }

  function dragMove(event: PointerEvent) {
    // If needed for future node drag mapping
  }

  function endDrag() {
    // If needed for future node drag mapping
  }

  onMount(() => {
    void listenPreviewLogs((log) => {
      output.update(o => [...o.slice(-300), log]);
    });
  });

</script>

<main class="editor-shell" class:inspector-collapsed={$inspectorCollapsed} on:pointermove={dragMove} on:pointerup={endDrag}>
  <CommandBar />
  <Modals />
  
  <Sidebar />

  <section class="workspace" class:panel-collapsed={$panelCollapsed}>
    <WorkspaceTabs />

    <div class="workbench">
      {#if $activeMainTab === "scene"}
        <SceneWorkbench />
      {:else if $activeMainTab === "script"}
        <ScriptWorkbench />
      {:else if $activeMainTab === "dialogue"}
        <DialogueWorkbench />
      {:else if $activeMainTab === "settings"}
        <SettingsWorkbench />
      {:else if $activeMainTab === "raw"}
        <RawEditor />
      {/if}
    </div>

    <BottomPanel collapsed={$panelCollapsed} on:toggleCollapse={togglePanel} />
  </section>

  <Inspector collapsed={$inspectorCollapsed} on:toggleCollapse={toggleInspector} />
</main>
