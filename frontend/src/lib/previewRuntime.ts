import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { Vfs } from './types';

type PreviewFile = {
  path: string;
  bytes: number[];
};

export type PreviewLog = {
  stream: 'stdout' | 'stderr';
  line: string;
};

type Unlisten = () => void;

const previewLogCallbacks = new Set<(log: PreviewLog) => void>();
let previewLogUnlisten: Unlisten | undefined;
let previewLogListenPromise: Promise<Unlisten> | undefined;

export async function startPreview(vfs: Vfs): Promise<string> {
  assertTauri();
  return invoke<string>('start_preview', { files: toPreviewFiles(vfs) });
}

export async function stopPreview(): Promise<string> {
  assertTauri();
  return invoke<string>('stop_preview');
}

export async function openProjectFolder(root: string): Promise<Vfs> {
  assertTauri();
  const files = await invoke<PreviewFile[]>('open_project_folder', { root });
  return fromPreviewFiles(files);
}

export async function saveProjectFolder(root: string, vfs: Vfs): Promise<string> {
  assertTauri();
  return invoke<string>('save_project_folder', { request: { root, files: toPreviewFiles(vfs) } });
}

export async function exportWebBundle(destination: string, vfs: Vfs): Promise<string> {
  assertTauri();
  return invoke<string>('export_web_bundle', { request: { destination, files: toPreviewFiles(vfs) } });
}

export async function listenPreviewLogs(onLog: (log: PreviewLog) => void): Promise<() => void> {
  if (!isTauriRuntime()) return () => {};
  previewLogCallbacks.add(onLog);
  if (!previewLogListenPromise) {
    previewLogListenPromise = listen<PreviewLog>('preview-log', (event) => {
      for (const callback of previewLogCallbacks) callback(event.payload);
    }).then((unlisten) => {
      previewLogUnlisten = unlisten;
      return unlisten;
    });
  }
  await previewLogListenPromise;
  return () => {
    previewLogCallbacks.delete(onLog);
    if (previewLogCallbacks.size === 0 && previewLogUnlisten) {
      previewLogUnlisten();
      previewLogUnlisten = undefined;
      previewLogListenPromise = undefined;
    }
  };
}

function assertTauri(): void {
  if (!isTauriRuntime()) throw new Error('This action is available in the desktop editor.');
}

function isTauriRuntime(): boolean {
  return '__TAURI_INTERNALS__' in window;
}

function toPreviewFiles(vfs: Vfs): PreviewFile[] {
  return [...vfs.values()].map((file) => ({
    path: file.path,
    bytes:
      file.kind === 'text'
        ? [...new TextEncoder().encode(file.text ?? '')]
        : [...(file.bytes ?? new Uint8Array())]
  }));
}

function fromPreviewFiles(files: PreviewFile[]): Vfs {
  const decoder = new TextDecoder();
  const vfs: Vfs = new Map();
  for (const file of files) {
    const bytes = new Uint8Array(file.bytes);
    const textLike = file.path === 'game.json' || /\.(json|wren|txt|md|csv)$/i.test(file.path);
    vfs.set(file.path, textLike ? { path: file.path, kind: 'text', text: decoder.decode(bytes) } : { path: file.path, kind: 'binary', bytes });
  }
  return vfs;
}
