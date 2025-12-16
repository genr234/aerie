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

    var builder = dialogue.Builder.init(allocator);
    defer builder.deinit();

    _ = builder.say("Narrator", "Hello!").label("intro_2");
    _ = builder.say("Narrator", "What do you want to do?").label("choice_1");

    var choice_options = [_]dialogue.Option{
        .{ .text = "option one", .goto = "one" },
        .{ .text = "option two", .goto = "two" },
    };
    _ = builder.ask("Narrator", "Choose an option", &choice_options).label("explore_ask");

    _ = builder.say("Narrator", "Option one! Great!").goto("end_1");
    _ = builder.label("skip");
    _ = builder.say("Narrator", "Option two! Nice!").goto("end_1");
    _ = builder.label("end_1");
    _ = builder.done();

    var script = try builder.build();
    defer script.deinit();

    var gameDialogue = dialogue.Runner.init(allocator, &script);
    defer gameDialogue.deinit();


    triggerGo.addTrigger(rl.Rectangle{
        .x = 300,
        .y = 200,
        .width = 50,
        .height = 50,
    }, gameobjects.TriggerAction{ .start_dialogue = .{
        .runner = &gameDialogue,
        .context = null,
    } });

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
        manager.currentScene().updateGameObjectPlayer(deltaTime, gameDialogue.isActive());

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

        const dialogueBounds = rl.Rectangle{
            .x = 20,
            .y = screenHeight - 120,
            .width = screenWidth - 40,
            .height = 100,
        };
        dialogue.draw(&gameDialogue, dialogueBounds, .{});

        manager.draw();

        rl.endDrawing();
    }
}

