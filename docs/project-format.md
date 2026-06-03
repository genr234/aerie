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

Scenes live under `assets/scenes/` and contain entities with components such as `Transform`, `Sprite`, `Camera`, `PlayerController`, and `Trigger`.

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

Scene trigger actions can start dialogue with:

```json
{ "startDialogue": { "id": "intro", "label": "hello" } }
```

Omit `id` to use the first dialogue declared in `game.json`.
