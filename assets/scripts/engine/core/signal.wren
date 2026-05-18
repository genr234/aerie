import "engine/core/state" for State

class Signal {
  static from(path) {
    return SourceSignal.new(path)
  }

  static derive(dependencies, fn) {
    return DerivedSignal.new(dependencies, fn)
  }

  static effect(dependencies, fn) {
    var effect = EffectSignal.new(dependencies, fn)
    effect.run()
    return effect
  }
}

class SourceSignal {
  construct new(path) {
    this.path = path
  }

  value {
    return State.get(this.path)
  }

  value=(newValue) {
    State.set(this.path, newValue)
  }
}

class DerivedSignal {
  construct new(dependencies, fn) {
    this.dependencies = dependencies
    this.fn = fn
  }

  value {
    return this.fn.call()
  }
}

class EffectSignal {
  construct new(dependencies, fn) {
    this.dependencies = dependencies
    this.fn = fn
    this.last = null
  }

  run() {
    var current = []
    for (dep in this.dependencies) {
      current.add(dep.value)
    }

    if (this.last == null || !same(this.last, current)) {
      this.fn.call()
      this.last = current
      return true
    }

    return false
  }

  same(left, right) {
    if (left.count != right.count) return false
    for (i in 0...left.count) {
      if (left[i] != right[i]) return false
    }
    return true
  }
}
