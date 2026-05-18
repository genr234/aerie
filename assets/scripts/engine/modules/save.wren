import "engine/core/module" for Module
import "engine/core/state" for State
import "engine/core/script" for Script

var saveConfig = {
    "slots": 3,
    "autosave": true,
    "autosaveInterval": 300,
    "format": "json",
    "includeRecords": false,
    "migrations": []
  }
class SaveModule {
  static configure(options) {
    if (options != null) {
      for (key in options.keys) {
        saveConfig[key] = options[key]
      }
    }

    Module.register("SaveModule", {
      "requires": [],
      "config": saveConfig
    })

    return saveConfig
  }

  static save() {
    Script.emit("onBeforeSave", {"config": saveConfig})

    var strategy = saveConfig["includeRecords"] ? "models+records" : "models"
    var snapshot = State.snapshot(strategy)

    Script.emit("onAfterSave", {"snapshot": snapshot})
    return snapshot
  }

  static load(payload) {
    if (payload == null) {
      Script.emit("onLoadFailed", {"reason": "empty payload"})
      return false
    }

    var migrated = runMigrations(payload)
    State.restore(migrated)
    Script.emit("onLoad", {"snapshot": migrated})
    return true
  }

  static runMigrations(payload) {
    var migrations = saveConfig["migrations"]
    if (migrations == null) return payload

    var data = payload
    for (migration in migrations) {
      data = migration.call(data)
    }
    return data
  }
}
