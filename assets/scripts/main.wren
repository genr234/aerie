import "engine/api" for UI
import "engine/core/state" for State
import "engine/core/scene" for Scene
import "engine/core/script" for Script
import "engine/core/signal" for Signal
import "engine/core/module" for Module
import "engine/core/genome" for Genome
import "engine/core/entity" for Entity
import "engine/modules/save" for SaveModule
import "engine/modules/vn" for VNModule
import "engine/modules/rpg" for RpgModule
import "engine/schemas/base" for BaseSchemas
import "engine/genomes/base" for BaseGenomes
import "engine/scenes/demo" for DemoScenes

class Game {
  static onBoot() {
    BaseSchemas.install()
    BaseGenomes.install()
    DemoScenes.install()

    SaveModule.configure({ "autosave": true, "slots": 2 })
    VNModule.configure(null)
    RpgModule.configure(null)

    State.defineModel("player", {
      "name": { "type": "string", "default": "Explorer" },
      "hp": { "type": "number", "default": 80 },
      "gold": { "type": "number", "default": 5 }
    })
    State.defineRecordType("combat_round", { "turn": 0, "actor": null, "target": null })

    Module.register("GameModule", { "requires": ["SaveModule"], "config": { "difficulty": "easy" } })
    Module.requires("GameModule", [])

    Script.spawn("main", Fn.new { Game.engineLoop() })

    State.transaction("boot", Fn.new {|state|
      State.set("scene.current", "intro")
      State.set("runtime.saveCount", 0)
      return state
    })

    Script.emit("scene.initialized", { "scene": State.get("scene.current") })
  }

  static engineLoop() {
    Script.checkpoint("booted")

    while (true) {
      State.update("runtime.tick", Fn.new {|value|
        if (value == null) return 1
        return value + 1
      })

      var actor = Genome.instantiate("Player")
      Entity.addComponent(actor, "NarrativeActor", { "mood": "curious" })

      var line = State.get("story.lastChoice")
      if (line == null) {
        State.set("story.lastChoice", "none")
      }

      Script.emit("frame.tick", { "tick": State.get("runtime.tick") })

      if (State.get("runtime.tick") % 10 == 0) {
        SaveModule.save()
        State.update("runtime.saveCount", Fn.new {|value|
          if (value == null) return 1
          return value + 1
        })
        Script.emit("game.saved", { "slot": State.get("runtime.saveCount") })
      }

      Fiber.yield()
    }
  }

  static onUpdate(dt) {}

  static onDraw() {
    var currentScene = State.get("scene.current")
    var frame = State.get("runtime.tick")
    var gold = State.get("models.player.gold")
    var message = "Gold: %(gold)"

    drawPanel("Scene: %(currentScene)", 32, 32)
    drawPanel("Frame: %(frame)", 32, 72)
    drawPanel("Gold: %(gold)", 32, 112)
    drawPanel("Message: %(message)", 32, 152)

    if (UI.button(32, 200, 220, 40, "Advance Scene")) {
      var next = currentScene == "intro" ? "camp" : "intro"
      Scene.transition(next, "idle")
      State.set("scene.current", next)
      Script.emit("scene.changed", { "scene": next })
    }

    if (UI.button(280, 200, 220, 40, "Spend 2 Gold")) {
      State.update("models.player.gold", Fn.new {|value|
        var current = value
        if (current == null) current = 0
        return current - 2
      })
      Script.emit("gold.changed", { "gold": State.get("models.player.gold") })
    }
  }

  static drawPanel(text, x, y) {
    UI.panel(x, y, 460, 34)
    UI.text(x + 8, y + 8, text)
  }
}
