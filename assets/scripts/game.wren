// Minimal scripting entry point.
// The Zig runtime calls Game.onBoot() once and Game.onUpdate(dt) every frame.

foreign class Events {
  foreign static showMessage(text, duration)
}

foreign class Story {
  foreign static setFlag(name, value)
  foreign static getFlag(name)
}

foreign class Scene {
  foreign static change(index)
  foreign static changeByName(name)
}

foreign class Dialogue {
  foreign static start()
  foreign static startAt(label)
}

class Game {
  static onBoot() {
    Events.showMessage("Wren booted!", 2)
    Story.setFlag("wren_booted", true)
  }

  static onUpdate(dt) {
    // Example: once per second, post a toast.
    if (Story.getFlag("wren_booted")) {
      // (Keep it simple; you can expand this later.)
    }
  }
}
