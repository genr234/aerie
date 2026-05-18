import "engine/core/event_bus" for EventBus

var nextId = 1
var entities = Map.new()

class Entity {

  static create(data) {
    var id = nextId
    nextId = nextId + 1

    var entity = {
      "id": id,
      "data": data == null ? Map.new() : data,
      "components": Map.new()
    }

    entities[id] = entity
    EventBus.emit("entity.created", entity)
    return id
  }

  static addComponent(id, name, data) {
    var entity = entities[id]
    if (entity == null) return false

    var components = entity["components"]
    components[name] = data

    EventBus.emit("entity.componentAdded", {
      "id": id,
      "name": name,
      "data": data
    })
    return true
  }

  static get(id) {
    return entities[id]
  }

  static list {
    return entities.values
  }

  static clear() {
    entities = Map.new()
    nextId = 1
    EventBus.emit("entity.cleared", null)
    return true
  }
}
