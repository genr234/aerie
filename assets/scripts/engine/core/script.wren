import "engine/core/event_bus" for EventBus

var fibers = Map.new()
var checkpoints = Map.new()
var currentScript = null

class Script {

  static on(eventName, handlerFn) {
    return EventBus.on(eventName, handlerFn)
  }

  static emit(eventName, payloadMap) {
    return EventBus.emit(eventName, payloadMap)
  }

  static spawn(name, fiberFn) {
    var fiber = Fiber.new {
      currentScript = name
      fiberFn.call()
      currentScript = null
    }

    fibers[name] = fiber
    return resume(name, null)
  }

  static checkpoint(id) {
    if (currentScript == null) return false
    checkpoints[currentScript] = id
    EventBus.emit("script.checkpoint", {
      "script": currentScript,
      "checkpoint": id
    })
    return true
  }

  static awaitSignal(signal, predicateFn) {
    return predicateFn.call(signal.value)
  }

  static resume(name, checkpointId) {
    var fiber = fibers[name]
    if (fiber == null) return null

    if (checkpointId != null) {
      checkpoints[name] = checkpointId
    }

    currentScript = name
    var result = fiber.call()
    currentScript = null

    EventBus.emit("script.resumed", {
      "script": name,
      "checkpoint": checkpoints[name]
    })

    return result
  }

  static getCheckpoint(name) {
    return checkpoints[name]
  }

  static clear() {
    fibers = Map.new()
    checkpoints = Map.new()
    currentScript = null
    EventBus.clear(null)
    return true
  }
}
