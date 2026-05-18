import "engine/core/event_bus" for EventBus

var stateData = Map.new()
var modelSchemas = Map.new()
var recordTypes = Map.new()
var records = Map.new()

var transactions = []
var nextTxId = 1

class State {

  static defineModel(name, schemaMap) {
    modelSchemas[name] = schemaMap
    if (stateData["models"] == null) stateData["models"] = Map.new()

    var defaults = Map.new()
    for (key in schemaMap.keys) {
      var field = schemaMap[key]
      if (field is Map && field.containsKey("default")) {
        defaults[key] = cloneValue(field["default"])
      } else {
        defaults[key] = cloneValue(field)
      }
    }

    stateData["models"][name] = defaults
    return defaults
  }

  static defineRecordType(name, defaultsMap) {
    recordTypes[name] = defaultsMap
    return defaultsMap
  }

  static createRecord(recordType, id, values) {
    var defaults = recordTypes[recordType]
    if (defaults == null) Fiber.abort("Unknown record type: %(recordType)")

    if (records[recordType] == null) records[recordType] = Map.new()

    var instance = cloneValue(defaults)
    if (values != null) {
      for (key in values.keys) {
        instance[key] = values[key]
      }
    }

    records[recordType][id] = instance
    EventBus.emit("state.recordCreated", {"type": recordType, "id": id})
    return instance
  }

  static transaction(name, fn) {
    var before = cloneValue(stateData)
    var result = fn.call(stateData)
    var after = cloneValue(stateData)

    var entry = {
      "id": nextTxId,
      "name": name,
      "before": before,
      "after": after
    }
    nextTxId = nextTxId + 1
    transactions.add(entry)

    EventBus.emit("state.transaction", entry)
    return result
  }

  static get(path) {
    if (path == null || path == "") return stateData

    var node = stateData
    var parts = segments(path)

    for (part in parts) {
      if (!(node is Map)) return null
      if (!node.containsKey(part)) return null
      node = node[part]
    }

    return node
  }

  static set(path, value) {
    if (path == null || path == "") {
      stateData = value
      EventBus.emit("state.changed", {"path": path, "value": value})
      return value
    }

    var parts = segments(path)
    var node = stateData

    if (parts.count > 1) {
      for (i in 0...parts.count - 1) {
        var part = parts[i]
        var next = node[part]
        if (!(next is Map)) {
          next = Map.new()
          node[part] = next
        }
        node = next
      }
    }

    node[parts[parts.count - 1]] = value
    EventBus.emit("state.changed", {"path": path, "value": value})
    return value
  }

  // Stage 1 behavior stays simple: update does direct mutation.
  static update(path, fn) {
    var current = get(path)
    var next = fn.call(current)
    return set(path, next)
  }

  static snapshot(strategy) {
    if (strategy == null || strategy == "models") {
      var out = Map.new()
      out["models"] = cloneValue(stateData["models"])
      out["transactions"] = cloneValue(transactions)
      return out
    }

    if (strategy == "models+records") {
      var out = snapshot("models")
      out["records"] = cloneValue(records)
      return out
    }

    if (strategy == "all") {
      return {
        "data": cloneValue(stateData),
        "models": cloneValue(modelSchemas),
        "recordTypes": cloneValue(recordTypes),
        "records": cloneValue(records),
        "transactions": cloneValue(transactions)
      }
    }

    Fiber.abort("Unknown snapshot strategy: %(strategy)")
  }

  static restore(snapshot) {
    if (snapshot.containsKey("data")) {
      stateData = cloneValue(snapshot["data"])
    } else {
      if (snapshot.containsKey("models")) {
        stateData["models"] = cloneValue(snapshot["models"])
      }
      if (snapshot.containsKey("records")) {
        records = cloneValue(snapshot["records"])
      }
    }

    if (snapshot.containsKey("transactions")) {
      transactions = cloneValue(snapshot["transactions"])
      nextTxId = transactions.count + 1
    }

    EventBus.emit("state.restored", {"snapshot": snapshot})
    return true
  }

  static transactionLog {
    return transactions
  }

  static clear() {
    stateData = Map.new()
    records = Map.new()
    transactions = []
    nextTxId = 1
    EventBus.emit("state.cleared", null)
    return true
  }

  static segments(path) {
    var parts = path.split(".")
    var clean = []
    for (part in parts) {
      if (part != "") clean.add(part)
    }
    return clean
  }

  static cloneValue(value) {
    if (value is Map) {
      var out = Map.new()
      for (key in value.keys) {
        out[key] = cloneValue(value[key])
      }
      return out
    }

    if (value is List) {
      var out = []
      for (item in value) {
        out.add(cloneValue(item))
      }
      return out
    }

    return value
  }
}
