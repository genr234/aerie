# Scripting Guide

Scripts are Wren modules declared in `game.json`. The default entry is `assets/scripts/main.wren` with class `Game`.

```wren
import "engine/api" for Events, State, Scene, UI, Save

class Game {
  static onBoot() {
    Events.message("Hello", 2)
  }

  static onUpdate(dt) {}

  static onDraw() {
    UI.text(18, 18, "HUD")
  }
}
```

Core APIs:

- `Events.message(text, duration)` shows a temporary message.
- `State.setFlag/getFlag`, `State.setInt/getInt`, `State.setFloat/getFloat`, and `State.setString/getString` store story state.
- `Scene.go(name)`, `Scene.currentIndex()`, and `Scene.findIndex(name)` control scenes.
- `UI.text`, `UI.button`, `UI.panel`, and `UI.bar` draw simple UI.
- `Save.write(slot)`, `Save.load(slot)`, `Save.exists(slot)`, and `Save.clear(slot)` persist v1 JSON saves under `saves/`.

