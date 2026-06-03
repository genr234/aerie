import type { DialogueChoice, DialogueDocument, DialogueNode, DialogueNodePosition } from "./types";

export type DialogueGraphIssue = {
  severity: "error" | "warning" | "info";
  type: "missing-target" | "duplicate-id" | "missing-start" | "unreachable" | "empty-choice" | "self-link" | "cycle";
  message: string;
  nodeId?: string;
  choiceIndex?: number;
  target?: string;
};

export type DialogueGraphLink = {
  from: string;
  to: string;
  kind: "next" | "choice";
  choiceIndex?: number;
  label?: string;
};

const NODE_WIDTH = 260;
const COLUMN_GAP = 340;
const ROW_GAP = 178;
const UNREACHABLE_Y_GAP = 120;

export function dialogueLinks(dialogue: DialogueDocument): DialogueGraphLink[] {
  const links: DialogueGraphLink[] = [];
  for (const node of dialogue.nodes) {
    if (node.next) links.push({ from: node.id, to: node.next, kind: "next", label: "next" });
    for (const [choiceIndex, choice] of (node.choices ?? []).entries()) {
      if (choice.next) {
        links.push({
          from: node.id,
          to: choice.next,
          kind: "choice",
          choiceIndex,
          label: choice.text || `choice ${choiceIndex + 1}`,
        });
      }
    }
  }
  return links;
}

export function outgoingTargets(node: DialogueNode): string[] {
  return [
    ...(node.next ? [node.next] : []),
    ...(node.choices ?? []).map((choice) => choice.next).filter((target): target is string => Boolean(target)),
  ];
}

export function reachableDialogueNodeIds(dialogue: DialogueDocument): Set<string> {
  const ids = new Set(dialogue.nodes.map((node) => node.id));
  const start = dialogue.start ?? dialogue.nodes[0]?.id;
  const reachable = new Set<string>();
  if (!start || !ids.has(start)) return reachable;

  const byId = new Map(dialogue.nodes.map((node) => [node.id, node]));
  const queue = [start];
  while (queue.length) {
    const id = queue.shift()!;
    if (reachable.has(id)) continue;
    reachable.add(id);
    const node = byId.get(id);
    if (!node) continue;
    for (const target of outgoingTargets(node)) {
      if (ids.has(target) && !reachable.has(target)) queue.push(target);
    }
  }
  return reachable;
}

export function validateDialogueGraph(dialogue: DialogueDocument): DialogueGraphIssue[] {
  const issues: DialogueGraphIssue[] = [];
  const ids = new Set<string>();
  const duplicateIds = new Set<string>();
  for (const node of dialogue.nodes) {
    if (ids.has(node.id)) duplicateIds.add(node.id);
    ids.add(node.id);
  }
  for (const id of duplicateIds) {
    issues.push({ severity: "error", type: "duplicate-id", nodeId: id, message: `Duplicate node id '${id}'.` });
  }

  const start = dialogue.start ?? dialogue.nodes[0]?.id;
  if (!start || !ids.has(start)) {
    issues.push({ severity: "error", type: "missing-start", target: start, message: `Start node '${start || "unset"}' is missing.` });
  }

  for (const node of dialogue.nodes) {
    if (node.next) {
      if (!ids.has(node.next)) {
        issues.push({ severity: "error", type: "missing-target", nodeId: node.id, target: node.next, message: `${node.id}.next targets missing node '${node.next}'.` });
      } else if (node.next === node.id) {
        issues.push({ severity: "warning", type: "self-link", nodeId: node.id, target: node.next, message: `${node.id} links to itself.` });
      }
    }
    for (const [choiceIndex, choice] of (node.choices ?? []).entries()) {
      if (!choice.text.trim()) {
        issues.push({ severity: "error", type: "empty-choice", nodeId: node.id, choiceIndex, message: `${node.id} choice ${choiceIndex + 1} needs text.` });
      }
      if (choice.next) {
        if (!ids.has(choice.next)) {
          issues.push({ severity: "error", type: "missing-target", nodeId: node.id, choiceIndex, target: choice.next, message: `${node.id} choice ${choiceIndex + 1} targets missing node '${choice.next}'.` });
        } else if (choice.next === node.id) {
          issues.push({ severity: "warning", type: "self-link", nodeId: node.id, choiceIndex, target: choice.next, message: `${node.id} choice ${choiceIndex + 1} links to itself.` });
        }
      }
    }
  }

  const reachable = reachableDialogueNodeIds(dialogue);
  for (const node of dialogue.nodes) {
    if (start && ids.has(start) && !reachable.has(node.id)) {
      issues.push({ severity: "warning", type: "unreachable", nodeId: node.id, message: `${node.id} is unreachable from '${start}'.` });
    }
  }

  for (const id of cyclicDialogueNodeIds(dialogue)) {
    issues.push({ severity: "info", type: "cycle", nodeId: id, message: `${id} is part of a dialogue cycle.` });
  }

  return issues;
}

