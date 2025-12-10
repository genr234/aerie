const rl = @import("raylib");
const characters = @import("engine/characters.zig");
const scenes = @import("engine/scenes.zig");

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "Hello Raylib + Zig!");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const playerTexture = try rl.loadTexture("assets/player.png");
    defer rl.unloadTexture(playerTexture);

    const scene = scenes.Scene.init(screenWidth, screenHeight);

    var player = characters.Player.init(playerTexture, scene, screenWidth / 2, screenHeight / 2);

    // Main game loop
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);

        player.update(rl.getFrameTime());
    }
}
