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
  combat?: { path: string };
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

export type CombatDocument = {
  actors: CombatActor[];
  skills: CombatSkill[];
  encounters: CombatEncounter[];
};

export type CombatActor = {
  id: string;
  name: string;
  side: 'party' | 'enemy';
  level?: number;
  hp: number;
  mp?: number;
  attack: number;
  defense: number;
  speed: number;
  xp?: number;
  skills?: string[];
};

export type CombatSkill = {
  id: string;
  name: string;
  kind?: 'damage' | 'heal';
  power?: number;
  mpCost?: number;
  target?: 'enemy' | 'ally' | 'self';
  message?: string;
};

export type CombatEncounter = {
  id: string;
  party: string[];
  enemies: string[];
  rewards?: { xp?: number; gold?: number };
  onWinScene?: string;
  onLoseScene?: string;
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