export function autoLayoutDialogue(dialogue: DialogueDocument): Record<string, DialogueNodePosition> {
  const positions: Record<string, DialogueNodePosition> = {};
  const byId = new Map(dialogue.nodes.map((node) => [node.id, node]));
  const start = dialogue.start ?? dialogue.nodes[0]?.id;
  const layers = new Map<string, number>();

  if (start && byId.has(start)) {
    const queue: Array<{ id: string; depth: number }> = [{ id: start, depth: 0 }];
    while (queue.length) {
      const { id, depth } = queue.shift()!;
      const previousDepth = layers.get(id);
      if (previousDepth !== undefined && previousDepth <= depth) continue;
      layers.set(id, depth);
      const node = byId.get(id);
      if (!node) continue;
      for (const target of outgoingTargets(node)) {
        if (byId.has(target)) queue.push({ id: target, depth: depth + 1 });
      }
    }
  }

  const grouped = new Map<number, string[]>();
  for (const node of dialogue.nodes) {
    const depth = layers.get(node.id);
    if (depth === undefined) continue;
    grouped.set(depth, [...(grouped.get(depth) ?? []), node.id]);
  }
  for (const [depth, ids] of grouped) {
    ids.forEach((id, row) => {
      positions[id] = { x: 40 + depth * COLUMN_GAP, y: 40 + row * ROW_GAP };
    });
  }

  const maxLayerSize = Math.max(0, ...[...grouped.values()].map((ids) => ids.length));
  const unreachableY = 40 + maxLayerSize * ROW_GAP + UNREACHABLE_Y_GAP;
  let unreachableIndex = 0;
  for (const node of dialogue.nodes) {
    if (positions[node.id]) continue;
    positions[node.id] = {
      x: 40 + (unreachableIndex % 3) * COLUMN_GAP,
      y: unreachableY + Math.floor(unreachableIndex / 3) * ROW_GAP,
    };
    unreachableIndex += 1;
  }

  return positions;
}

export function dialoguePositions(dialogue: DialogueDocument): Record<string, DialogueNodePosition> {
  const layout = autoLayoutDialogue(dialogue);
  const stored = dialogue.editor?.nodes ?? {};
  const positions: Record<string, DialogueNodePosition> = {};
  for (const node of dialogue.nodes) {
    const saved = stored[node.id];
    positions[node.id] = isPosition(saved) ? saved : layout[node.id];
  }
  return positions;
}

export function renameDialogueNodeId(dialogue: DialogueDocument, index: number, nextId: string) {
  const node = dialogue.nodes[index];
  const id = nextId.trim();
  if (!node || !id || id === node.id) return;
  const previousId = node.id;
  node.id = id;
  if (dialogue.start === previousId) dialogue.start = id;
  for (const item of dialogue.nodes) {
    if (item.next === previousId) item.next = id;
    for (const choice of item.choices ?? []) {
      if (choice.next === previousId) choice.next = id;
    }
  }
  const saved = dialogue.editor?.nodes?.[previousId];
  if (saved) {
    dialogue.editor = { ...(dialogue.editor ?? {}), nodes: { ...(dialogue.editor?.nodes ?? {}), [id]: saved } };
    delete dialogue.editor.nodes?.[previousId];
  }
}

