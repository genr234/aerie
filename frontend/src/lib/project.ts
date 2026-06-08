import type { CombatDocument, Diagnostic, DialogueDocument, ProjectConfig, SceneDocument, Vfs } from './types';
import { normalizePath, readText } from './vfs';
export { COMPONENTS } from './componentRegistry';
import { COMPONENTS } from './componentRegistry';

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

export function parseCombat(vfs: Vfs, path: string): { combat?: CombatDocument; diagnostics: Diagnostic[] } {
  const text = readText(vfs, path);
  if (!text) return { diagnostics: [{ severity: 'error', path, message: 'Missing combat file' }] };
  try {
    const combat = JSON.parse(text) as CombatDocument;
    return { combat, diagnostics: validateCombat(path, combat) };
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

export function writeCombat(combat: CombatDocument): string {
  return `${JSON.stringify(combat, null, 2)}\n`;
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
  if (project.combat?.path) out.push(...parseCombat(vfs, project.combat.path).diagnostics);
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
  if (project.combat?.path) {
    if (!vfs.has(normalizePath(project.combat.path))) {
      out.push({ severity: 'error', path: project.combat.path, message: 'Missing combat file' });
    } else {
      out.push(...parseCombat(vfs, project.combat.path).diagnostics);
    }
  }
  for (const asset of [...(project.audio?.sounds ?? []), ...(project.audio?.music ?? [])]) {
    if (!asset.id) out.push({ severity: 'error', path: 'game.json', message: 'Audio asset is missing id' });
    if (!asset.path) {
      out.push({ severity: 'error', path: 'game.json', message: `Audio asset '${asset.id || 'unknown'}' is missing path` });
      continue;
    }
    const assetPath = asset.path.startsWith('assets/') ? asset.path : `assets/${asset.path}`;
    if (!vfs.has(normalizePath(assetPath))) {
      out.push({ severity: 'error', path: assetPath, message: `Missing audio asset '${asset.id || asset.path}'` });
    }
  }
  const audioIds = new Set([...(project.audio?.sounds ?? []), ...(project.audio?.music ?? [])].map((asset) => asset.id).filter(Boolean));
  const combatDoc = project.combat?.path ? parseCombat(vfs, project.combat.path).combat : undefined;
  const encounterIds = new Set((combatDoc?.encounters ?? []).map((encounter) => encounter.id).filter(Boolean));
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
  const referencedEncounters = new Set<string>();
  let hasEnding = false;
  for (const scene of scenes) {
    const parsed = parseScene(vfs, scene.path);
    if (!parsed.scene) continue;
    for (const diagnostic of validateSceneReferences(vfs, scene.path, parsed.scene, sceneTargets, scenes, audioIds, encounterIds)) out.push(diagnostic);
    for (const entity of parsed.scene.entities ?? []) {
      for (const ref of actionCombatRefs(entity.components?.Trigger)) referencedEncounters.add(ref.encounter);
      for (const ref of actionCombatRefs(entity.components?.Interactable)) referencedEncounters.add(ref.encounter);
      if (entity.tag?.toLowerCase().includes('ending')) hasEnding = true;
      if (actionsSetFlag(entity.components?.Trigger, ['ending_reached', 'game_complete'])) hasEnding = true;
      if (actionsSetFlag(entity.components?.Interactable, ['ending_reached', 'game_complete'])) hasEnding = true;
    }
  }
  for (const script of project.scripts ?? []) {
    const source = readText(vfs, script.path) ?? '';
    for (const id of encounterIds) {
      if (source.includes(id)) referencedEncounters.add(id);
    }
    if (/ending_reached|game_complete/.test(source)) hasEnding = true;
  }
  for (const id of encounterIds) {
    if (!referencedEncounters.has(id)) out.push({ severity: 'warning', path: project.combat?.path ?? 'game.json', message: `Combat encounter '${id}' is not started by any scene action or script` });
  }
  if (scenes.length > 0 && !hasEnding) {
    out.push({ severity: 'warning', path: 'game.json', message: "Project has no obvious ending action; add an Ending preset or set 'ending_reached'" });
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
    if (entity.components.PlayerController && !entity.components.BoxCollider) {
      out.push({ severity: 'warning', path, message: `entities[${index}] has PlayerController but no BoxCollider` });
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

function validateSceneReferences(vfs: Vfs, path: string, scene: SceneDocument, sceneTargets: Set<string>, scenes: Array<{ name: string; path: string }>, audioIds: Set<string>, encounterIds: Set<string>): Diagnostic[] {
  const out: Diagnostic[] = [];
  const tags = new Set((scene.entities ?? []).map((entity) => entity.tag).filter(Boolean));
  const spawnPoints = new Set<string>();
  for (const entity of scene.entities ?? []) {
    const spawn = record(entity.components?.SpawnPoint);
    if (typeof spawn?.name === 'string') spawnPoints.add(spawn.name);
  }

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

    for (const ref of actionSceneRefs(entity.components?.Trigger)) {
      if (ref.scene && !sceneTargets.has(ref.scene)) {
        out.push({ severity: 'error', path, message: `entities[${index}].Trigger targets missing scene '${ref.scene}'` });
      }
    }
    for (const ref of actionSceneRefs(entity.components?.Interactable)) {
      if (ref.scene && !sceneTargets.has(ref.scene)) {
        out.push({ severity: 'error', path, message: `entities[${index}].Interactable targets missing scene '${ref.scene}'` });
      }
    }
    for (const ref of [...actionAudioRefs(entity.components?.Trigger), ...actionAudioRefs(entity.components?.Interactable)]) {
      if (ref.id && audioIds.size > 0 && !audioIds.has(ref.id)) {
        out.push({ severity: 'warning', path, message: `entities[${index}] references undeclared audio '${ref.id}'` });
      }
    }
    for (const ref of [...actionCombatRefs(entity.components?.Trigger), ...actionCombatRefs(entity.components?.Interactable)]) {
      if (ref.encounter && encounterIds.size > 0 && !encounterIds.has(ref.encounter)) {
        out.push({ severity: 'error', path, message: `entities[${index}] starts missing encounter '${ref.encounter}'` });
      }
    }

    const portal = record(entity.components?.Portal);
    if (portal) {
      if (typeof portal.scene === 'string' && !sceneTargets.has(portal.scene)) {
        out.push({ severity: 'error', path, message: `entities[${index}].Portal targets missing scene '${portal.scene}'` });
      }
      if (typeof portal.spawn === 'string' && !spawnPointExists(vfs, sceneTargets, scenes, portal.scene, portal.spawn)) {
        out.push({ severity: 'warning', path, message: `entities[${index}].Portal spawn '${portal.spawn}' was not found` });
      }
    }
  }
  return out;
}

function validateCombat(path: string, combat: CombatDocument): Diagnostic[] {
  const out: Diagnostic[] = [];
  if (!Array.isArray(combat.actors)) out.push({ severity: 'error', path, message: 'combat.actors must be an array' });
  if (!Array.isArray(combat.skills)) out.push({ severity: 'error', path, message: 'combat.skills must be an array' });
  if (!Array.isArray(combat.encounters)) out.push({ severity: 'error', path, message: 'combat.encounters must be an array' });
  const actorIds = new Set<string>();
  const skillIds = new Set<string>();
  for (const [index, actor] of (combat.actors ?? []).entries()) {
    if (!actor.id) out.push({ severity: 'error', path, message: `actors[${index}] is missing id` });
    if (actor.id && actorIds.has(actor.id)) out.push({ severity: 'error', path, message: `Duplicate actor '${actor.id}'` });
    if (actor.id) actorIds.add(actor.id);
    if (!actor.name) out.push({ severity: 'error', path, message: `actors[${index}] is missing name` });
    if (actor.side !== 'party' && actor.side !== 'enemy') out.push({ severity: 'error', path, message: `actors[${index}].side must be party or enemy` });
    for (const key of ['level', 'hp', 'mp', 'attack', 'defense', 'speed', 'xp']) {
      if ((actor as any)[key] !== undefined && !num((actor as any)[key])) out.push({ severity: 'error', path, message: `actors[${index}].${key} must be a number` });
    }
  }
  for (const [index, skill] of (combat.skills ?? []).entries()) {
    if (!skill.id) out.push({ severity: 'error', path, message: `skills[${index}] is missing id` });
    if (skill.id && skillIds.has(skill.id)) out.push({ severity: 'error', path, message: `Duplicate skill '${skill.id}'` });
    if (skill.id) skillIds.add(skill.id);
    if (!skill.name) out.push({ severity: 'error', path, message: `skills[${index}] is missing name` });
    if (skill.kind !== undefined && skill.kind !== 'damage' && skill.kind !== 'heal') out.push({ severity: 'error', path, message: `skills[${index}].kind must be damage or heal` });
    if (skill.target !== undefined && !['enemy', 'ally', 'self'].includes(skill.target)) out.push({ severity: 'error', path, message: `skills[${index}].target is invalid` });
    for (const key of ['power', 'mpCost']) {
      if ((skill as any)[key] !== undefined && !num((skill as any)[key])) out.push({ severity: 'error', path, message: `skills[${index}].${key} must be a number` });
    }
  }
  for (const [index, actor] of (combat.actors ?? []).entries()) {
    for (const skill of actor.skills ?? []) {
      if (!skillIds.has(skill)) out.push({ severity: 'error', path, message: `actors[${index}] references missing skill '${skill}'` });
    }
  }
  for (const [index, encounter] of (combat.encounters ?? []).entries()) {
    if (!encounter.id) out.push({ severity: 'error', path, message: `encounters[${index}] is missing id` });
    for (const actor of [...(encounter.party ?? []), ...(encounter.enemies ?? [])]) {
      if (!actorIds.has(actor)) out.push({ severity: 'error', path, message: `encounters[${index}] references missing actor '${actor}'` });
    }
    if (encounter.rewards) {
      if (encounter.rewards.xp !== undefined && !num(encounter.rewards.xp)) out.push({ severity: 'error', path, message: `encounters[${index}].rewards.xp must be a number` });
      if (encounter.rewards.gold !== undefined && !num(encounter.rewards.gold)) out.push({ severity: 'error', path, message: `encounters[${index}].rewards.gold must be a number` });
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

  const layer = record(components.Layer);
  if (layer) {
    if (layer.order !== undefined && !num(layer.order)) out.push({ severity: 'error', path, message: `entities[${index}].Layer.order must be a number` });
    if (layer.ySort !== undefined && typeof layer.ySort !== 'boolean') out.push({ severity: 'error', path, message: `entities[${index}].Layer.ySort must be a boolean` });
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
    if (camera.rotation !== undefined && !num(camera.rotation)) out.push({ severity: 'error', path, message: `entities[${index}].Camera.rotation must be a number` });
    if (camera.smoothing !== undefined && !num(camera.smoothing)) out.push({ severity: 'error', path, message: `entities[${index}].Camera.smoothing must be a number` });
    if (camera.clampToScene !== undefined && typeof camera.clampToScene !== 'boolean') out.push({ severity: 'error', path, message: `entities[${index}].Camera.clampToScene must be a boolean` });
    if (camera.followTag !== undefined && typeof camera.followTag !== 'string') out.push({ severity: 'error', path, message: `entities[${index}].Camera.followTag must be a string` });
  }

  const controller = record(components.PlayerController);
  if (controller) {
    if (controller.speed !== undefined && !num(controller.speed)) out.push({ severity: 'error', path, message: `entities[${index}].PlayerController.speed must be a number` });
    if (controller.mode !== undefined && !['smooth4', 'smooth8', 'grid4'].includes(String(controller.mode))) out.push({ severity: 'error', path, message: `entities[${index}].PlayerController.mode must be smooth4, smooth8, or grid4` });
    if (controller.stepSize !== undefined && !num(controller.stepSize)) out.push({ severity: 'error', path, message: `entities[${index}].PlayerController.stepSize must be a number` });
    if (controller.stepTime !== undefined && !num(controller.stepTime)) out.push({ severity: 'error', path, message: `entities[${index}].PlayerController.stepTime must be a number` });
  }

  const solid = record(components.Solid);
  if (solid && solid.enabled !== undefined && typeof solid.enabled !== 'boolean') {
    out.push({ severity: 'error', path, message: `entities[${index}].Solid.enabled must be a boolean` });
  }

  const animation = record(components.Animation);
  if (animation) {
    if (animation.current !== undefined && typeof animation.current !== 'string') out.push({ severity: 'error', path, message: `entities[${index}].Animation.current must be a string` });
    if (animation.clips !== undefined && !Array.isArray(animation.clips)) out.push({ severity: 'error', path, message: `entities[${index}].Animation.clips must be an array` });
  }

  const tilemap = record(components.Tilemap);
  if (tilemap) {
    if (!num(tilemap.columns) || !num(tilemap.rows) || !Array.isArray(tilemap.tiles)) out.push({ severity: 'error', path, message: `entities[${index}].Tilemap needs columns, rows, and tiles` });
    if (tilemap.tileWidth !== undefined && !num(tilemap.tileWidth)) out.push({ severity: 'error', path, message: `entities[${index}].Tilemap.tileWidth must be a number` });
    if (tilemap.tileHeight !== undefined && !num(tilemap.tileHeight)) out.push({ severity: 'error', path, message: `entities[${index}].Tilemap.tileHeight must be a number` });
  }

  const emitter = record(components.ParticleEmitter);
  if (emitter) {
    if (emitter.color !== undefined && !validColor(emitter.color)) out.push({ severity: 'error', path, message: `entities[${index}].ParticleEmitter.color must be #RRGGBB or #RRGGBBAA` });
    for (const key of ['rate', 'lifetime', 'speed', 'spread', 'radius', 'burst']) {
      if (emitter[key] !== undefined && !num(emitter[key])) out.push({ severity: 'error', path, message: `entities[${index}].ParticleEmitter.${key} must be a number` });
    }
  }

  const tween = record(components.Tween);
  if (tween) {
    if (!vec(tween.to, 2)) out.push({ severity: 'error', path, message: `entities[${index}].Tween.to must be [x, y]` });
    if (tween.duration !== undefined && !num(tween.duration)) out.push({ severity: 'error', path, message: `entities[${index}].Tween.duration must be a number` });
    if (tween.loop !== undefined && typeof tween.loop !== 'boolean') out.push({ severity: 'error', path, message: `entities[${index}].Tween.loop must be a boolean` });
  }

  const trigger = record(components.Trigger);
  if (trigger) {
    if (!vec(trigger.bounds, 4)) out.push({ severity: 'error', path, message: `entities[${index}].Trigger.bounds must be [x, y, width, height]` });
    if (trigger.oneShot !== undefined && typeof trigger.oneShot !== 'boolean') out.push({ severity: 'error', path, message: `entities[${index}].Trigger.oneShot must be a boolean` });
    if (!validActionCarrier(trigger)) out.push({ severity: 'error', path, message: `entities[${index}].Trigger action has invalid shape` });
  }

  const box = record(components.BoxCollider);
  if (box) {
    if (!num(box.width) || !num(box.height)) out.push({ severity: 'error', path, message: `entities[${index}].BoxCollider needs numeric width and height` });
    if (box.offset !== undefined && !vec(box.offset, 2)) out.push({ severity: 'error', path, message: `entities[${index}].BoxCollider.offset must be [x, y]` });
  }

  const interactable = record(components.Interactable);
  if (interactable) {
    if (!vec(interactable.bounds, 4)) out.push({ severity: 'error', path, message: `entities[${index}].Interactable.bounds must be [x, y, width, height]` });
    if (interactable.prompt !== undefined && typeof interactable.prompt !== 'string') out.push({ severity: 'error', path, message: `entities[${index}].Interactable.prompt must be a string` });
    if (interactable.repeatable !== undefined && typeof interactable.repeatable !== 'boolean') out.push({ severity: 'error', path, message: `entities[${index}].Interactable.repeatable must be a boolean` });
    if (!validActionCarrier(interactable)) out.push({ severity: 'error', path, message: `entities[${index}].Interactable action has invalid shape` });
  }

  const portal = record(components.Portal);
  if (portal) {
    if (!vec(portal.bounds, 4)) out.push({ severity: 'error', path, message: `entities[${index}].Portal.bounds must be [x, y, width, height]` });
    if (typeof portal.scene !== 'string') out.push({ severity: 'error', path, message: `entities[${index}].Portal.scene must be a string` });
    if (portal.spawn !== undefined && typeof portal.spawn !== 'string') out.push({ severity: 'error', path, message: `entities[${index}].Portal.spawn must be a string` });
  }

  const spawn = record(components.SpawnPoint);
  if (spawn) {
    if (typeof spawn.name !== 'string' || spawn.name.length === 0) out.push({ severity: 'error', path, message: `entities[${index}].SpawnPoint.name must be a non-empty string` });
  }

  return out;
}

function validActionCarrier(value: Record<string, unknown>): boolean {
  if (value.actions !== undefined) {
    return Array.isArray(value.actions) && value.actions.every(validTriggerAction);
  }
  return validTriggerAction(value.action);
}

function validTriggerAction(value: unknown): boolean {
  const action = record(value);
  if (!action) return false;
  if (Array.isArray(action.actions)) return action.actions.every(validTriggerAction);
  if (record(action.startDialogue)) return true;
  const showMessage = record(action.showMessage);
  if (showMessage) return typeof showMessage.text === 'string' && (showMessage.duration === undefined || num(showMessage.duration));
  const changeScene = record(action.changeScene);
  if (changeScene) {
    return (changeScene.index === undefined || num(changeScene.index))
      && (changeScene.name === undefined || typeof changeScene.name === 'string')
      && (changeScene.index !== undefined || changeScene.name !== undefined);
  }
  const setFlag = record(action.setFlag);
  if (setFlag) return typeof setFlag.name === 'string' && (setFlag.value === undefined || typeof setFlag.value === 'boolean');
  const startCombat = record(action.startCombat);
  if (startCombat) return typeof startCombat.encounter === 'string';
  const playSound = record(action.playSound);
  if (playSound) return typeof playSound.id === 'string'
    && (playSound.volume === undefined || num(playSound.volume))
    && (playSound.loop === undefined || typeof playSound.loop === 'boolean');
  const setEntityActive = record(action.setEntityActive);
  if (setEntityActive) return typeof setEntityActive.tag === 'string'
    && (setEntityActive.active === undefined || typeof setEntityActive.active === 'boolean');
  return false;
}

function actionSceneRefs(component: unknown): Array<{ scene?: string }> {
  const carrier = record(component);
  if (!carrier) return [];
  const actions = Array.isArray(carrier.actions) ? carrier.actions : [carrier.action];
  return actions.flatMap(actionSceneRefsFromAction);
}

function actionSceneRefsFromAction(value: unknown): Array<{ scene?: string }> {
  const action = record(value);
  if (!action) return [];
  if (Array.isArray(action.actions)) return action.actions.flatMap(actionSceneRefsFromAction);
  const changeScene = record(action.changeScene);
  if (typeof changeScene?.name === 'string') return [{ scene: changeScene.name }];
  return [];
}

function actionAudioRefs(component: unknown): Array<{ id: string }> {
  return actionsFromCarrier(component).flatMap((action) => {
    const playSound = record(record(action)?.playSound);
    return typeof playSound?.id === 'string' ? [{ id: playSound.id }] : [];
  });
}

function actionCombatRefs(component: unknown): Array<{ encounter: string }> {
  return actionsFromCarrier(component).flatMap((action) => {
    const startCombat = record(record(action)?.startCombat);
    return typeof startCombat?.encounter === 'string' ? [{ encounter: startCombat.encounter }] : [];
  });
}

function actionsSetFlag(component: unknown, names: string[]): boolean {
  return actionsFromCarrier(component).some((action) => {
    const setFlag = record(record(action)?.setFlag);
    return typeof setFlag?.name === 'string' && names.includes(setFlag.name);
  });
}

function actionsFromCarrier(component: unknown): unknown[] {
  const carrier = record(component);
  if (!carrier) return [];
  const raw = Array.isArray(carrier.actions) ? carrier.actions : [carrier.action];
  return raw.flatMap(flattenAction);
}

function flattenAction(value: unknown): unknown[] {
  const action = record(value);
  if (!action) return [];
  if (Array.isArray(action.actions)) return action.actions.flatMap(flattenAction);
  return [action];
}

function spawnPointExists(vfs: Vfs, sceneTargets: Set<string>, scenes: Array<{ name: string; path: string }>, sceneName: unknown, spawnName: string): boolean {
  if (typeof sceneName !== 'string' || !sceneTargets.has(sceneName)) return true;
  const sceneDecl = scenes.find((scene) => scene.name === sceneName);
  if (!sceneDecl) return true;
  const scene = parseScene(vfs, sceneDecl.path).scene;
  return Boolean(scene?.entities?.some((entity) => {
    const spawn = record(entity.components?.SpawnPoint);
    return spawn?.name === spawnName;
  }));
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
