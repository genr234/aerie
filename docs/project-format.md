# Project Format

Aerie projects are folders with a `game.json` manifest.

```json
{
  "id": "tiny-story",
  "title": "Tiny Story",
  "version": "0.1.0",
  "entry": { "module": "main", "class": "Game" },
  "start_scene": "crossroads",
  "scenes": [{ "name": "crossroads", "path": "assets/scenes/crossroads.json" }],
  "scripts": [{ "name": "main", "path": "assets/scripts/main.wren" }],
  "dialogues": [{ "name": "intro", "path": "assets/dialogues/intro.json" }],
  "combat": { "path": "assets/combat/combat.json" },
  "window": { "width": 800, "height": 450, "title": "Tiny Story" }
}
```

Audio is optional. Omit `audio` entirely for a silent project. Features such as `Portal` and `Interactable` never require audio assets; sound cues only play when a matching id is declared and loaded. When present, paths are resolved relative to `assets/`. The editor's asset import button declares `.wav`, `.mp3`, and `.ogg` files automatically under `audio.sounds` or `audio.music`.

```json
{
  "audio": {
    "sounds": [{ "id": "interact", "path": "audio/interact.wav" }],
    "music": [{ "id": "ambient", "path": "audio/ambient.ogg" }]
  }
}
```

Scenes live under `assets/scenes/` and contain entities with components such as `Transform`, `Sprite`, `Layer`, `Camera`, `PlayerController`, `Solid`, `BoxCollider`, `Tilemap`, `Animation`, `ParticleEmitter`, `Tween`, `Trigger`, `Interactable`, `Portal`, and `SpawnPoint`.

Gameplay-oriented components are intentionally small and data-first:

```json
{
  "tag": "wall",
  "components": {
    "Transform": { "position": [160, 220] },
    "Rect": { "width": 80, "height": 24, "color": "#53606a" },
    "Solid": { "enabled": true }
  }
}
```

Add `Layer` to opt into explicit render ordering. Scenes without any `Layer` component keep the legacy component-order renderer. Once a scene uses `Layer`, renderable entities are sorted by `order`; entities with `ySort` enabled are ordered by their lower screen position within the same layer.

```json
{
  "Transform": { "position": [96, 238] },
  "Sprite": { "texture": "hero.png" },
  "Layer": { "order": 20, "ySort": true }
}
```

Tilemaps use numeric tile ids. `0` is empty, palette entries color tile ids starting at `1`, and `solidTiles` marks ids that block player movement.

```json
{
  "tag": "ground",
  "components": {
    "Transform": { "position": [0, 0] },
    "Tilemap": {
      "columns": 4,
      "rows": 3,
      "tileWidth": 16,
      "tileHeight": 16,
      "tiles": [1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1],
      "solidTiles": [1],
      "palette": ["#5f8f5f"]
    }
  }
}
```

Named sprite animations are declared beside `Sprite`. Each clip selects a frame range from the sprite sheet.

```json
{
  "Sprite": { "texture": "hero.png", "frameWidth": 32, "frameHeight": 32 },
  "Animation": {
    "current": "idle",
    "clips": [
      { "name": "idle", "start": 0, "frames": 4, "fps": 6, "loop": true },
      { "name": "run", "start": 4, "frames": 6, "fps": 12, "loop": true }
    ]
  }
}
```

`ParticleEmitter` adds lightweight visual effects, and `Tween` moves an entity toward a target position over time.

Combat assets are declared as one JSON file in `game.json`. The file contains `actors`, `skills`, and `encounters`.

```json
{
  "actors": [
    { "id": "hero", "name": "Hero", "side": "party", "hp": 28, "mp": 8, "attack": 7, "defense": 2, "speed": 7, "skills": ["fire"] },
    { "id": "slime", "name": "Slime", "side": "enemy", "hp": 12, "mp": 0, "attack": 4, "defense": 1, "speed": 4 }
  ],
  "skills": [
    { "id": "fire", "name": "Fire", "kind": "damage", "power": 6, "mpCost": 3, "target": "enemy" }
  ],
  "encounters": [
    { "id": "slime_duo", "party": ["hero"], "enemies": ["slime", "slime"], "rewards": { "xp": 10, "gold": 3 } }
  ]
}
```

Dialogue assets live under `assets/dialogues/`. Multiple dialogue files may be declared; `startDialogue.id` selects the matching dialogue at runtime, and the editor validates ids and node labels before Play or Export. The v1 editor format is data-driven:

```json
{
  "id": "intro",
  "start": "hello",
  "nodes": [
    { "id": "hello", "speaker": "Guide", "text": "Welcome.", "next": "choice" },
    {
      "id": "choice",
      "text": "Where next?",
      "choices": [
        { "text": "The clearing", "next": "done", "actions": [{ "changeScene": { "name": "clearing" } }] }
      ]
    },
    { "id": "done", "text": "Then go." }
  ]
}
```

Nodes and choices may include `when` conditions such as `flag_name`, `!flag_name`, or `score >= 2`. Supported dialogue actions are `setFlag`, `changeScene`, and `showMessage`.

Scene `Trigger` and `Interactable` actions also support `playSound`, `setEntityActive`, `startDialogue`, and `startCombat`, and may be grouped with `actions`.

The editor may add optional layout metadata for the node graph:

```json
{
  "editor": {
    "nodes": {
      "hello": { "x": 40, "y": 40 }
    }
  }
}
```

This metadata is ignored by the runtime and can be omitted.

`PlayerController` supports small opinionated movement modes. `smooth4` is the default top-down narrative feel, `smooth8` allows normalized diagonal movement, and `grid4` moves one tile-sized step at a time.

```json
{
  "PlayerController": { "speed": 125, "mode": "smooth4" },
  "BoxCollider": { "width": 14, "height": 10, "offset": [9, 20] }
}
```

If a player has a sprite but no `BoxCollider`, the runtime creates a small foot collider by default.

Camera follow can be smoothed and clamped to scene bounds:

```json
{
  "Camera": {
    "offset": [400, 225],
    "zoom": 1.0,
    "smoothing": 12,
    "clampToScene": true,
    "followTag": "player"
  }
}
```

`Interactable` runs actions only when the player presses interact while facing/reaching the bounds. This is preferred for talking, inspecting, switches, and intentional encounters.

```json
{
  "Interactable": {
    "bounds": [510, 170, 152, 132],
    "prompt": "Wake waystone",
    "repeatable": false,
    "actions": [
      { "setFlag": { "name": "stone_touched", "value": true } },
      { "showMessage": { "text": "The waystone hums.", "duration": 3 } }
    ]
  }
}
```

`Portal` changes scenes on touch and can place the persistent player at a named `SpawnPoint` in the destination scene:

```json
{
  "Portal": { "bounds": [720, 182, 52, 124], "scene": "clearing", "spawn": "from_crossroads" }
}
```

```json
{
  "Transform": { "position": [124, 245] },
  "SpawnPoint": { "name": "from_crossroads" }
}
```

Scene trigger actions can start dialogue with:

```json
{ "startDialogue": { "id": "intro", "label": "hello" } }
```

Omit `id` to use the first dialogue declared in `game.json`. The editor provides node pickers for declared dialogue files; use raw JSON only for unusual hand-authored cases.

Scene trigger actions can start combat with:

```json
{ "startCombat": { "encounter": "slime_duo" } }
```

The editor can create a starter combat database from the Combat workbench or Explorer toolbar. Scene action editors only enable `startCombat` once at least one encounter exists.
