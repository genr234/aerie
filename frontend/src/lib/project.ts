import type { Diagnostic, DialogueDocument, ProjectConfig, SceneDocument, Vfs } from './types';
import { normalizePath, readText } from './vfs';

export const COMPONENTS = ['Transform', 'Sprite', 'Circle', 'Rect', 'Camera', 'PlayerController', 'Trigger'];

export function parseProject(vfs: Vfs): { project?: ProjectConfig; diagnostics: Diagnostic[] } {
  const text = readText(vfs, 'game.json');
  if (!text) return { diagnostics: [{ severity: 'error', path: 'game.json', message: 'Missing project manifest' }] };
  try {
    const project = JSON.parse(text) as ProjectConfig;
    return { project, diagnostics: validateProject(vfs, project) };
  } catch (error) {
    return { diagnostics: [{ severity: 'error', path: 'game.json', message: `Invalid JSON: ${messageOf(error)}`, ...jsonErrorLocation(text, error) }] };
  }
}

export function parseScene(vfs: Vfs, path: string): { scene?: SceneDocument; diagnostics: Diagnostic[] } {
  const text = readText(vfs, path);
  if (!text) return { diagnostics: [{ severity: 'error', path, message: 'Missing scene file' }] };
  try {
    const scene = JSON.parse(text) as SceneDocument;
    return { scene, diagnostics: validateScene(path, scene) };
  } catch (error) {
    return { diagnostics: [{ severity: 'error', path, message: `Invalid JSON: ${messageOf(error)}`, ...jsonErrorLocation(text, error) }] };
  }
}

export function parseDialogue(vfs: Vfs, path: string): { dialogue?: DialogueDocument; diagnostics: Diagnostic[] } {
  const text = readText(vfs, path);
  if (!text) return { diagnostics: [{ severity: 'error', path, message: 'Missing dialogue file' }] };
  try {
    const dialogue = JSON.parse(text) as DialogueDocument;
    return { dialogue, diagnostics: validateDialogue(path, dialogue) };
  } catch (error) {
    return { diagnostics: [{ severity: 'error', path, message: `Invalid JSON: ${messageOf(error)}`, ...jsonErrorLocation(text, error) }] };
  }
}

export function writeScene(scene: SceneDocument): string {
  return `${JSON.stringify(scene, null, 2)}\n`;
}

export function writeDialogue(dialogue: DialogueDocument): string {
  return `${JSON.stringify(dialogue, null, 2)}\n`;
}

export function validateAll(vfs: Vfs): Diagnostic[] {
  const { project, diagnostics } = parseProject(vfs);
  if (!project) return diagnostics;
  const out = [...diagnostics];
  for (const decl of project.scenes ?? []) {
    out.push(...parseScene(vfs, decl.path).diagnostics);
  }
  for (const decl of project.dialogues ?? []) {
    out.push(...parseDialogue(vfs, decl.path).diagnostics);
  }
  return out;
}

export function fatalDiagnostics(diagnostics: Diagnostic[]): Diagnostic[] {
  return diagnostics.filter((diagnostic) => diagnostic.severity === 'error');
}

