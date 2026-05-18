import "engine/core/event_bus" for EventBus

var scenes = Map.new()
var activeSceneId = null

class Scene {

  static define(definitionMap) {
    var id = definitionMap["id"]
    if (id == null) Fiber.abort("Scene.define requires an 'id'.")

    var states = definitionMap["states"]
    if (states == null) states = ["idle"]

    var initial = definitionMap["initial"]
    if (initial == null) initial = states[0]

    var transitions = definitionMap["transitions"]
    if (transitions == null) transitions = Map.new()

    var scene = {
      "id": id,
      "states": states,
      "state": initial,
      "transitions": transitions,
      "onEnter": definitionMap["onEnter"],
      "onExit": definitionMap["onExit"]
    }

    scenes[id] = scene
    if (activeSceneId == null) activeSceneId = id

    EventBus.emit("scene.defined", scene)
    return id
  }

  static transition(sceneId, nextState) {
    var scene = scenes[sceneId]
    if (scene == null) return false

    var current = scene["state"]
    if (current == nextState) {
      activeSceneId = sceneId
      return true
    }
    var rules = scene["transitions"]

    var allowed = rules[current]
    if (allowed != null && !allowed.contains(nextState)) {
      EventBus.emit("scene.transitionRejected", {
        "sceneId": sceneId,
        "from": current,
        "to": nextState
      })
      return false
    }

    var onExit = scene["onExit"]
    if (onExit is Fn) onExit.call(scene)

    scene["state"] = nextState
    activeSceneId = sceneId

    var onEnter = scene["onEnter"]
    if (onEnter is Fn) onEnter.call(scene)

    EventBus.emit("scene.transitioned", {
      "sceneId": sceneId,
      "from": current,
      "to": nextState
    })
    return true
  }

  static get(sceneId) {
    return scenes[sceneId]
  }

  static active {
    return activeSceneId
  }

  static activeState {
    var scene = scenes[activeSceneId]
    if (scene == null) return null
    return scene["state"]
  }

  static clear() {
    scenes = Map.new()
    activeSceneId = null
    EventBus.emit("scene.cleared", null)
    return true
  }
}
