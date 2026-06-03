# Scripting Guide

Scripts are Wren modules declared in `game.json`. The default entry is `assets/scripts/main.wren` with class `Game`.

```wren
import "engine/api" for Events, State, Scene, UI, Save, Entity, CameraFx

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
- `Entity.exists`, `Entity.getPosition`, `Entity.setPosition`, `Entity.move`, and `Entity.despawn` manipulate tagged entities.
- `Entity.spawnRect` and `Entity.spawnCircle` create simple runtime entities.
- `Entity.setAnimation(tag, name)`, `Entity.tweenTo(tag, x, y, duration)`, and `Entity.emitParticles(tag, count)` add moment-to-moment game feel.
- `CameraFx.shake(intensity, duration)` shakes the active camera.
- `UI.text`, `UI.button`, `UI.panel`, and `UI.bar` draw simple UI.
- `Save.write(slot)`, `Save.load(slot)`, `Save.exists(slot)`, and `Save.clear(slot)` persist v1 JSON saves under `saves/`.
- `Inventory.add/count/has`, `Quest.start/complete/isActive/isComplete`, and `Combat.setHp/damage/heal/hp` provide tiny save-backed gameplay modules.

Example:

```wren
import "engine/api" for Entity, Inventory, Quest, Combat, CameraFx

class Game {
  static onBoot() {
    Inventory.add("key", 1)
    Quest.start("open_gate")
    Combat.setHp("slime", 12)
  }

  static onUpdate(dt) {
    Entity.setAnimation("player", "run")
    if (Inventory.has("key", 1)) Entity.tweenTo("gate", 700, 180, 0.5)
    if (Combat.hp("slime") <= 0 && !Quest.isComplete("open_gate")) {
      Quest.complete("open_gate")
      Entity.emitParticles("slime", 24)
      CameraFx.shake(8, 0.25)
    }
  }
}
```
