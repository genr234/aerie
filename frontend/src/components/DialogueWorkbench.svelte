<script lang="ts">
  import { FilePlus2, Trash2, ArrowUp, ArrowDown } from "@lucide/svelte";
  import { selectedPath, dialogueDecls } from "../lib/stores";
  import { 
    updateDialogueField, addDialogueNode, deleteDialogueNode,
    moveDialogueNode, addDialogueChoice, updateDialogueChoice, 
    deleteDialogueChoice, updateDialogueNode
  } from "../lib/actions";

  import { parseDialogue } from "../lib/project";
  import { vfs } from "../lib/stores";
  
  $: isDeclaredDialogue = $dialogueDecls.some((dialogue) => dialogue.path === $selectedPath);
  $: selectedDialogue = isDeclaredDialogue
    ? parseDialogue($vfs, $selectedPath).dialogue 
    : undefined;
</script>

<div class="dialogue-workbench">
  {#if selectedDialogue}
    <div class="panel-title">
      <h2>{selectedDialogue.id}</h2>
      <div class="panel-actions">
        <button class="primary" on:click={addDialogueNode}><FilePlus2 size={16} /> Add Node</button>
      </div>
    </div>
    <div class="settings-grid compact-form">
      <label>Dialogue ID <input value={selectedDialogue.id} on:change={(e) => updateDialogueField("id", e.currentTarget.value)} /></label>
      <label>Start Node <input value={selectedDialogue.start} on:change={(e) => updateDialogueField("start", e.currentTarget.value)} /></label>
    </div>
    
    <!-- Render Nodes -->
    {#each selectedDialogue.nodes as node, i}
      <div class="node-panel">
        <div class="node-header">
           <label>ID <input value={node.id} on:change={(e) => updateDialogueNode(i, {id: e.currentTarget.value})} /></label>
           <label>Speaker <input value={node.speaker} on:change={(e) => updateDialogueNode(i, {speaker: e.currentTarget.value})} /></label>
           <!-- Reorder / Delete Node Controls Here... omitted for brevity, map to moveDialogueNode / deleteDialogueNode -->
           <div class="actions">
             <button on:click={() => moveDialogueNode(i, -1)}><ArrowUp size={16}/></button>
             <button on:click={() => moveDialogueNode(i, 1)}><ArrowDown size={16}/></button>
             <button on:click={() => deleteDialogueNode(i)}><Trash2 size={16}/></button>
           </div>
        </div>
        <textarea class="node-text" value={node.text} on:change={(e) => updateDialogueNode(i, {text: e.currentTarget.value})}></textarea>
        <!-- Render Choices -->
        {#if node.choices && node.choices.length > 0}
          <div class="choices-list">
            {#each node.choices as choice, j}
              <div class="choice">
                <input value={choice.text} on:change={(e) => updateDialogueChoice(i, j, { text: e.currentTarget.value })} />
                <span>→</span>
                <input value={choice.next} on:change={(e) => updateDialogueChoice(i, j, { next: e.currentTarget.value })} />
                <button on:click={() => deleteDialogueChoice(i, j)}><Trash2 size={16}/></button>
              </div>
            {/each}
          </div>
        {/if}
        <button on:click={() => addDialogueChoice(i)}>+ Choice</button>
      </div>
    {/each}
  {:else}
    <div class="empty-state">Select or create a dialogue to edit.</div>
  {/if}
</div>
