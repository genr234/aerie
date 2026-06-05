<script lang="ts">
  import { createEventDispatcher } from "svelte";
  import { ChevronUp, ChevronDown, Copy } from "@lucide/svelte";
  import { activeBottomTab, diagnostics, output, runtimeProblems } from "../lib/stores";
  import { repairDiagnostic, selectFile } from "../lib/actions";
  import type { Diagnostic } from "../lib/types";

  export let collapsed = false;
  const dispatch = createEventDispatcher<{ toggleCollapse: void }>();

  function navigateDiagnostic(diagnostic: Diagnostic) {
    selectFile(
      diagnostic.path,
      diagnostic.path.endsWith(".json") ? "scene" : "raw",
    );
  }

  async function copyText(text: string) {
    await navigator.clipboard?.writeText(text);
  }

  function problemText(problem: { severity: string; source: string; message: string }) {
    return `[${problem.severity}] ${problem.source}: ${problem.message}`;
  }

  function allProblemsText() {
    return $runtimeProblems.map(problemText).join("\n");
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
      {#if $diagnostics.length === 0}
        <p>No diagnostics.</p>
      {:else}
        {#each $diagnostics as diagnostic}
          <div
            class="diagnostic-row"
            class:diag-error={diagnostic.severity === "error"}
            class:diag-warning={diagnostic.severity === "warning"}
          >
            <button on:click={() => navigateDiagnostic(diagnostic)}>
              <strong>{diagnostic.severity}</strong>: {diagnostic.message} ({diagnostic.path})
            </button>
            <button class="mini-repair" on:click={() => repairDiagnostic(diagnostic)}>Repair</button>
          </div>
        {/each}
      {/if}
    </div>
  {:else if $activeBottomTab === "problems"}
    <div class="problems">
      {#if $runtimeProblems.length === 0}
        <p>No problems.</p>
      {:else}
        <div class="problems-toolbar">
          <span>{$runtimeProblems.length} problem{$runtimeProblems.length === 1 ? "" : "s"}</span>
          <button class="mini-repair" on:click={() => copyText(allProblemsText())}>
            <Copy size={13} /> Copy all
          </button>
        </div>
        {#each $runtimeProblems as problem}
          <div
            class="problem-row"
            class:diag-error={problem.severity === "error"}
            class:diag-warning={problem.severity === "warning"}
          >
            <div class="problem-body">
              <strong>{problem.severity}</strong>
              <span>{problem.source}</span>
              <code>{problem.message}</code>
            </div>
            <button class="mini-repair" title="Copy problem" aria-label="Copy problem" on:click={() => copyText(problemText(problem))}>
              <Copy size={13} />
            </button>
          </div>
        {/each}
      {/if}
    </div>
  {/if}
  {/if}
</footer>
