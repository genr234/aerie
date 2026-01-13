const rl = @import("raylib");
const std = @import("std");
const builtin = @import("builtin");
const mem = @import("engine/memory.zig");
const scenes = @import("engine/scenes.zig");
const dialogue = @import("engine/dialogue.zig");
const ecs = @import("engine/ecs.zig");
const vn = @import("engine/vn.zig");
const story = @import("engine/story.zig");
const events = @import("engine/events.zig");
const assets = @import("engine/utils/assets.zig");
const ui = @import("engine/ui.zig");
const state = @import("engine/state.zig");
const scripting = @import("engine/scripting/runtime.zig");
const scripting_context = @import("engine/scripting/context.zig");

// Emscripten imports
extern "c" fn emscripten_set_main_loop(func: *const fn () callconv(.c) void, fps: i32, simulate_infinite_loop: i32) void;

const screenWidth = 800;
const screenHeight = 450;

var gameState: state.GameState = undefined;
var initialized: bool = false;

var sceneManager: scenes.SceneManager = undefined;
var sceneBuilder: scenes.Builder = undefined;

var scriptCtx: scripting_context.ScriptingContext = undefined;
var wrenRuntime: ?scripting.Runtime = null;

fn onSceneTransition(scene: *scenes.Scene, manager: *scenes.SceneManager, toSceneIndex: usize) bool {
    _ = scene;
    const tags = [_][]const u8{ "player", "origin_circle", "main_camera" };
    manager.transferPersistentEntities(manager.currentIndex, toSceneIndex, &tags);
    return false;
}

fn init() !void {
    mem.init();

    rl.initWindow(screenWidth, screenHeight, "Test Game");

    rl.setTargetFPS(60);

    // Load assets
    const player_path = try assets.parseAssetPath(mem.frame(), "player.png", builtin.os.tag);
    gameState.playerTexture = rl.loadTexture(player_path) catch |err| {
        std.debug.print("Failed to load texture: {s}\n", .{player_path});
        return err;
    };

    // Setup Dialogue using permanent allocator (dialogue script lives for engine lifetime)
    var builder = dialogue.Builder.init(mem.permanent());
    defer builder.deinit();

    _ = builder.say("Narrator", "Hello!");
    _ = builder.ask("Narrator", "Choose an option", &[_]dialogue.Option{
        .{ .text = "option one", .goto = "skip" },
        .{ .text = "option two", .goto = "skip" },
    });
    _ = builder.label("skip");
    _ = builder.say("Narrator", "The end.");
    _ = builder.done();

    gameState.script = try builder.build();
    gameState.gameDialogue = dialogue.Runner.init(mem.scene(), &gameState.script);

    // Own these as values inside GameState (no pointers to temporaries).
    gameState.eventQueue = events.EventQueue.init();
    gameState.storyState = story.StoryState.initWithEvents(&gameState.eventQueue);

    var vnBuilder = dialogue.Builder.init(mem.permanent());
    defer vnBuilder.deinit();

    _ = vnBuilder.say("???", "Vn mode");
    _ = vnBuilder.ask("Narrator", "What will you do?", &[_]dialogue.Option{
        .{ .text = "Continue", .goto = "continue" },
        .{ .text = "Exit", .goto = "exit" },
    });
    _ = vnBuilder.label("continue");
    _ = vnBuilder.say("Narrator", "You chose to continue.");
    _ = vnBuilder.label("exit");
    _ = vnBuilder.say("Narrator", "Goodbye for now.");
    _ = vnBuilder.done();

    gameState.vnScript = try vnBuilder.build();
    gameState.vnDialogue = dialogue.Runner.init(mem.scene(), &gameState.vnScript);

    // Initialize VN gameState and connect all references
    gameState.vnState = vn.VNState.init(screenWidth, screenHeight);
    gameState.vnState.setDialogueRunner(&gameState.vnDialogue);
    gameState.vnState.setStoryState(&gameState.storyState);
    gameState.vnState.setEventQueue(&gameState.eventQueue);

    // IMPORTANT: manager/builder need a *GameState for World/Scene initialization.
    gameState.manager = undefined;
    gameState.sceneBuilder = undefined;

    sceneManager = try scenes.SceneManager.init(10, &gameState);
    sceneManager.setOnTransition(onSceneTransition);
    sceneBuilder = try scenes.Builder.init(mem.permanent(), screenWidth, screenHeight, &gameState);

    gameState.manager = &sceneManager;
    gameState.sceneBuilder = &sceneBuilder;

    // Bind all game systems to event queue for automatic event routing
    gameState.eventQueue.bindSystems(.{
        .sceneManager = gameState.manager,
        .storyState = &gameState.storyState,
    });

    gameState.manager.scenes[0] = gameState.sceneBuilder
        .camera("main_camera", .{
            .offset = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
            .target = .{ .x = 0, .y = 0 },
            .rotation = 0,
            .zoom = 1.0,
        })
        .player("player", .{
            .texture = gameState.playerTexture,
            .speed = 100,
            .spawn = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
        })
        .circle("origin_circle", .{ .x = 0, .y = 0 }, 4, rl.Color.blue)
        .rect("trigger_zone", .{ .x = 300, .y = 200 }, .{ .x = 50, .y = 50 }, rl.Color.green)
        .triggerZone("dialogue_trigger", .{ .x = 300, .y = 200, .width = 50, .height = 50 }, ecs.TriggerDialogueStart(&gameState.gameDialogue, null), false)
        .build();

    // Init Wren scripting (calls Game.onBoot()).
    scriptCtx = .{
        .eventQueue = &gameState.eventQueue,
        .storyState = &gameState.storyState,
        .sceneManager = gameState.manager,
        .gameDialogue = &gameState.gameDialogue,
        .vnDialogue = &gameState.vnDialogue,
        .vnActive = &gameState.vnActive,
    };
    wrenRuntime = scripting.Runtime.init(mem.permanent(), &scriptCtx) catch null;

    initialized = true;
}

