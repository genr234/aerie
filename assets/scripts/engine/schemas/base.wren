import "engine/core/state" for State

class BaseSchemas {
  static install() {
    State.defineModel("player", {
      "name": {"type": "string", "default": "Hero"},
      "hp": {"type": "number", "default": 100},
      "gold": {"type": "number", "default": 0}
    })

    State.defineModel("world", {
      "chapter": {"type": "number", "default": 1},
      "route": {"type": "string", "default": "main"}
    })

    State.defineRecordType("combat_round", {
      "turn": 0,
      "actor": null,
      "action": null
    })
  }
}
