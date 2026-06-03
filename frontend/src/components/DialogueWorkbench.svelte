<script lang="ts">
  import {
    AlignHorizontalDistributeCenter,
    Copy,
    FilePlus2,
    GitBranch,
    Home,
    LocateFixed,
    MousePointer2,
    Plus,
    Route,
    Trash2,
    ZoomIn,
    ZoomOut,
  } from "@lucide/svelte";
  import { selectedPath, dialogueDecls, status, vfs } from "../lib/stores";
  import {
    addDialogueChoice,
    addDialogueNode,
    autoLayoutCurrentDialogue,
    deleteDialogueChoice,
    deleteDialogueNode,
    duplicateDialogueNode,
    setDialogueAction,
    setDialogueStartNode,
    updateDialogueChoice,
    updateDialogueChoiceNext,
    updateDialogueField,
    updateDialogueNode,
    updateDialogueNodeNext,
    updateDialogueNodePosition,
  } from "../lib/actions";
  import {
    dialogueLinks,
    dialoguePositions,
    validateDialogueGraph,
    type DialogueGraphIssue,
    type DialogueGraphLink,
  } from "../lib/dialogueGraph";
  import { parseDialogue } from "../lib/project";
  import type {
    DialogueDocument,
    DialogueNode,
    DialogueNodePosition,
  } from "../lib/types";

  const NODE_WIDTH = 260;
  const NODE_HEADER_Y = 50;
  const NEXT_OUTPUT_Y = 86;
  const CHOICE_OUTPUT_START_Y = 128;
  const CHOICE_OUTPUT_GAP = 30;
  const MIN_ZOOM = 0.45;
  const MAX_ZOOM = 1.8;

  let selectedNodeId = "";
  let canvasEl: HTMLElement | undefined;
  let view = { x: 24, y: 24, scale: 1 };
  let draggingNode:
    | {
        id: string;
        startClientX: number;
        startClientY: number;
        startX: number;
        startY: number;
      }
    | undefined;
  let panning:
    | {
        startClientX: number;
        startClientY: number;
        startX: number;
        startY: number;
      }
    | undefined;
  let tempPositions: Record<string, DialogueNodePosition> = {};
  let connecting:
    | { fromId: string; kind: "next"; nodeIndex: number }
    | { fromId: string; kind: "choice"; nodeIndex: number; choiceIndex: number }
    | undefined;

  $: isDeclaredDialogue = $dialogueDecls.some(
    (dialogue) => dialogue.path === $selectedPath,
  );
  $: selectedDialogue = isDeclaredDialogue
    ? parseDialogue($vfs, $selectedPath).dialogue
    : undefined;
  $: nodes = selectedDialogue?.nodes ?? [];
  $: selectedNode =
    nodes.find((node) => node.id === selectedNodeId) ?? nodes[0];
  $: selectedIndex = selectedNode
    ? nodes.findIndex((node) => node.id === selectedNode.id)
    : -1;
  $: if (
    selectedDialogue &&
    (!selectedNodeId || !nodes.some((node) => node.id === selectedNodeId))
  ) {
    selectedNodeId = selectedDialogue.start ?? nodes[0]?.id ?? "";
  }
  $: graphIssues = selectedDialogue
    ? validateDialogueGraph(selectedDialogue)
    : [];
  $: links = selectedDialogue ? dialogueLinks(selectedDialogue) : [];

  function positionOf(
    dialogue: DialogueDocument,
    id: string,
  ): DialogueNodePosition {
    return (
      tempPositions[id] ?? dialoguePositions(dialogue)[id] ?? { x: 40, y: 40 }
    );
  }

  function nodeHeight(node: DialogueNode) {
    return 132 + Math.max(1, node.choices?.length ?? 0) * 30;
  }

  function nodeIssues(nodeId: string) {
    return graphIssues.filter((issue) => issue.nodeId === nodeId);
  }

  function hasError(nodeId: string) {
    return nodeIssues(nodeId).some((issue) => issue.severity === "error");
  }

  function hasWarning(nodeId: string) {
    return nodeIssues(nodeId).some((issue) => issue.severity === "warning");
  }

  function linkPath(dialogue: DialogueDocument, link: DialogueGraphLink) {
    const fromNode = dialogue.nodes.find((node) => node.id === link.from);
    if (!fromNode) return "";
    const from = positionOf(dialogue, link.from);
    const to = positionOf(dialogue, link.to);
    const outputY =
      link.kind === "choice" && link.choiceIndex !== undefined
        ? CHOICE_OUTPUT_START_Y + link.choiceIndex * CHOICE_OUTPUT_GAP
        : NEXT_OUTPUT_Y;
    const x1 = from.x + NODE_WIDTH;
    const y1 = from.y + outputY;
    const x2 = to.x;
    const y2 = to.y + NODE_HEADER_Y;
    const bend = Math.max(80, Math.abs(x2 - x1) * 0.45);
    return `M ${x1} ${y1} C ${x1 + bend} ${y1}, ${x2 - bend} ${y2}, ${x2} ${y2}`;
  }

  function isBrokenLink(link: DialogueGraphLink) {
    return selectedDialogue
      ? !selectedDialogue.nodes.some((node) => node.id === link.to)
      : false;
  }

  function startNodeDrag(event: PointerEvent, id: string) {
    if (event.button !== 0 || !selectedDialogue) return;
    const pos = positionOf(selectedDialogue, id);
    draggingNode = {
      id,
      startClientX: event.clientX,
      startClientY: event.clientY,
      startX: pos.x,
      startY: pos.y,
    };
    selectedNodeId = id;
    event.stopPropagation();
  }

  function startPan(event: PointerEvent) {
    if (event.button !== 0) return;
    panning = {
      startClientX: event.clientX,
      startClientY: event.clientY,
      startX: view.x,
      startY: view.y,
    };
  }

  function handlePointerMove(event: PointerEvent) {
    if (draggingNode) {
      const next = {
        x:
          draggingNode.startX +
          (event.clientX - draggingNode.startClientX) / view.scale,
        y:
          draggingNode.startY +
          (event.clientY - draggingNode.startClientY) / view.scale,
      };
      tempPositions = { ...tempPositions, [draggingNode.id]: next };
      return;
    }
    if (panning) {
      view = {
        ...view,
        x: panning.startX + event.clientX - panning.startClientX,
        y: panning.startY + event.clientY - panning.startClientY,
      };
    }
  }

  function handlePointerUp() {
    if (draggingNode && selectedDialogue) {
      const position =
        tempPositions[draggingNode.id] ??
        positionOf(selectedDialogue, draggingNode.id);
      updateDialogueNodePosition(draggingNode.id, position);
      const { [draggingNode.id]: _removed, ...rest } = tempPositions;
      tempPositions = rest;
    }
    draggingNode = undefined;
    panning = undefined;
  }

  function zoomBy(delta: number) {
    view = { ...view, scale: clamp(view.scale + delta, MIN_ZOOM, MAX_ZOOM) };
  }

  function handleWheel(event: WheelEvent) {
    const scale = clamp(
      view.scale * (event.deltaY > 0 ? 0.9 : 1.1),
      MIN_ZOOM,
      MAX_ZOOM,
    );
    view = { ...view, scale };
  }

  function fitView() {
    if (!selectedDialogue || !canvasEl || selectedDialogue.nodes.length === 0)
      return;
    const positions = selectedDialogue.nodes.map((node) => {
      const pos = positionOf(selectedDialogue, node.id);
      return { ...pos, height: nodeHeight(node) };
    });
    const minX = Math.min(...positions.map((pos) => pos.x));
    const minY = Math.min(...positions.map((pos) => pos.y));
    const maxX = Math.max(...positions.map((pos) => pos.x + NODE_WIDTH));
    const maxY = Math.max(...positions.map((pos) => pos.y + pos.height));
    const rect = canvasEl.getBoundingClientRect();
    const scale = clamp(
      Math.min(
        (rect.width - 80) / Math.max(1, maxX - minX),
        (rect.height - 80) / Math.max(1, maxY - minY),
      ),
      MIN_ZOOM,
      1.15,
    );
    view = { scale, x: 40 - minX * scale, y: 40 - minY * scale };
  }

  function autoLayoutAndFit() {
    autoLayoutCurrentDialogue();
    tempPositions = {};
    requestAnimationFrame(fitView);
  }

  function createNode() {
    const id = addDialogueNode();
    if (id) selectedNodeId = id;
  }

  function duplicateSelectedNode() {
    if (selectedIndex < 0) return;
    const id = duplicateDialogueNode(selectedIndex);
    if (id) selectedNodeId = id;
  }

  function deleteSelectedNode() {
    if (selectedIndex < 0) return;
    deleteDialogueNode(selectedIndex);
    selectedNodeId = nodes[Math.max(0, selectedIndex - 1)]?.id ?? "";
  }

  function connectTo(targetId: string) {
    if (!connecting) return;
    if (connecting.kind === "next")
      updateDialogueNodeNext(connecting.nodeIndex, targetId);
    else
      updateDialogueChoiceNext(
        connecting.nodeIndex,
        connecting.choiceIndex,
        targetId,
      );
    connecting = undefined;
  }

  function nodeTargetOptions(current?: string) {
    const options = [
      { id: "", label: "End dialogue" },
      ...nodes.map((node) => ({ id: node.id, label: node.id })),
    ];
    if (current && !options.some((option) => option.id === current))
      options.push({ id: current, label: `${current} (missing)` });
    return options;
  }

  function updateActionsFromText(index: number, text: string) {
    try {
      const parsed = text.trim() ? JSON.parse(text) : [];
      if (!Array.isArray(parsed))
        throw new Error("Actions must be a JSON array.");
      setDialogueAction(index, parsed);
    } catch (error) {
      status.set(error instanceof Error ? error.message : String(error));
    }
  }

  function issueClass(issue: DialogueGraphIssue) {
    return `graph-problem graph-problem-${issue.severity}`;
  }

  function selectNodeFromKeyboard(event: KeyboardEvent, id: string) {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    selectedNodeId = id;
  }

  function clamp(value: number, min: number, max: number) {
    return Math.max(min, Math.min(max, value));
  }
