var registry = Map.new()

class Component {

  static define(name, handlersMap, configMap) {
    var component = {
      "name": name,
      "handlers": handlersMap == null ? Map.new() : handlersMap,
      "config": configMap == null ? Map.new() : configMap
    }

    registry[name] = component
    return component
  }

  static compose(baseComponent, handlersMap) {
    var composedHandlers = Map.new()
    for (key in baseComponent["handlers"].keys) {
      composedHandlers[key] = baseComponent["handlers"][key]
    }

    if (handlersMap != null) {
      for (key in handlersMap.keys) {
        composedHandlers[key] = handlersMap[key]
      }
    }

    return {
      "name": baseComponent["name"],
      "handlers": composedHandlers,
      "config": baseComponent["config"]
    }
  }

  static get(name) {
    return registry[name]
  }
}
