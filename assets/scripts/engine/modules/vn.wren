import "engine/core/module" for Module
import "engine/core/script" for Script

var vnConfig = {
  "autoAdvance": false,
  "autoAdvanceDelay": 3000,
  "typingSpeed": 30,
  "skipMode": "seen",
  "choiceTimeout": null,
  "historyLength": 100
}

var dialogueState = null

class VNModule {

  static configure(options) {
    if (options != null) {
      for (key in options.keys) {
        vnConfig[key] = options[key]
      }
    }

    Module.register("VNModule", {
      "requires": [],
      "config": vnConfig
    })

    return vnConfig
  }

  static start(dialogueModel) {
    dialogueState = {
      "model": dialogueModel,
      "index": 0,
      "active": true,
      "history": []
    }

    Script.emit("onDialogueStart", {"dialogue": dialogueModel})
    emitCurrentLine()
    return dialogueState
  }

  static advance(input) {
    if (dialogueState == null || !dialogueState["active"]) return null

    var model = dialogueState["model"]
    var lines = model["lines"]

    var current = lines[dialogueState["index"]]
    if (current["choices"] != null && input != null) {
      Script.emit("onChoiceMade", {"choice": input})
    }

    dialogueState["index"] = dialogueState["index"] + 1
    if (dialogueState["index"] >= lines.count) {
      dialogueState["active"] = false
      Script.emit("onDialogueEnd", {"dialogue": model})
      return null
    }

    emitCurrentLine()
    return lines[dialogueState["index"]]
  }

  static state {
    return dialogueState
  }

  static emitCurrentLine() {
    var line = dialogueState["model"]["lines"][dialogueState["index"]]
    var history = dialogueState["history"]
    history.add(line)

    if (history.count > vnConfig["historyLength"]) {
      history.removeAt(0)
    }

    Script.emit("onLineDisplayed", {"line": line, "index": dialogueState["index"]})
  }
}
