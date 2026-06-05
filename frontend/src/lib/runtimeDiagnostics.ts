import type { PreviewLog } from "./previewRuntime";
import type { RuntimeProblem } from "./stores";

const RUNTIME_PATTERNS = [
  /\[wren(?::|\])/i,
  /WrenLoadFailed/i,
  /interpret error/i,
  /runtime error/i,
  /compile error/i,
  /failed to (load|parse|instantiate|open)/i,
  /MissingTexture|UnknownTexture|UnknownScene|InvalidJson|InvalidValue|InvalidType/i,
];

export function problemFromPreviewLog(log: PreviewLog): RuntimeProblem | undefined {
  const line = log.line.trim();
  if (!line) return undefined;
  const isError = RUNTIME_PATTERNS.some((pattern) => pattern.test(line));
  if (!isError) return undefined;
  return {
    severity: "error",
    source: runtimePathFromLine(line),
    message: line,
    raw: `[${log.stream}] ${line}`,
  };
}

export function diagnosticFromPreviewLog(log: PreviewLog) {
  return problemFromPreviewLog(log);
}

export function isProblemLog(log: PreviewLog): boolean {
  const line = log.line.trim();
  return Boolean(line && RUNTIME_PATTERNS.some((pattern) => pattern.test(line)));
}

function runtimePathFromLine(line: string): string {
  const match = line.match(/(?:assets\/|\.\/)?[\w./-]+\.(?:json|wren|png|jpg|jpeg)/i);
  return match?.[0]?.replace(/^\.\//, "") ?? "runtime";
}
