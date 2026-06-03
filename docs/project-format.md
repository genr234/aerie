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
  "window": { "width": 800, "height": 450, "title": "Tiny Story" }
}
```

Scenes live under `assets/scenes/` and contain entities with components such as `Transform`, `Sprite`, `Camera`, `PlayerController`, `Solid`, `Tilemap`, `Animation`, `ParticleEmitter`, `Tween`, and `Trigger`.

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

Dialogue assets live under `assets/dialogues/`. The v1 editor format is data-driven:

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

Nodes and choices may include `when` conditions such as `flag_name`, `!flag_name`, or `score >= 2`. Supported actions are `setFlag`, `changeScene`, and `showMessage`.

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

Scene trigger actions can start dialogue with:

```json
{ "startDialogue": { "id": "intro", "label": "hello" } }
```

Omit `id` to use the first dialogue declared in `game.json`.
