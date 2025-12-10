const rl = @import("raylib");
const characters = @import("engine/characters.zig");
const scenes = @import("engine/scenes.zig");
const root = @import("root.zig");

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "Test Game");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const playerTexture = try rl.loadTexture("assets/player.png");
    defer rl.unloadTexture(playerTexture);

    var scene = scenes.Scene.init(screenWidth, screenHeight);
    scene.camera.offset = rl.Vector2{
        .x = root.F32(screenWidth) / 2.0,
        .y = root.F32(screenHeight) / 2.0,
    };
    
    var player = characters.Player.init(playerTexture, scene, screenWidth / 2, screenHeight / 2);


    // Main game loop
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(.white);

        rl.beginMode2D(scene.camera);
        rl.drawCircle(15, 15, 4, .blue);

        player.update(rl.getFrameTime());
        scene.camera.target = rl.Vector2{
            .x = player.sprite.x + root.F32(player.texture.width) / 2.0,
            .y = player.sprite.y + root.F32(player.texture.height) / 2.0,
        };

        rl.endMode2D();
        rl.endDrawing();
    }
}
