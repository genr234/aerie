import "events" for

class Game {
  static onBoot() {
    Events.message("Welcome to the Game!", 3.0)
  }

  static onUpdate(dt) {
    // no-op
  }
}