fn deinit() void {
    if (!initialized) return;

    if (wrenRuntime) |*rt| {
        rt.deinit();
        wrenRuntime = null;
    }

    gameState.manager.deinit();
    gameState.gameDialogue.deinit();
    gameState.script.deinit();

    gameState.vnDialogue.deinit();
    gameState.vnScript.deinit();
    gameState.eventQueue.deinit();

    rl.unloadTexture(gameState.playerTexture);
    rl.closeWindow();

    mem.deinit();
}

fn update() !void {
    if (!initialized) return;

    mem.resetFrame();

    const deltaTime = rl.getFrameTime();

    if (rl.isKeyPressed(.v)) {
        gameState.vnActive = !gameState.vnActive;
        if (gameState.vnActive) {
            gameState.vnDialogue.start(&gameState.storyState);
        }
    }

    if (gameState.vnActive) {
        gameState.vnState.handleInput();
        gameState.vnState.update(deltaTime);

        if (wrenRuntime) |*rt| {
            rt.reloadIfChanged();
            _ = rt.callOnUpdate(deltaTime);
        }

        gameState.eventQueue.process(deltaTime);
        return;
    }

    gameState.manager.update(deltaTime);
    gameState.gameDialogue.update(deltaTime);

    dialogue.handleInput(&gameState.gameDialogue);

    if (rl.isKeyPressed(.r)) {
        const nextSceneIdx = gameState.manager.currentIndex + 1;
        if (nextSceneIdx < 10 and !gameState.isTransitioning) {
            gameState.isTransitioning = true;
            mem.resetScene();

            gameState.manager.changeScene(nextSceneIdx) catch {};
            gameState.isTransitioning = false;
        }
    }

    const currentScene = gameState.manager.currentScene();

    const isPaused = gameState.gameDialogue.isActive() or gameState.manager.inputBlocked;
    currentScene.runSystems(deltaTime, isPaused);

    if (wrenRuntime) |*rt| {
        rt.reloadIfChanged();
        _ = rt.callOnUpdate(deltaTime);
    }

    gameState.eventQueue.process(deltaTime);
}

fn draw() void {
    if (!initialized) return;

    rl.beginDrawing();
    rl.clearBackground(.white);

    if (gameState.vnActive) {
        gameState.vnState.draw();
        defer rl.endDrawing();
        return;
    }

    const currentScene = gameState.manager.currentScene();
    const deltaTime = rl.getFrameTime();

    if (ecs.Systems.getActiveCamera(&currentScene.world)) |camera| {
        rl.beginMode2D(camera);
        ecs.Systems.render(&currentScene.world);
        rl.endMode2D();
    } else |_| {
        rl.drawText("No Active Camera!", 200, 200, 30, rl.Color.red);
    }

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
    dialogue.draw(&gameState.gameDialogue, dialogueBounds, .{});

    rl.drawText(rl.textFormat("Scene: %d", .{gameState.manager.currentIndex}), 10, 10, 20, .green);

    ui.drawFromEventQueue(gameState.eventQueue, .{ .toast = .{
        .origin = .{ .x = 10, .y = 40 },
        .lineHeight = 24,
        .fontSize = 20,
        .color = .black,
        .maxLines = 4,
    } });

    gameState.manager.draw();

    rl.endDrawing();
}

fn gameLoop() callconv(.c) void {
    update() catch |err| {
        std.debug.print("Update error: {}\n", .{err});
    };
    draw();
}

pub fn main() !void {
    try init();

    if (builtin.os.tag == .emscripten) {
        emscripten_set_main_loop(gameLoop, 0, 1);
    } else {
        while (!rl.windowShouldClose()) {
            try update();
            draw();
        }
        deinit();
    }
}
