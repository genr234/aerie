import "engine/api" for Events, State, Scene, UI

class Game {
  static onBoot() {
    State.set("stone_touched", false)
    State.set("crossroads_done", false)
    State.set("clearing_seen", false)
    State.set("touch_count", 0)
    Events.message("Walk to the lit stone.", 3)
  }

  static onUpdate(dt) {
    if (State.getFlag("stone_touched") && !State.getFlag("crossroads_done")) {
      State.set("crossroads_done", true)
      State.update("touch_count", Fn.new {|value| value + 1 })
      Events.message("The stone remembers you. The path opens.", 3)
      Scene.go("clearing")
    }

    if (Scene.currentIndex() == Scene.findIndex("clearing") && !State.getFlag("clearing_seen")) {
      State.set("clearing_seen", true)
      if (State.getFlag("stone_touched")) {
        Events.message("The clearing answers because the stone is awake.", 4)
      } else {
        Events.message("The clearing is quiet.", 3)
      }
    }
  }

  static onDraw() {
    var place = Scene.currentIndex() == Scene.findIndex("clearing") ? "Clearing" : "Crossroads"
    var touched = State.getFlag("stone_touched") ? "awake" : "sleeping"
    UI.text(18, 18, "%(place) | stone: %(touched)")
  }
}
