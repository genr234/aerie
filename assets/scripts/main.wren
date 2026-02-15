import "engine/api" for Events, Input

class Game {
  static onBoot() {
    Events.message("Welcome to the Game!", 3.0)
    Input.onAnyKey("d") { Events.message("You pressed the E key!", 2.0) }
  }

  static onUpdate(dt) {
    // no-op
  }
}
