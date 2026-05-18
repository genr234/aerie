import "engine/core/genome" for Genome

class BaseGenomes {
  static install() {
    Genome.register("Actor", {
      "name": "Actor",
      "components": ["Transform"],
      "state": {
        "hp": 100,
        "maxHp": 100,
        "attack": 8,
        "defense": 4
      },
      "tags": ["actor"]
    })

    Genome.register("Player", {
      "name": "Player",
      "extends": "Actor",
      "components": ["PlayerController"],
      "state": {
        "name": "Player"
      },
      "tags": ["player"]
    })
  }
}