function validateProject(vfs: Vfs, project: ProjectConfig): Diagnostic[] {
  const out: Diagnostic[] = [];
  if (!project.id) out.push({ severity: 'error', path: 'game.json', message: 'Missing id' });
  if (!project.title) out.push({ severity: 'error', path: 'game.json', message: 'Missing title' });

  const scenes = project.scenes ?? [];
  if (scenes.length === 0) out.push({ severity: 'error', path: 'game.json', message: 'No scenes declared' });

  const sceneNames = new Set<string>();
  for (const scene of scenes) {
    if (sceneNames.has(scene.name)) out.push({ severity: 'error', path: 'game.json', message: `Duplicate scene '${scene.name}'` });
    sceneNames.add(scene.name);
    if (!vfs.has(normalizePath(scene.path))) out.push({ severity: 'error', path: scene.path, message: `Missing scene '${scene.name}'` });
  }

  const start = project.start_scene;
  if (!start) {
    out.push({ severity: 'error', path: 'game.json', message: 'Missing start_scene' });
  } else if (!scenes.some((scene) => scene.name === start || normalizePath(scene.path) === normalizePath(start))) {
    out.push({ severity: 'error', path: 'game.json', message: `start_scene '${start}' is not declared` });
  }

  const scriptNames = new Set<string>();
  for (const script of project.scripts ?? []) {
    if (scriptNames.has(script.name)) out.push({ severity: 'error', path: 'game.json', message: `Duplicate script '${script.name}'` });
    scriptNames.add(script.name);
    if (!vfs.has(normalizePath(script.path))) out.push({ severity: 'error', path: script.path, message: `Missing script '${script.name}'` });
  }

  const dialogueNames = new Set<string>();
  for (const dialogue of project.dialogues ?? []) {
    if (dialogueNames.has(dialogue.name)) out.push({ severity: 'error', path: 'game.json', message: `Duplicate dialogue '${dialogue.name}'` });
    dialogueNames.add(dialogue.name);
    if (!vfs.has(normalizePath(dialogue.path))) out.push({ severity: 'error', path: dialogue.path, message: `Missing dialogue '${dialogue.name}'` });
  }
  const entryModule = project.entry?.module ?? 'main';
  const entryClass = project.entry?.class ?? 'Game';
  const entryScript = (project.scripts ?? []).find((script) => script.name === entryModule);
  if (!entryScript) {
    out.push({ severity: 'error', path: 'game.json', message: `entry.module '${entryModule}' is not declared in scripts` });
  } else {
    const source = readText(vfs, entryScript.path) ?? '';
    if (!source.includes(`class ${entryClass}`)) {
      out.push({ severity: 'warning', path: entryScript.path, message: `Entry class '${entryClass}' was not found` });
    }
  }

  const sceneTargets = new Set(scenes.map((scene) => scene.name));
  for (const scene of scenes) {
    const parsed = parseScene(vfs, scene.path);
    if (!parsed.scene) continue;
    for (const diagnostic of validateSceneReferences(vfs, scene.path, parsed.scene, sceneTargets)) out.push(diagnostic);
  }
  out.push(...validateUnusedAssets(vfs, scenes));

  return out;
}

function validateUnusedAssets(vfs: Vfs, scenes: Array<{ name: string; path: string }>): Diagnostic[] {
  const referenced = new Set<string>();
  for (const scene of scenes) {
    const parsed = parseScene(vfs, scene.path);
    for (const entity of parsed.scene?.entities ?? []) {
      const sprite = entity.components?.Sprite as { texture?: string } | undefined;
      if (sprite?.texture) referenced.add(normalizePath(sprite.texture.startsWith('assets/') ? sprite.texture : `assets/${sprite.texture}`));
    }
  }
  return [...vfs.keys()]
    .filter((path) => path.startsWith('assets/') && /\.(png|jpg|jpeg)$/i.test(path) && !referenced.has(normalizePath(path)))
    .map((path) => ({ severity: 'warning', path, message: `Asset is not used by any Sprite component` }));
}

function validateDialogue(path: string, dialogue: DialogueDocument): Diagnostic[] {
  const out: Diagnostic[] = [];
  if (!dialogue.id) out.push({ severity: 'error', path, message: 'Dialogue is missing id' });
  if (!Array.isArray(dialogue.nodes) || dialogue.nodes.length === 0) {
    out.push({ severity: 'error', path, message: 'Dialogue must contain nodes' });
    return out;
  }
  const ids = new Set<string>();
  for (const [index, node] of dialogue.nodes.entries()) {
    if (!node.id) out.push({ severity: 'error', path, message: `nodes[${index}] is missing id` });
    if (node.id && ids.has(node.id)) out.push({ severity: 'error', path, message: `Duplicate dialogue node '${node.id}'` });
    ids.add(node.id);
    if (node.text !== undefined && typeof node.text !== 'string') out.push({ severity: 'error', path, message: `nodes[${index}].text must be a string` });
    if (node.speaker !== undefined && typeof node.speaker !== 'string') out.push({ severity: 'error', path, message: `nodes[${index}].speaker must be a string` });
    if (node.next !== undefined && typeof node.next !== 'string') out.push({ severity: 'error', path, message: `nodes[${index}].next must be a string` });
    if (node.choices !== undefined && !Array.isArray(node.choices)) out.push({ severity: 'error', path, message: `nodes[${index}].choices must be an array` });
    for (const [choiceIndex, choice] of (node.choices ?? []).entries()) {
      if (typeof choice.text !== 'string' || choice.text.length === 0) out.push({ severity: 'error', path, message: `nodes[${index}].choices[${choiceIndex}].text is required` });
      if (choice.next !== undefined && typeof choice.next !== 'string') out.push({ severity: 'error', path, message: `nodes[${index}].choices[${choiceIndex}].next must be a string` });
    }
  }
  const start = dialogue.start ?? dialogue.nodes[0]?.id;
  if (start && !ids.has(start)) out.push({ severity: 'error', path, message: `Dialogue start '${start}' is missing` });
  for (const [index, node] of dialogue.nodes.entries()) {
    if (node.next && !ids.has(node.next)) out.push({ severity: 'error', path, message: `nodes[${index}].next targets missing node '${node.next}'` });
    for (const [choiceIndex, choice] of (node.choices ?? []).entries()) {
      if (choice.next && !ids.has(choice.next)) out.push({ severity: 'error', path, message: `nodes[${index}].choices[${choiceIndex}].next targets missing node '${choice.next}'` });
    }
  }
  return out;
}

