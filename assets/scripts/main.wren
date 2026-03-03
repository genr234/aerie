// Simple Bitsy-like game example
// Use Engine state for persistence, or just track in closures for simple games

import "engine/api" for Engine, UI

class Game {
  static onBoot() {
    // Initialize state in Engine (persists across scene changes)
    Engine.setInt("score", 0)
    Engine.setInt("health", 100)
    
    Engine.showMessage("Welcome to the Game!", 2.0)
    
    Engine.onKeyPressed("space") {
      Engine.addInt("score", 10)
      Engine.showMessage("+10 points!", 1.0)
    }
    
    Engine.onKeyPressed("r") {
      Engine.setInt("score", 0)
      Engine.setInt("health", 100)
      Engine.showMessage("Reset!", 1.0)
    }
  }

  static onUpdate(dt) {
    // Game logic here
  }
  
  static onDraw() {
    // HUD panel
    UI.panel(10, 10, 200, 100)
    
    // Score text
    UI.text(20, 20, "Score: %(Engine.getInt("score"))")
    
    // Health bar
    UI.text(20, 45, "Health:")
    UI.bar(20, 65, 180, 15, Engine.getInt("health"), 100)
    
    // Interactive button
    if (UI.button(10, 120, 100, 35, "Click Me!")) {
      Engine.addInt("score", 1)
      Engine.showMessage("+1 point!", 0.5)
    }
    
    // Reset button
    if (UI.button(120, 120, 100, 35, "Reset")) {
      Engine.setInt("score", 0)
      Engine.setInt("health", 100)
    }
    
    // Text input field
    UI.text(10, 170, "Enter name:")
    if (UI.inputField(100, 165, 150, 30, 1)) {
      var name = UI.getInputText()
      Engine.setString("playerName", name)
      Engine.showMessage("Hello, %(name)!", 2.0)
      UI.clearInput()
    }
    
    // Show current name if set
    var currentName = Engine.getString("playerName")
    if (currentName != "") {
      UI.text(260, 170, "Player: %(currentName)")
    }
    
    // Instructions
    UI.text(10, 210, "Press SPACE for +10 pts")
    UI.text(10, 230, "Press R to reset")
  }
}
