import "engine/api" for Events

class Game {
  static onBoot() {
    Events.message("Starter scene loaded.", 3)
  }

  static onUpdate(dt) {}
}
