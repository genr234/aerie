const rl = @import("raylib");
const std = @import("std");
const characters = @import("engine/characters.zig");
const scenes = @import("engine/scenes.zig");
const dialogue = @import("engine/dialogue.zig");
const gameobjects = @import("engine/gameobjects.zig");
const sprites = @import("engine/sprites.zig");
const root = @import("root.zig");

fn onSceneTransition(scene: *scenes.Scene, manager: *scenes.SceneManager, toSceneIndex: usize) void {
    _ = scene;
    _ = manager.transferGameObject(manager.currentIndex, toSceneIndex, "player");
    _ = manager.transferGameObject(manager.currentIndex, toSceneIndex, "main_camera");
    _ = manager.transferGameObject(manager.currentIndex, toSceneIndex, "origin_circle");
}

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
    cs.onTransition = onSceneTransition;

    const cameraGo = gameobjects.GameObject.init("main_camera", gameobjects.GameObjectData{
        .camera = .{
            .offset = rl.Vector2{
                .x = root.F32(screenWidth) / 2.0,
                .y = root.F32(screenHeight) / 2.0,
            },
            .target = rl.Vector2{ .x = 0.0, .y = 0.0 },
            .rotation = 0.0,
            .zoom = 1.0,
        },
    });
    _ = cs.addGameObject(cameraGo);

    var circleGo = gameobjects.GameObject.init("origin_circle", gameobjects.GameObjectData{
        .circle = .{
            .radius = 4,
            .color = rl.Color.blue,
        },
    });
    circleGo.position = rl.Vector2{ .x = 15, .y = 15 };
    _ = cs.addGameObject(circleGo);

    var triggerGo = gameobjects.GameObject.init("trigger_zone", gameobjects.GameObjectData{
        .rectangle = .{
            .width = 50,
            .height = 50,
            .color = rl.Color.green,
        },
    });
    triggerGo.position = rl.Vector2{ .x = 300, .y = 200 };

    // Create dialogue system with simplified API
    var gameDialogue = try dialogue.DialogueSystem.init(allocator, .{});
    defer gameDialogue.deinit();

    // Build dialogue tree with simple method calls
    try gameDialogue.text("intro_1", "Narrator", "Benvenuto nell'avventura!", "intro_2");
    try gameDialogue.text("intro_2", "Narrator", "Cosa vuoi fare?", "choice_1");

    var choice_options = [_]dialogue.Choice{
        .{ .text = "Esplorare il mondo", .next_node_id = "explore" },
        .{ .text = "Saltare il tutorial", .next_node_id = "skip" },
    };
    try gameDialogue.choice("choice_1", "Narrator", "Scegli un'opzione:", &choice_options);

    try gameDialogue.text("explore", "Narrator", "Hai deciso di esplorare il mondo. Buona fortuna!", "end_1");
    try gameDialogue.text("skip", "Narrator", "Hai saltato il tutorial. Iniziamo direttamente!", "end_1");
    try gameDialogue.end("end_1");

    triggerGo.addTrigger(rl.Rectangle{
        .x = 300,
        .y = 200,
        .width = 50,
        .height = 50,
    }, gameobjects.TriggerAction{ .start_dialogue = &gameDialogue });

    _ = cs.addGameObject(triggerGo);

    const playerSprite = sprites.Sprite{
        .texture = playerTexture,
        .x = root.F32(screenWidth) / 2.0,
        .y = root.F32(screenHeight) / 2.0,
    };
    var playerGo = gameobjects.GameObject.init("player", gameobjects.GameObjectData{
        .player = .{
            .texture = playerTexture,
            .speed = 100,
            .sprite = playerSprite,
            .scale = 1.0,
        },
    });
    playerGo.position = rl.Vector2{ .x = root.F32(screenWidth) / 2.0, .y = root.F32(screenHeight) / 2.0 };
    _ = cs.addGameObject(playerGo);

    // Main game loop
    while (!rl.windowShouldClose()) {
        const deltaTime = rl.getFrameTime();

        manager.update(deltaTime);
        try gameDialogue.update();

        // Handle dialogue input
        if (gameDialogue.active) {
            if (rl.isKeyPressed(.space)) {
                try gameDialogue.advance();
            }

            if (gameDialogue.getCurrentNode()) |node| {
                if (node.node_type == .choice) {
                    if (rl.isKeyPressed(.up)) try gameDialogue.selectPreviousChoice();
                    if (rl.isKeyPressed(.down)) try gameDialogue.selectNextChoice();
                } else if (node.node_type == .input) {
                    // Handle text input
                    const key = rl.getCharPressed();
                    if (key > 0 and key < 127) {
                        gameDialogue.addInputChar(@intCast(key));
                    }
                    if (rl.isKeyPressed(.backspace)) {
                        gameDialogue.removeInputChar();
                    }
                }
            }
        }

        if (rl.isKeyPressed(.r)) {
            var ns = &manager.scenes[1];
            ns.* = scenes.Scene.init(screenWidth, screenHeight, null, null, null, null);
            ns.onTransition = onSceneTransition;
            manager.changeScene(1);
        }

        rl.beginDrawing();
        rl.clearBackground(.white);

        var currentCamera = manager.currentScene().getGameObjectCamera() orelse manager.currentScene().camera;
        rl.beginMode2D(currentCamera);

        manager.currentScene().drawGameObjects();
        manager.currentScene().updateGameObjectPlayer(deltaTime, gameDialogue.active);

        if (manager.currentScene().getPlayerRect()) |playerRect| {
            manager.currentScene().checkGameObjectTriggers(playerRect);

            const player = manager.currentScene().getGameObjectByTag("player");
            if (player) |pg| {
                const spriteW: f32 = @floatFromInt(pg.data.player.texture.width);
                const spriteH: f32 = @floatFromInt(pg.data.player.texture.height);
                const targetPos = rl.Vector2{
                    .x = pg.position.x + spriteW / 2.0,
                    .y = pg.position.y + spriteH / 2.0,
                };
                manager.currentScene().updateGameObjectCamera(targetPos);
                currentCamera = manager.currentScene().getGameObjectCamera() orelse currentCamera;
            }
        }

        rl.endMode2D();

        if (manager.currentScene().messageTimer > 0.0) {
            if (manager.currentScene().message) |msg| {
                rl.drawText(msg, 10, 10, 20, .red);
            }
            manager.currentScene().messageTimer -= deltaTime;
        }

        try gameDialogue.draw(20, screenHeight - 120, screenWidth - 40, 100);

        manager.draw();

        rl.endDrawing();
    }
}

