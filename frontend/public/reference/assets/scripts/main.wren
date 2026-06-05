import "engine/api" for Events, State, Scene, UI, Entity, CameraFx

class Game {
  static onBoot() {
    State.set("stone_touched", false)
    State.set("gate_open", false)
    State.set("stone_feedback", false)
    State.set("crossroads_done", false)
    State.set("clearing_seen", false)
    State.set("memory_touched", false)
    State.set("memory_feedback", false)
    State.set("touch_count", 0)
    Events.message("Follow the amber markers. Press E near things that glow.", 4)
  }

  static onUpdate(dt) {
    if (State.getFlag("stone_touched") && !State.getFlag("stone_feedback")) {
      State.set("stone_feedback", true)
      Entity.emitParticles("waystone_core", 24)
      CameraFx.shake(4, 0.18)
    }

    if (State.getFlag("stone_touched") && !State.getFlag("crossroads_done")) {
      State.set("crossroads_done", true)
      State.update("touch_count", Fn.new {|value| value + 1 })
    }

    if (State.getFlag("memory_touched") && !State.getFlag("memory_feedback")) {
      State.set("memory_feedback", true)
      Entity.emitParticles("memory_glow", 20)
      CameraFx.shake(5, 0.2)
    }

    if (Scene.currentIndex() == Scene.findIndex("clearing") && !State.getFlag("clearing_seen")) {
      State.set("clearing_seen", true)
      if (State.getFlag("stone_touched")) {
        Events.message("The clearing answers with a ring of warm light.", 4)
      } else {
        Events.message("The clearing is quiet, waiting for the stone.", 3)
      }
    }
  }

  static onDraw() {
    var place = Scene.currentIndex() == Scene.findIndex("clearing") ? "Clearing" : "Crossroads"
    var touched = State.getFlag("stone_touched") ? "awake" : "sleeping"
    var gate = State.getFlag("gate_open") ? "open" : "dim"
    var visits = State.get("touch_count")
    UI.text(18, 18, "%(place) | waystone: %(touched) | east gate: %(gate) | awakenings: %(visits)")
  }
}
