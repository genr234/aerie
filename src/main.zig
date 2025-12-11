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

    var player = try characters.Player.init(playerTexture, &scene, screenWidth / 2, screenHeight / 2);

    try player.addTrigger(rl.Rectangle{
        .x = 300,
        .y = 200,
        .width = 50,
        .height = 50,
    }, characters.TriggerAction{ .print_message = "Collision!" });

    // Main game loop
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(.white);

        rl.beginMode2D(scene.camera);
        rl.drawCircle(15, 15, 4, .blue);
        rl.drawRectangle(300, 200, 50, 50, .green);

        try player.update(rl.getFrameTime());
        scene.camera.target = rl.Vector2{
            .x = player.sprite.x + root.F32(player.texture.width) / 2.0,
            .y = player.sprite.y + root.F32(player.texture.height) / 2.0,
        };

        rl.endMode2D();

        // update and render scene message (in screen coordinates, outside camera transform)
        if (scene.messageTimer > 0.0) {
            if (scene.message) |msg| {
                rl.drawText(msg, 10, 10, 20, .red);
            }
            scene.messageTimer -= rl.getFrameTime();
            if (scene.messageTimer <= 0.0) {
                scene.message = null;
                scene.messageTimer = 0.0;
            }
        }

        rl.endDrawing();
    }
}
