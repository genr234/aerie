import { describe, expect, it } from "vitest";
import { normalizePath, readText, writeText } from "./vfs";
import type { Vfs } from "./types";

describe("vfs", () => {
  it("normalizes paths and reads written text files", () => {
    let vfs: Vfs = new Map();
    vfs = writeText(vfs, "/assets\\scenes/start.json", "{}");

    expect(normalizePath("/assets\\scenes/start.json")).toBe("assets/scenes/start.json");
    expect(readText(vfs, "assets/scenes/start.json")).toBe("{}");
  });
});
