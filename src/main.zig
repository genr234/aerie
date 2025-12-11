const rl = @import("raylib");
const std = @import("std");
const characters = @import("engine/characters.zig");
const scenes = @import("engine/scenes.zig");
const dialogue = @import("engine/dialogue.zig");
const gameobjects = @import("engine/gameobjects.zig");
const root = @import("root.zig");

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "Test Game");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const playerTexture = try rl.loadTexture("assets/player.png");
    defer rl.unloadTexture(playerTexture);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var manager = try scenes.SceneManager.initWithAllocator(&allocator, 4);
    defer manager.deinit();

    var cs = &manager.scenes[0];
    cs.* = scenes.Scene.init(screenWidth, screenHeight, null, null, null, null);
    cs.camera.offset = rl.Vector2{
        .x = root.F32(screenWidth) / 2.0,
        .y = root.F32(screenHeight) / 2.0,
    };

    // Add origin circle GameObject
    var circleGo = gameobjects.GameObject.init("origin_circle", gameobjects.GameObjectData{
        .circle = .{
            .radius = 4,
            .color = rl.Color.blue,
        },
    });
    circleGo.position = rl.Vector2{ .x = 15, .y = 15 };
    _ = cs.addGameObject(circleGo);

    // Add trigger zone rectangle GameObject
    var triggerGo = gameobjects.GameObject.init("trigger_zone", gameobjects.GameObjectData{
        .rectangle = .{
            .width = 50,
            .height = 50,
            .color = rl.Color.green,
        },
    });
    triggerGo.position = rl.Vector2{ .x = 300, .y = 200 };

    // Add trigger to the GameObject
    var dialogueLines = [_][]const u8{
        "Welcome!",
        "Press SPACE to continue.",
    };
    var gameDialogue = dialogue.Dialogue.init(&dialogueLines, "Narrator");
    triggerGo.addTrigger(rl.Rectangle{
        .x = 300,
        .y = 200,
        .width = 50,
        .height = 50,
    }, gameobjects.TriggerAction{ .start_dialogue = &gameDialogue });

    _ = cs.addGameObject(triggerGo);

    var player = try characters.Player.init(playerTexture, cs, screenWidth / 2, screenHeight / 2);

    // Main game loop
    while (!rl.windowShouldClose()) {
        const deltaTime = rl.getFrameTime();

        manager.update(deltaTime);

        // Handle dialogue input
        if (gameDialogue.active and rl.isKeyPressed(.space)) {
            gameDialogue.advance();
        }
        
        if (rl.isKeyPressed(.r)) {
            var ns = &manager.scenes[1];
            ns.* = scenes.Scene.init(screenWidth, screenHeight, null, null, null, null);
            ns.camera.offset = rl.Vector2{
                .x = root.F32(screenWidth) / 2.0,
                .y = root.F32(screenHeight) / 2.0,
            };
            manager.changeScene(1);
        }

        rl.beginDrawing();
        rl.clearBackground(.white);

        // Update and render game
        rl.beginMode2D(manager.currentScene().camera);

        // Draw all scene GameObjects
        manager.currentScene().drawGameObjects();

        try player.update(deltaTime, gameDialogue.active);

        // Check triggers on all GameObjects with player rectangle
        const spriteW: f32 = @floatFromInt(player.texture.width);
        const spriteH: f32 = @floatFromInt(player.texture.height);
        const absScale = if (player.sprite.scale < 0.0) -player.sprite.scale else player.sprite.scale;
        const playerRec = rl.Rectangle{
            .x = player.sprite.x,
            .y = player.sprite.y,
            .width = spriteW * absScale,
            .height = spriteH * absScale,
        };
        manager.currentScene().checkGameObjectTriggers(playerRec);

        manager.currentScene().camera.target = rl.Vector2{
            .x = player.sprite.x + root.F32(player.texture.width) / 2.0,
            .y = player.sprite.y + root.F32(player.texture.height) / 2.0,
        };

        rl.endMode2D();

        // Render scene message
        if (manager.currentScene().messageTimer > 0.0) {
            if (manager.currentScene().message) |msg| {
                rl.drawText(msg, 10, 10, 20, .red);
            }
            manager.currentScene().messageTimer -= deltaTime;
        }

        // Draw dialogue
        gameDialogue.draw(20, screenHeight - 120, screenWidth - 40, 100);

        manager.draw();

        rl.endDrawing();
    }
}
