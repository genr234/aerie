import { unzipSync, zipSync, strFromU8, strToU8 } from 'fflate';
import type { Vfs, VfsFile } from './types';

const TEXT_EXTENSIONS = new Set(['.json', '.wren', '.txt', '.md', '.csv']);

export function normalizePath(path: string): string {
  return path.replaceAll('\\', '/').replace(/^\/+/, '').replace(/^\.\//, '');
}

export function isTextPath(path: string): boolean {
  const lower = path.toLowerCase();
  if (lower === 'game.json') return true;
  for (const ext of TEXT_EXTENSIONS) {
    if (lower.endsWith(ext)) return true;
  }
  return false;
}

export function readText(vfs: Vfs, path: string): string | undefined {
  const file = vfs.get(normalizePath(path));
  if (!file) return undefined;
  if (file.kind === 'text') return file.text ?? '';
  return file.bytes ? strFromU8(file.bytes) : undefined;
}

export function writeText(vfs: Vfs, path: string, text: string): Vfs {
  const next = new Map(vfs);
  const normalized = normalizePath(path);
  next.set(normalized, { path: normalized, kind: 'text', text });
  return next;
}

export async function vfsFromZip(file: File): Promise<Vfs> {
  const bytes = new Uint8Array(await file.arrayBuffer());
  const entries = unzipSync(bytes);
  const vfs: Vfs = new Map();
  for (const [rawPath, content] of Object.entries(entries)) {
    const path = normalizePath(rawPath);
    if (!path || path.endsWith('/')) continue;
    vfs.set(path, fileFromBytes(path, content));
  }
  return vfs;
}

export function vfsToZip(vfs: Vfs): Uint8Array {
  const entries: Record<string, Uint8Array> = {};
  for (const [path, file] of [...vfs.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    entries[path] = file.kind === 'text' ? strToU8(file.text ?? '') : file.bytes ?? new Uint8Array();
  }
  return zipSync(entries, { level: 6 });
}

export function downloadZip(vfs: Vfs, name = 'game-project.zip'): void {
  const zip = vfsToZip(vfs);
  const bytes = new Uint8Array(zip.byteLength);
  bytes.set(zip);
  const blob = new Blob([bytes.buffer as ArrayBuffer], { type: 'application/zip' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = name;
  anchor.click();
  URL.revokeObjectURL(url);
}

export async function loadReferenceProject(): Promise<Vfs> {
  const paths = [
    'game.json',
    'assets/reference-game/crossroads.json',
    'assets/reference-game/clearing.json',
    'assets/reference-game/player.png',
    'assets/scripts/main.wren'
  ];
  const vfs: Vfs = new Map();
  for (const path of paths) {
    const res = await fetch(`/reference/${path}`);
    if (!res.ok) throw new Error(`Failed to load reference file: ${path}`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    vfs.set(path, fileFromBytes(path, bytes));
  }
  return vfs;
}

export function fileFromBytes(path: string, bytes: Uint8Array): VfsFile {
  const normalized = normalizePath(path);
  if (isTextPath(normalized)) {
    return { path: normalized, kind: 'text', text: strFromU8(bytes) };
  }
  return { path: normalized, kind: 'binary', bytes };
}

export function sortedPaths(vfs: Vfs): string[] {
  return [...vfs.keys()].sort((a, b) => a.localeCompare(b));
}
