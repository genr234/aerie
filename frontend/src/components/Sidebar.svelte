<script lang="ts">
  import { Plus, FolderOpen, Folder, File, FileCode, FileJson, Image, ChevronRight } from "@lucide/svelte";
  import {
    project, showCreateScene, showCreateScript, showCreateDialogue,
    selectedPath, dirty, sceneDecls, scriptDecls, dialogueDecls,
    paths
  } from "../lib/stores";
  import { selectScene, selectFile } from "../lib/actions";

  // ---- Tree types ----
  interface TreeNode {
    name: string;
    path: string;
    isFolder: boolean;
    children: TreeNode[];
    depth: number;
  }

  // ---- Build tree from flat paths ----
  function buildTree(sortedPaths: string[]): TreeNode[] {
    const root: TreeNode[] = [];
    const folderMap = new Map<string, TreeNode>();

    for (const path of sortedPaths) {
      const parts = path.split("/");
      let currentPath = "";
      let siblings = root;

      for (let i = 0; i < parts.length; i++) {
        const part = parts[i];
        currentPath = currentPath ? `${currentPath}/${part}` : part;
        const isLast = i === parts.length - 1;

        if (isLast) {
          siblings.push({ name: part, path, isFolder: false, children: [], depth: i });
        } else {
          let folder = folderMap.get(currentPath);
          if (!folder) {
            folder = { name: part, path: currentPath, isFolder: true, children: [], depth: i };
            folderMap.set(currentPath, folder);
            siblings.push(folder);
          }
          siblings = folder.children;
        }
      }
    }

    sortTree(root);
    return root;
  }

  function sortTree(nodes: TreeNode[]) {
    nodes.sort((a, b) => {
      if (a.isFolder !== b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
    for (const node of nodes) {
      if (node.isFolder) sortTree(node.children);
    }
  }

  $: tree = buildTree($paths);

  // ---- Expand / collapse state ----
  let expandedFolders: Set<string> = new Set(["assets"]);

  function toggleFolder(path: string) {
    const next = new Set(expandedFolders);
    if (next.has(path)) {
      next.delete(path);
    } else {
      next.add(path);
    }
    expandedFolders = next;
  }

  function ensureAncestorsExpanded(filePath: string) {
    const parts = filePath.split("/");
    const next = new Set(expandedFolders);
    let changed = false;
    let currentPath = "";
    for (let i = 0; i < parts.length - 1; i++) {
      currentPath = currentPath ? `${currentPath}/${parts[i]}` : parts[i];
      if (!next.has(currentPath)) {
        next.add(currentPath);
        changed = true;
      }
    }
    if (changed) expandedFolders = next;
  }

  // ---- Flatten tree to visible rows ----
  function flattenTree(nodes: TreeNode[], expanded: Set<string>): TreeNode[] {
    const result: TreeNode[] = [];
    for (const node of nodes) {
      result.push(node);
      if (node.isFolder && expanded.has(node.path)) {
        result.push(...flattenTree(node.children, expanded));
      }
    }
    return result;
  }

  $: flatRows = flattenTree(tree, expandedFolders);

  // ---- Icon per file type ----
  function rowIcon(node: TreeNode): typeof Folder {
    if (node.isFolder) {
      return expandedFolders.has(node.path) ? FolderOpen : Folder;
    }
    if (node.path.endsWith(".wren")) return FileCode;
    if (node.path.endsWith(".json")) return FileJson;
    if (/\.(png|jpg|jpeg|gif|svg|webp)$/i.test(node.path)) return Image;
    return File;
  }

  // ---- Click handler ----
  function handleRowClick(node: TreeNode) {
    if (node.isFolder) {
      toggleFolder(node.path);
      return;
    }

    ensureAncestorsExpanded(node.path);

    const s = new Set($sceneDecls.map((d) => d.path));
    const d = new Set($dialogueDecls.map((d) => d.path));
    const sc = new Set($scriptDecls.map((d) => d.path));

    if (s.has(node.path)) {
      selectScene(node.path);
    } else if (sc.has(node.path)) {
      selectFile(node.path, "script");
    } else if (d.has(node.path)) {
      selectFile(node.path, "dialogue");
    } else {
      selectFile(node.path);
    }
  }

  function canCreate() {
    return Boolean($project);
  }
</script>

<aside class="sidebar">
  <div class="sidebar-toolbar">
    <span class="sidebar-title">Explorer</span>
    <div class="sidebar-actions">
      <button class="tool-button" on:click={() => ($showCreateScene = true)} disabled={!canCreate()} title="New scene"><Plus size={14} /><span>Scene</span></button>
      <button class="tool-button" on:click={() => ($showCreateScript = true)} disabled={!canCreate()} title="New script"><Plus size={14} /><span>Script</span></button>
      <button class="tool-button" on:click={() => ($showCreateDialogue = true)} disabled={!canCreate()} title="New dialogue"><Plus size={14} /><span>Dialogue</span></button>
    </div>
  </div>

  <div class="file-tree">
    {#if flatRows.length > 0}
      {#each flatRows as node (node.path)}
        {@const Icon = rowIcon(node)}
        {@const isExpanded = node.isFolder && expandedFolders.has(node.path)}
        <button
          class="tree-row"
          class:active={$selectedPath === node.path}
          class:folder={node.isFolder}
          style="padding-left: {node.depth * 16 + 8}px"
          on:click={() => handleRowClick(node)}
        >
          {#if node.isFolder}
            <span class="tree-chevron" class:expanded={isExpanded}><ChevronRight size={14} /></span>
          {:else}
            <span class="tree-chevron tree-chevron-spacer"></span>
          {/if}
          <span class="tree-icon"><Icon size={16} /></span>
          <span class="tree-name">{$dirty.has(node.path) ? "• " : ""}{node.name}</span>
        </button>
      {/each}
    {:else}
      <div class="tree-empty">
        <p>No files yet.</p>
        <p class="hint">Load the reference project or open a folder to begin.</p>
      </div>
    {/if}
  </div>
</aside>
