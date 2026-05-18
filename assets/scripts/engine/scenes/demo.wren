import "engine/core/scene" for Scene

class DemoScenes {
  static install() {
    Scene.define({
      "id": "intro",
      "states": ["idle", "choice", "done"],
      "initial": "idle",
      "transitions": {
        "idle": ["choice"],
        "choice": ["done"],
        "done": ["done"]
      }
    })

    Scene.define({
      "id": "camp",
      "states": ["idle", "rested"],
      "initial": "idle",
      "transitions": {
        "idle": ["rested"],
        "rested": ["idle"]
      }
    })
  }
}
