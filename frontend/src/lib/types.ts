export type FileKind = 'text' | 'binary';

export type VfsFile = {
  path: string;
  kind: FileKind;
  text?: string;
  bytes?: Uint8Array;
};

export type Vfs = Map<string, VfsFile>;

export type ProjectConfig = {
  id: string;
  title: string;
  version?: string;
  entry?: { module?: string; class?: string };
  start_scene?: string;
  scenes?: Array<{ name: string; path: string }>;
  scripts?: Array<{ name: string; path: string }>;
  dialogues?: Array<{ name: string; path: string }>;
  window?: { width?: number; height?: number; title?: string };
};

export type SceneDocument = {
  name: string;
  type?: 'exploration' | 'visual_novel';
  size?: { width?: number; height?: number };
  background?: { color?: string; image?: string };
  entities: SceneEntity[];
};

export type SceneEntity = {
  tag?: string;
  components: Record<string, unknown>;
};

export type DialogueDocument = {
  id: string;
  start?: string;
  nodes: DialogueNode[];
  editor?: DialogueEditorState;
};

export type DialogueEditorState = {
  nodes?: Record<string, DialogueNodePosition>;
};

export type DialogueNodePosition = {
  x: number;
  y: number;
};

export type DialogueNode = {
  id: string;
  speaker?: string;
  text?: string;
  choices?: DialogueChoice[];
  when?: string;
  actions?: Array<Record<string, unknown>>;
  next?: string;
};

export type DialogueChoice = {
  text: string;
  next?: string;
  when?: string;
  actions?: Array<Record<string, unknown>>;
};

export type DiagnosticSeverity = 'error' | 'warning' | 'info';

export type Diagnostic = {
  severity: DiagnosticSeverity;
  path: string;
  message: string;
  line?: number;
  column?: number;
};

export type Selection =
  | { type: 'file'; path: string }
  | { type: 'entity'; scenePath: string; entityIndex: number }
  | { type: 'component'; scenePath: string; entityIndex: number; component: string };