function validateScene(path: string, scene: SceneDocument): Diagnostic[] {
  const out: Diagnostic[] = [];
  if (!scene.name) out.push({ severity: 'error', path, message: 'Missing scene name' });
  if (scene.size) {
    if (!num(scene.size.width) || !num(scene.size.height) || Number(scene.size.width) <= 0 || Number(scene.size.height) <= 0) {
      out.push({ severity: 'error', path, message: 'Scene size must contain positive width and height' });
    }
  }
  if (scene.background?.color !== undefined && !validColor(scene.background.color)) {
    out.push({ severity: 'error', path, message: 'Scene background color must be #RRGGBB or #RRGGBBAA' });
  }
  if (!Array.isArray(scene.entities)) out.push({ severity: 'error', path, message: 'entities must be an array' });
  const tags = new Set<string>();
  for (const [index, entity] of (scene.entities ?? []).entries()) {
    if (entity.tag) {
      if (tags.has(entity.tag)) out.push({ severity: 'error', path, message: `Duplicate entity tag '${entity.tag}'` });
      tags.add(entity.tag);
    }
    if (!entity.components || typeof entity.components !== 'object' || Array.isArray(entity.components)) {
      out.push({ severity: 'error', path, message: `entities[${index}].components must be an object` });
      continue;
    }
    for (const component of Object.keys(entity.components)) {
      if (!COMPONENTS.includes(component)) {
        out.push({ severity: 'warning', path, message: `entities[${index}] has unknown component '${component}'` });
      }
    }
    out.push(...validateComponentShape(path, index, entity.components));
  }
  if (!tags.has('player')) out.push({ severity: 'warning', path, message: "Scene has no entity tagged 'player'" });
  if (!(scene.entities ?? []).some((entity) => Boolean(entity.components?.Camera))) out.push({ severity: 'warning', path, message: 'Scene has no Camera component' });
  return out;
}

function validateSceneReferences(vfs: Vfs, path: string, scene: SceneDocument, sceneTargets: Set<string>): Diagnostic[] {
  const out: Diagnostic[] = [];
  const tags = new Set((scene.entities ?? []).map((entity) => entity.tag).filter(Boolean));
  for (const [index, entity] of (scene.entities ?? []).entries()) {
    const sprite = entity.components?.Sprite as { texture?: string } | undefined;
    if (sprite?.texture) {
      const texturePath = sprite.texture.startsWith('assets/') ? sprite.texture : `assets/${sprite.texture}`;
      if (!vfs.has(normalizePath(texturePath))) {
        out.push({ severity: 'error', path, message: `entities[${index}].Sprite.texture missing asset '${sprite.texture}'` });
      }
    }
    const camera = entity.components?.Camera as { followTag?: string } | undefined;
    if (camera?.followTag && !tags.has(camera.followTag)) {
      out.push({ severity: 'error', path, message: `entities[${index}].Camera.followTag targets missing tag '${camera.followTag}'` });
    }
    const trigger = entity.components?.Trigger as { action?: { changeScene?: { name?: string } } } | undefined;
    const target = trigger?.action?.changeScene?.name;
    if (target && !sceneTargets.has(target)) {
      out.push({ severity: 'error', path, message: `entities[${index}].Trigger targets missing scene '${target}'` });
    }
  }
  return out;
}

