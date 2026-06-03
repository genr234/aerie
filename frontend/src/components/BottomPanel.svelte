<script lang="ts">
  import { createEventDispatcher } from "svelte";
  import { ChevronUp, ChevronDown } from "@lucide/svelte";
  import { activeBottomTab, output, runtimeDiagnostics, selectedPath } from "../lib/stores";
  import { selectFile } from "../lib/actions";
  import type { Diagnostic } from "../lib/types";

  export let collapsed = false;
  const dispatch = createEventDispatcher<{ toggleCollapse: void }>();

  function navigateDiagnostic(diagnostic: Diagnostic) {
    selectFile(
      diagnostic.path,
      diagnostic.path.endsWith(".json") ? "scene" : "raw",
    );
  }
</script>

<footer class="bottom-panel">
  <div class="tab-bar compact">
    <button
      class:active={$activeBottomTab === "diagnostics"}
      on:click={() => ($activeBottomTab = "diagnostics")}>Diagnostics</button>
    <button
      class:active={$activeBottomTab === "output"}
      on:click={() => ($activeBottomTab = "output")}>Output</button>
    <button
      class:active={$activeBottomTab === "problems"}
      on:click={() => ($activeBottomTab = "problems")}>Problems</button>
    <button class="collapse-btn" on:click={() => dispatch("toggleCollapse")} title={collapsed ? "Expand panel" : "Collapse panel"}>
      {#if collapsed}
        <ChevronUp size={16} aria-hidden="true" />
      {:else}
        <ChevronDown size={16} aria-hidden="true" />
      {/if}
    </button>
  </div>
  {#if !collapsed}
    {#if $activeBottomTab === "output"}
    <div class="log-list">
      {#each $output as line}
        <p class:error={line.stream === "stderr"}>
          [{line.stream}] {line.line}
        </p>
      {/each}
      {#if $output.length === 0}<p>No runtime output yet.</p>{/if}
    </div>
  {:else if $activeBottomTab === "diagnostics"}
    <div class="diagnostics">
      {#if $runtimeDiagnostics.length === 0}
        <p>No diagnostics.</p>
      {:else}
        {#each $runtimeDiagnostics as diagnostic}
          <button
            class:diag-error={diagnostic.severity === "error"}
            class:diag-warning={diagnostic.severity === "warning"}
            on:click={() => navigateDiagnostic(diagnostic)}
          >
            <strong>{diagnostic.severity}</strong>: {diagnostic.message} ({diagnostic.path})
          </button>
        {/each}
      {/if}
    </div>
  {:else if $activeBottomTab === "problems"}
    <div class="problems log-list">
      <p>No problems.</p>
    </div>
  {/if}
  {/if}
</footer>
