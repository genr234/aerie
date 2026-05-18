import "engine/core/entity" for Entity
import "engine/core/state" for State

var registry = Map.new()

class Genome {

  static register(name, genomeMap) {
    registry[name] = genomeMap
    return genomeMap
  }

  static instantiate(nameOrMap) {
    var flat = flatten(nameOrMap)

    var entityId = Entity.create({"genome": flat["name"]})

    var components = flat["components"]
    if (components != null) {
      for (componentName in components) {
        Entity.addComponent(entityId, componentName, Map.new())
      }
    }

    var state = flat["state"]
    if (state != null) {
      for (key in state.keys) {
        State.set("entities.%(entityId).%(key)", state[key])
      }
    }

    return entityId
  }

  static merge(base, override) {
    return deepMerge(clone(base), override)
  }

  static flatten(nameOrMap) {
    var raw = nameOrMap
    if (nameOrMap is String) raw = registry[nameOrMap]
    if (raw == null) Fiber.abort("Unknown genome: %(nameOrMap)")

    var parentName = raw["extends"]
    if (parentName == null) return clone(raw)

    var parent = flatten(parentName)
    return deepMerge(parent, raw)
  }

  static deepMerge(left, right) {
    var out = clone(left)

    if (right == null) return out

    for (key in right.keys) {
      var l = out[key]
      var r = right[key]

      if (l is Map && r is Map) {
        out[key] = deepMerge(l, r)
      } else if (l is List && r is List) {
        var merged = []
        for (item in l) merged.add(item)
        for (item in r) merged.add(item)
        out[key] = merged
      } else {
        out[key] = clone(r)
      }
    }

    return out
  }

  static clone(value) {
    if (value is Map) {
      var out = Map.new()
      for (key in value.keys) {
        out[key] = clone(value[key])
      }
      return out
    }

    if (value is List) {
      var out = []
      for (item in value) {
        out.add(clone(item))
      }
      return out
    }

    return value
  }
}
