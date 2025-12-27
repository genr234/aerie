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

    // Setup Dialogue
    var builder = dialogue.Builder.init(allocator);
    defer builder.deinit();

    _ = builder.say("Narrator", "Hello!");
    _ = builder.ask("Narrator", "Choose an option", &[_]dialogue.Option{
        .{ .text = "option one", .goto = "skip" },
        .{ .text = "option two", .goto = "skip" },
    });
    _ = builder.label("skip");
    _ = builder.say("Narrator", "The end.");
    _ = builder.done();

    var script = try builder.build();
    defer script.deinit();

    var gameDialogue = dialogue.Runner.init(allocator, &script);
    defer gameDialogue.deinit();

    var manager = try scenes.SceneManager.initWithAllocator(&allocator, 10);
    defer manager.deinit();

    var sceneBuilder = scenes.Builder.init(screenWidth, screenHeight);

    manager.scenes[0] = sceneBuilder
        .camera("main_camera", .{
            .offset = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
            .target = .{ .x = 0, .y = 0 },
            .rotation = 0,
            .zoom = 1.0,
        })
        .player("player", .{
            .texture = playerTexture,
            .speed = 100,
            .spawn = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
        })
        .circle("origin_circle", .{ .x = 15, .y = 15 }, 4, rl.Color.blue)
        .rect("trigger_zone", .{ .x = 300, .y = 200 }, .{ .x = 50, .y = 50 }, rl.Color.green)
        .trigger("trigger_zone", .{ .x = 300, .y = 200, .width = 50, .height = 50 }, .{
            .start_dialogue = .{ .runner = &gameDialogue, .context = null },
        })
        .build();

    // Main game loop
    while (!rl.windowShouldClose()) {
        const deltaTime = rl.getFrameTime();

        manager.update(deltaTime);
        gameDialogue.update(deltaTime);

        // Handle dialogue input
        if (gameDialogue.isActive()) {
            if (rl.isKeyPressed(.space)) {
                gameDialogue.skip();
                gameDialogue.advance();
            }

            if (gameDialogue.currentNode()) |node| {
                if (node.tag == .ask) {
                    if (rl.isKeyPressed(.up)) gameDialogue.selectUp();
                    if (rl.isKeyPressed(.down)) gameDialogue.selectDown();
                } else if (node.tag == .input) {
                    // Handle text input
                    const key = rl.getCharPressed();
                    if (key > 0 and key < 127) {
                        gameDialogue.typeChar(@intCast(key));
                    }
                    if (rl.isKeyPressed(.backspace)) {
                        gameDialogue.backspace();
                    }
                }
            }
        }

        if (rl.isKeyPressed(.r)) {
            manager.scenes[manager.currentIndex+1] = sceneBuilder
                .reset(sceneBuilder.scene.width, sceneBuilder.scene.height)
                .camera("main_camera", .{
                    .offset = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
                    .target = .{ .x = 0, .y = 0 },
                    .rotation = 0,
                    .zoom = 1.0,
                })
                .player("player", .{
                    .texture = playerTexture,
                    .speed = 100,
                    .spawn = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
                })
                .circle("origin_circle", .{ .x = 15, .y = 15 }, 4, rl.Color.blue)
                .build();
            manager.changeScene(manager.currentIndex+1) catch {};
        }

        const currentScene = manager.currentScene();

        currentScene.updatePlayer(deltaTime, gameDialogue.isActive());

        if (currentScene.getPlayerRect()) |playerRect| {
            currentScene.checkTriggers(playerRect);

            if (currentScene.get("player")) |playerGo| {
                const targetPos = rl.Vector2{
                    .x = playerGo.position.x + 16,
                    .y = playerGo.position.y + 16,
                };
                currentScene.updateCamera(targetPos);
            }
        }

        rl.beginDrawing();
        rl.clearBackground(.white);

        const currentCamera = currentScene.getCamera() orelse currentScene.camera;

        rl.beginMode2D(currentCamera);
        currentScene.drawGameObjects();
        rl.endMode2D();

        if (currentScene.messageTimer > 0.0) {
            if (currentScene.message) |msg| rl.drawText(msg, 10, 10, 20, .red);
            currentScene.messageTimer -= deltaTime;
        }

        const dialogueBounds = rl.Rectangle{
            .x = 20,
            .y = screenHeight - 120,
            .width = screenWidth - 40,
            .height = 100,
        };
        dialogue.draw(&gameDialogue, dialogueBounds, .{});

        rl.drawText(rl.textFormat("Scene: %d", .{manager.currentIndex}), 10, 20, 20, .green);

        manager.draw();

        rl.endDrawing();
    }
}

