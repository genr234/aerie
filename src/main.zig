const rl = @import("raylib");
const characters = @import("engine/characters.zig");
const scenes = @import("engine/scenes.zig");
const dialogue = @import("engine/dialogue.zig");
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

    var dialogueLines = [_][]const u8{
        "Welcome!",
        "Press SPACE to continue.",
    };
    var gameDialogue = dialogue.Dialogue.init(&dialogueLines);
    gameDialogue.start();

    // Main game loop
    while (!rl.windowShouldClose()) {
        const deltaTime = rl.getFrameTime();

        // Handle dialogue input
        if (gameDialogue.active and rl.isKeyPressed(.space)) {
            gameDialogue.advance();
        }

        rl.beginDrawing();
        rl.clearBackground(.white);

        // Update and render game
        rl.beginMode2D(scene.camera);
        rl.drawCircle(15, 15, 4, .blue);
        rl.drawRectangle(300, 200, 50, 50, .green);

        try player.update(deltaTime, gameDialogue.active);

        scene.camera.target = rl.Vector2{
            .x = player.sprite.x + root.F32(player.texture.width) / 2.0,
            .y = player.sprite.y + root.F32(player.texture.height) / 2.0,
        };

        rl.endMode2D();

        // Render scene message
        if (scene.messageTimer > 0.0) {
            if (scene.message) |msg| {
                rl.drawText(msg, 10, 10, 20, .red);
            }
            scene.messageTimer -= deltaTime;
        }

        // Draw dialogue
        gameDialogue.draw(20, screenHeight - 120, screenWidth - 40, 100);

        rl.endDrawing();
    }
}
