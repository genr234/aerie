import "engine/core/module" for Module
import "engine/core/script" for Script

var rpgConfig = {
    "turnOrder": "speed",
    "damageFormula": Fn.new {|atk, def| (atk - def) > 0 ? atk - def : 1 },
    "xpFormula": Fn.new {|enemies| enemies.count * 10 },
    "fleeSuccessRate": 0.75,
    "maxPartySize": 4,
    "maxEnemyCount": 6,
    "statusEffects": []
  }
var combatState = null

class RpgModule {

  static configure(options) {
    if (options != null) {
      for (key in options.keys) {
        rpgConfig[key] = options[key]
      }
    }

    Module.register("RpgModule", {
      "requires": [],
      "config": rpgConfig
    })

    return rpgConfig
  }

  static startCombat(party, enemies) {
    combatState = {
      "party": party,
      "enemies": enemies,
      "turn": 0,
      "active": true,
      "winner": null
    }

    Script.emit("onCombatStart", combatState)
    Script.emit("onTurnStart", {"turn": combatState["turn"]})
    return combatState
  }

  static resolveAction(actor, target, skill) {
    if (combatState == null || !combatState["active"]) return null

    var atk = actor["attack"]
    var def = target["defense"]
    var dmg = rpgConfig["damageFormula"].call(atk, def)

    target["hp"] = target["hp"] - dmg
    if (target["hp"] < 0) target["hp"] = 0

    Script.emit("onActionResolved", {
      "actor": actor,
      "target": target,
      "skill": skill,
      "damage": dmg
    })

    combatState["turn"] = combatState["turn"] + 1
    Script.emit("onTurnStart", {"turn": combatState["turn"]})

    return dmg
  }

  static endCombat(result) {
    if (combatState == null) return false

    combatState["active"] = false
    combatState["winner"] = result
    Script.emit("onCombatEnd", combatState)
    return true
  }

  static state {
    return combatState
  }
}