</script>

<div class="dialogue-workbench">
  {#if selectedDialogue}
    <div class="dialogue-toolbar">
      <div class="dialogue-title">
        <h2>{selectedDialogue.id}</h2>
        <span>{nodes.length} node{nodes.length === 1 ? "" : "s"}</span>
      </div>
      <div class="dialogue-tools">
        <button class="tool-button primary" on:click={createNode}
          ><FilePlus2 size={16} /> Node</button
        >
        <button
          class="icon-button"
          title="Duplicate node"
          disabled={selectedIndex < 0}
          on:click={duplicateSelectedNode}><Copy size={16} /></button
        >
        <button
          class="icon-button"
          title="Delete node"
          disabled={selectedIndex < 0}
          on:click={deleteSelectedNode}><Trash2 size={16} /></button
        >
        <button
          class="icon-button"
          title="Auto layout"
          on:click={autoLayoutAndFit}
          ><AlignHorizontalDistributeCenter size={16} /></button
        >
        <button class="icon-button" title="Fit graph" on:click={fitView}
          ><LocateFixed size={16} /></button
        >
        <button
          class="icon-button"
          title="Zoom out"
          on:click={() => zoomBy(-0.1)}><ZoomOut size={16} /></button
        >
        <button class="icon-button" title="Zoom in" on:click={() => zoomBy(0.1)}
          ><ZoomIn size={16} /></button
        >
      </div>
    </div>

    <div class="dialogue-graph-layout">
      <section
        class="dialogue-graph-canvas"
        role="application"
        aria-label="Dialogue graph canvas"
        bind:this={canvasEl}
        on:pointerdown={startPan}
        on:pointermove={handlePointerMove}
        on:pointerup={handlePointerUp}
        on:pointerleave={handlePointerUp}
        on:wheel|preventDefault={handleWheel}
      >
        <div class="dialogue-graph-status">
          <MousePointer2 size={15} />
          {#if connecting}
            <span>Choose a target node</span>
          {:else}
            <span>{Math.round(view.scale * 100)}%</span>
          {/if}
        </div>

        <div
          class="dialogue-graph-world"
          style={`transform: translate(${view.x}px, ${view.y}px) scale(${view.scale});`}
        >
          <svg
            class="dialogue-link-layer"
            width="4000"
            height="3000"
            viewBox="0 0 4000 3000"
            aria-hidden="true"
          >
            {#each links as link}
              {#if !isBrokenLink(link)}
                <path
                  class:choice-link={link.kind === "choice"}
                  class:next-link={link.kind === "next"}
                  d={linkPath(selectedDialogue, link)}
                />
              {/if}
            {/each}
          </svg>

          {#each nodes as node, index (node.id)}
            {@const pos = positionOf(selectedDialogue, node.id)}
            <div
              class="dialogue-graph-node"
              role="button"
              tabindex="0"
              class:selected={selectedNodeId === node.id}
              class:start-node={selectedDialogue.start === node.id}
              class:node-error={hasError(node.id)}
              class:node-warning={hasWarning(node.id)}
              style={`left: ${pos.x}px; top: ${pos.y}px; width: ${NODE_WIDTH}px; min-height: ${nodeHeight(node)}px;`}
              on:pointerdown={(event) => startNodeDrag(event, node.id)}
              on:click={() => (selectedNodeId = node.id)}
              on:keydown={(event) => selectNodeFromKeyboard(event, node.id)}
            >
              <button
                class="node-input-port"
                class:armed={Boolean(connecting)}
                title="Connect to this node"
                on:pointerdown|stopPropagation
                on:click|stopPropagation={() => connectTo(node.id)}
              >
              </button>
              <div class="node-card-header">
                <strong>{node.id}</strong>
                {#if selectedDialogue.start === node.id}
                  <span>Start</span>
                {/if}
              </div>
              <div class="node-card-speaker">{node.speaker || "Narrator"}</div>
              <p>{node.text || "No dialogue text."}</p>
              <div class="node-card-meta">
                {#if node.when}<span>when {node.when}</span>{/if}
                {#if node.actions?.length}<span
                    >{node.actions.length} action{node.actions.length === 1
                      ? ""
                      : "s"}</span
                  >{/if}
              </div>
              <div class="node-outputs">
                <button
                  title="Connect continue"
                  on:pointerdown|stopPropagation
                  on:click|stopPropagation={() =>
                    (connecting = {
                      fromId: node.id,
                      kind: "next",
                      nodeIndex: index,
                    })}
                >
                  <Route size={13} />
                  <span>{node.next || "End"}</span>
                </button>
                {#each node.choices ?? [] as choice, choiceIndex}
                  <button
                    class="choice-output"
                    title="Connect choice"
                    on:pointerdown|stopPropagation
                    on:click|stopPropagation={() =>
                      (connecting = {
                        fromId: node.id,
                        kind: "choice",
                        nodeIndex: index,
                        choiceIndex,
                      })}
                  >
                    <GitBranch size={13} />
                    <span
                      >{choice.text || "Choice"} → {choice.next || "End"}</span
                    >
                  </button>
                {/each}
              </div>
            </div>
          {/each}
        </div>
      </section>

      <aside class="dialogue-detail-panel">
        <section>
          <h2>Dialogue</h2>
          <label
            >ID <input
              value={selectedDialogue.id}
              on:change={(event) =>
                updateDialogueField("id", event.currentTarget.value)}
            /></label
          >
          <label
            >Start
            <select
              value={selectedDialogue.start ?? nodes[0]?.id ?? ""}
              on:change={(event) =>
                setDialogueStartNode(event.currentTarget.value)}
            >
              {#each nodes as node}
                <option value={node.id}>{node.id}</option>
              {/each}
            </select>
          </label>
        </section>

        {#if selectedNode && selectedIndex >= 0}
          <section>
            <div class="detail-heading">
              <h2>Node</h2>
              <button
                class="icon-button"
                title="Mark as start"
                on:click={() => setDialogueStartNode(selectedNode.id)}
                ><Home size={15} /></button
              >
            </div>
            <label
              >ID <input
                value={selectedNode.id}
                on:change={(event) => (
                  (selectedNodeId = event.currentTarget.value),
                  updateDialogueNode(selectedIndex, {
                    id: event.currentTarget.value,
                  })
                )}
              /></label
            >
            <label
              >Speaker <input
                value={selectedNode.speaker ?? ""}
                on:change={(event) =>
                  updateDialogueNode(selectedIndex, {
                    speaker: event.currentTarget.value || undefined,
                  })}
              /></label
            >
            <label
              >Text <textarea
                class="dialogue-textarea"
                value={selectedNode.text ?? ""}
                on:change={(event) =>
                  updateDialogueNode(selectedIndex, {
                    text: event.currentTarget.value,
                  })}
              ></textarea></label
            >
            <label
              >Condition <input
                value={selectedNode.when ?? ""}
                placeholder="flag_name or score >= 2"
                on:change={(event) =>
                  updateDialogueNode(selectedIndex, {
                    when: event.currentTarget.value || undefined,
                  })}
              /></label
            >
            <label
              >Continue
              <select
                value={selectedNode.next ?? ""}
                on:change={(event) =>
                  updateDialogueNodeNext(
                    selectedIndex,
                    event.currentTarget.value,
                  )}
              >
                {#each nodeTargetOptions(selectedNode.next) as option}
                  <option value={option.id}>{option.label}</option>
                {/each}
              </select>
            </label>
            <label
              >Actions JSON
              <textarea
                class="actions-json"
                value={JSON.stringify(selectedNode.actions ?? [], null, 2)}
                on:change={(event) =>
                  updateActionsFromText(
                    selectedIndex,
                    event.currentTarget.value,
                  )}
              ></textarea>
            </label>
          </section>

          <section>
            <div class="detail-heading">
              <h2>Choices</h2>
              <button
                class="icon-button"
                title="Add choice"
                on:click={() => addDialogueChoice(selectedIndex)}
                ><Plus size={15} /></button
              >
            </div>
            {#if selectedNode.choices?.length}
              {#each selectedNode.choices as choice, choiceIndex}
                <div class="choice-editor">
                  <input
                    value={choice.text}
                    on:change={(event) =>
                      updateDialogueChoice(selectedIndex, choiceIndex, {
                        text: event.currentTarget.value,
                      })}
                  />
                  <select
                    value={choice.next ?? ""}
                    on:change={(event) =>
                      updateDialogueChoiceNext(
                        selectedIndex,
                        choiceIndex,
                        event.currentTarget.value,
                      )}
                  >
                    {#each nodeTargetOptions(choice.next) as option}
                      <option value={option.id}>{option.label}</option>
                    {/each}
                  </select>
                  <input
                    value={choice.when ?? ""}
                    placeholder="when"
                    on:change={(event) =>
                      updateDialogueChoice(selectedIndex, choiceIndex, {
                        when: event.currentTarget.value || undefined,
                      })}
                  />
                  <button
                    class="icon-button"
                    title="Delete choice"
                    on:click={() =>
                      deleteDialogueChoice(selectedIndex, choiceIndex)}
                    ><Trash2 size={15} /></button
                  >
                </div>
              {/each}
            {:else}
              <p>No choices.</p>
            {/if}
          </section>
        {/if}

        <section>
          <h2>Problems</h2>
          {#if graphIssues.length === 0}
            <p>No graph problems.</p>
          {:else}
            <div class="graph-problems">
              {#each graphIssues as issue}
                <button
                  class={issueClass(issue)}
                  on:click={() =>
                    issue.nodeId && (selectedNodeId = issue.nodeId)}
                >
                  <strong>{issue.severity}</strong>
                  <span>{issue.message}</span>
                </button>
              {/each}
            </div>
          {/if}
        </section>
      </aside>
    </div>
  {:else}
    <div class="empty-state">Select or create a dialogue to edit.</div>
  {/if}
</div>