function validateComponentShape(path: string, index: number, components: Record<string, unknown>): Diagnostic[] {
  const out: Diagnostic[] = [];
  const transform = record(components.Transform);
  if (transform) {
    if (transform.position !== undefined && !vec(transform.position, 2)) out.push({ severity: 'error', path, message: `entities[${index}].Transform.position must be [x, y]` });
    if (transform.scale !== undefined && !vec(transform.scale, 2)) out.push({ severity: 'error', path, message: `entities[${index}].Transform.scale must be [x, y]` });
    if (transform.rotation !== undefined && !num(transform.rotation)) out.push({ severity: 'error', path, message: `entities[${index}].Transform.rotation must be a number` });
  }

  const rect = record(components.Rect);
  if (rect && (!num(rect.width) || !num(rect.height) || !validColor(rect.color))) {
    out.push({ severity: 'error', path, message: `entities[${index}].Rect needs numeric width/height and string color` });
  }

  const circle = record(components.Circle);
  if (circle && (!num(circle.radius) || !validColor(circle.color))) {
    out.push({ severity: 'error', path, message: `entities[${index}].Circle needs numeric radius and string color` });
  }

  const sprite = record(components.Sprite);
  if (sprite) {
    if (typeof sprite.texture !== 'string') out.push({ severity: 'error', path, message: `entities[${index}].Sprite.texture must be a string` });
    for (const key of ['frameWidth', 'frameHeight', 'frames', 'fps']) {
      if (sprite[key] !== undefined && !num(sprite[key])) out.push({ severity: 'error', path, message: `entities[${index}].Sprite.${key} must be a number` });
    }
    if (sprite.loop !== undefined && typeof sprite.loop !== 'boolean') out.push({ severity: 'error', path, message: `entities[${index}].Sprite.loop must be a boolean` });
  }

  const camera = record(components.Camera);
  if (camera) {
    if (!vec(camera.offset, 2)) out.push({ severity: 'error', path, message: `entities[${index}].Camera.offset must be [x, y]` });
    if (camera.zoom !== undefined && !num(camera.zoom)) out.push({ severity: 'error', path, message: `entities[${index}].Camera.zoom must be a number` });
  }

  const controller = record(components.PlayerController);
  if (controller && controller.speed !== undefined && !num(controller.speed)) {
    out.push({ severity: 'error', path, message: `entities[${index}].PlayerController.speed must be a number` });
  }

  const trigger = record(components.Trigger);
  if (trigger) {
    if (!vec(trigger.bounds, 4)) out.push({ severity: 'error', path, message: `entities[${index}].Trigger.bounds must be [x, y, width, height]` });
    if (!validTriggerAction(trigger.action)) out.push({ severity: 'error', path, message: `entities[${index}].Trigger.action has invalid shape` });
  }

  return out;
}

function validTriggerAction(value: unknown): boolean {
  const action = record(value);
  if (!action) return false;
  if (record(action.startDialogue)) return true;
  const showMessage = record(action.showMessage);
  if (showMessage) return typeof showMessage.text === 'string' && (showMessage.duration === undefined || num(showMessage.duration));
  const changeScene = record(action.changeScene);
  if (changeScene) return changeScene.name === undefined || typeof changeScene.name === 'string';
  const setFlag = record(action.setFlag);
  if (setFlag) return typeof setFlag.name === 'string' && (setFlag.value === undefined || typeof setFlag.value === 'boolean');
  return false;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;
}

function num(value: unknown): boolean {
  return typeof value === 'number' && Number.isFinite(value);
}

function validColor(value: unknown): boolean {
  return typeof value === 'string' && /^#([0-9a-f]{6}|[0-9a-f]{8})$/i.test(value);
}

function vec(value: unknown, length: number): boolean {
  return Array.isArray(value) && value.length === length && value.every(num);
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function jsonErrorLocation(text: string, error: unknown): Pick<Diagnostic, 'line' | 'column'> {
  const match = messageOf(error).match(/position (\d+)/);
  if (!match) return {};
  const position = Number(match[1]);
  if (!Number.isFinite(position)) return {};
  const before = text.slice(0, position);
  const lines = before.split('\n');
  return { line: lines.length, column: lines[lines.length - 1].length + 1 };
}
