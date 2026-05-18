var handlers = Map.new()

class EventBus {

  static on(eventName, handler) {
    var eventHandlers = handlers[eventName]
    if (eventHandlers == null) {
      eventHandlers = []
      handlers[eventName] = eventHandlers
    }
    eventHandlers.add(handler)
    return eventHandlers.count
  }

  static emit(eventName, payload) {
    var eventHandlers = handlers[eventName]
    if (eventHandlers == null) return 0

    for (handler in eventHandlers) {
      handler.call(payload)
    }
    return eventHandlers.count
  }

  static clear(eventName) {
    if (eventName == null) {
      handlers = Map.new()
      return true
    }

    handlers.remove(eventName)
    return true
  }
}