export function deleteDialogueNodeAndClearLinks(dialogue: DialogueDocument, index: number) {
  const removed = dialogue.nodes[index];
  if (!removed) return;
  dialogue.nodes.splice(index, 1);
  for (const node of dialogue.nodes) {
    if (node.next === removed.id) delete node.next;
    for (const choice of node.choices ?? []) {
      if (choice.next === removed.id) delete choice.next;
    }
  }
  delete dialogue.editor?.nodes?.[removed.id];
  if (dialogue.nodes.length === 0) {
    dialogue.nodes.push({ id: "start", text: "" });
    dialogue.start = "start";
    dialogue.editor = { ...(dialogue.editor ?? {}), nodes: { ...(dialogue.editor?.nodes ?? {}), start: { x: 40, y: 40 } } };
  } else if (dialogue.start === removed.id) {
    dialogue.start = dialogue.nodes[0].id;
  }
}

export function duplicateDialogueNode(dialogue: DialogueDocument, index: number): string | undefined {
  const source = dialogue.nodes[index];
  if (!source) return undefined;
  const id = uniqueDialogueId(`${source.id}_copy`, new Set(dialogue.nodes.map((node) => node.id)));
  const clone = structuredClone(source);
  clone.id = id;
  delete clone.next;
  dialogue.nodes.splice(index + 1, 0, clone);
  const positions = dialoguePositions(dialogue);
  const sourcePosition = positions[source.id] ?? { x: 40, y: 40 };
  setDialogueNodePosition(dialogue, id, { x: sourcePosition.x + NODE_WIDTH + 60, y: sourcePosition.y + 40 });
  return id;
}

export function setDialogueNodePosition(dialogue: DialogueDocument, id: string, position: DialogueNodePosition) {
  dialogue.editor = { ...(dialogue.editor ?? {}), nodes: { ...(dialogue.editor?.nodes ?? {}) } };
  dialogue.editor.nodes![id] = { x: Math.round(position.x), y: Math.round(position.y) };
}

export function setDialogueAutoLayout(dialogue: DialogueDocument) {
  dialogue.editor = { ...(dialogue.editor ?? {}), nodes: autoLayoutDialogue(dialogue) };
}

export function uniqueDialogueId(prefix: string, used: Set<string>) {
  let id = sanitizeNodeId(prefix) || "node";
  if (!used.has(id)) return id;
  let index = 2;
  while (used.has(`${id}_${index}`)) index += 1;
  return `${id}_${index}`;
}

function cyclicDialogueNodeIds(dialogue: DialogueDocument): Set<string> {
  const byId = new Map(dialogue.nodes.map((node) => [node.id, node]));
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const cyclic = new Set<string>();

  function visit(id: string, path: string[]) {
    if (visiting.has(id)) {
      const cycleStart = path.indexOf(id);
      for (const cycleId of path.slice(Math.max(0, cycleStart))) cyclic.add(cycleId);
      return;
    }
    if (visited.has(id)) return;
    const node = byId.get(id);
    if (!node) return;
    visiting.add(id);
    for (const target of outgoingTargets(node)) {
      if (byId.has(target)) visit(target, [...path, target]);
    }
    visiting.delete(id);
    visited.add(id);
  }

  for (const node of dialogue.nodes) visit(node.id, [node.id]);
  return cyclic;
}

function sanitizeNodeId(value: string) {
  return value.trim().replace(/\s+/g, "_").replace(/[^a-zA-Z0-9_.-]/g, "");
}

function isPosition(value: unknown): value is DialogueNodePosition {
  return Boolean(
    value &&
      typeof value === "object" &&
      Number.isFinite((value as DialogueNodePosition).x) &&
      Number.isFinite((value as DialogueNodePosition).y)
  );
}
