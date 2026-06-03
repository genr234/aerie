import { describe, expect, it } from "vitest";
import {
  autoLayoutDialogue,
  deleteDialogueNodeAndClearLinks,
  dialoguePositions,
  duplicateDialogueNode,
  renameDialogueNodeId,
  setDialogueNodePosition,
  validateDialogueGraph,
} from "./dialogueGraph";
import type { DialogueDocument } from "./types";

function sampleDialogue(): DialogueDocument {
  return {
    id: "intro",
    start: "start",
    nodes: [
      { id: "start", text: "Hello", next: "choice" },
      {
        id: "choice",
        text: "Where next?",
        choices: [
          { text: "Left", next: "left" },
          { text: "Right", next: "right" },
        ],
      },
      { id: "left", text: "Left path" },
      { id: "right", text: "Right path" },
    ],
  };
}

describe("dialogue graph helpers", () => {
  it("renames a node id and rewrites start, next, choices, and editor metadata", () => {
    const dialogue = sampleDialogue();
    setDialogueNodePosition(dialogue, "choice", { x: 100, y: 200 });

    renameDialogueNodeId(dialogue, 1, "branch");

    expect(dialogue.nodes[1].id).toBe("branch");
    expect(dialogue.nodes[0].next).toBe("branch");
    expect(dialogue.editor?.nodes?.branch).toEqual({ x: 100, y: 200 });
    expect(dialogue.editor?.nodes?.choice).toBeUndefined();
  });

  it("deletes a node and clears links that target it", () => {
    const dialogue = sampleDialogue();

    deleteDialogueNodeAndClearLinks(dialogue, 2);

    expect(dialogue.nodes.map((node) => node.id)).toEqual(["start", "choice", "right"]);
    expect(dialogue.nodes[1].choices?.[0].next).toBeUndefined();
    expect(dialogue.nodes[1].choices?.[1].next).toBe("right");
  });

  it("creates deterministic fallback layout by reachability layers", () => {
    const dialogue = sampleDialogue();
    dialogue.nodes.push({ id: "orphan", text: "Not connected" });

    const positions = autoLayoutDialogue(dialogue);

    expect(positions.start.x).toBeLessThan(positions.choice.x);
    expect(positions.choice.x).toBeLessThan(positions.left.x);
    expect(positions.orphan.y).toBeGreaterThan(positions.start.y);
  });

  it("prefers saved node positions over fallback layout", () => {
    const dialogue = sampleDialogue();

    setDialogueNodePosition(dialogue, "start", { x: 321.4, y: 654.2 });

    expect(dialoguePositions(dialogue).start).toEqual({ x: 321, y: 654 });
  });

  it("duplicates nodes with a unique id and an offset saved position", () => {
    const dialogue = sampleDialogue();
    setDialogueNodePosition(dialogue, "choice", { x: 200, y: 100 });

    const id = duplicateDialogueNode(dialogue, 1);

    expect(id).toBe("choice_copy");
    expect(dialogue.nodes[2].id).toBe("choice_copy");
    expect(dialogue.nodes[2].next).toBeUndefined();
    expect(dialogue.editor?.nodes?.choice_copy).toEqual({ x: 520, y: 140 });
  });

  it("reports missing targets, empty choices, unreachable nodes, self links, and cycles", () => {
    const dialogue: DialogueDocument = {
      id: "broken",
      start: "a",
      nodes: [
        { id: "a", text: "", next: "b" },
        { id: "b", text: "", next: "a", choices: [{ text: "", next: "ghost" }] },
        { id: "self", text: "", next: "self" },
      ],
    };

    const issueTypes = [
      ...validateDialogueGraph(dialogue),
      ...validateDialogueGraph({ ...dialogue, start: "missing_start" }),
    ].map((issue) => issue.type);

    expect(issueTypes).toContain("missing-start");
    expect(issueTypes).toContain("missing-target");
    expect(issueTypes).toContain("empty-choice");
    expect(issueTypes).toContain("unreachable");
    expect(issueTypes).toContain("self-link");
    expect(issueTypes).toContain("cycle");
  });
});
