var modules = Map.new()

class Module {

  static register(name, moduleMap) {
    if (moduleMap == null) Fiber.abort("Module.register requires a module map.")

    if (moduleMap["requires"] == null) moduleMap["requires"] = []
    if (moduleMap["config"] == null) moduleMap["config"] = Map.new()

    modules[name] = moduleMap
    return moduleMap
  }

  static requires(name, deps) {
    var mod = modules[name]
    if (mod == null) Fiber.abort("Unknown module: %(name)")

    mod["requires"] = deps
    return deps
  }

  static configure(name, options) {
    var mod = modules[name]
    if (mod == null) Fiber.abort("Unknown module: %(name)")

    var current = mod["config"]
    if (current == null) current = Map.new()

    if (options != null) {
      for (key in options.keys) {
        current[key] = options[key]
      }
    }

    mod["config"] = current
    return current
  }

  static get(name) {
    return modules[name]
  }

  static all {
    return modules
  }
}
