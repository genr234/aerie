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

// Emscripten imports
extern "c" fn emscripten_set_main_loop(func: *const fn () callconv(.c) void, fps: i32, simulate_infinite_loop: i32) void;

const screenWidth = 800;
const screenHeight = 450;

const GameState = struct {
    manager: scenes.SceneManager,
    gameDialogue: dialogue.Runner,
    playerTexture: rl.Texture2D,
    sceneBuilder: scenes.Builder,
    script: dialogue.Script,
    isTransitioning: bool = false,

    vnActive: bool = false,
    vnState: vn.VNState,
    vnDialogue: dialogue.Runner,
    vnScript: dialogue.Script,
    storyState: story.StoryState,
    eventQueue: events.EventQueue,
};

var state: GameState = undefined;
var initialized: bool = false;

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
    state.playerTexture = rl.loadTexture(player_path) catch |err| {
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

    state.script = try builder.build();
    state.gameDialogue = dialogue.Runner.init(mem.scene(), &state.script);

    state.eventQueue = events.EventQueue.init();
    state.storyState = story.StoryState.initWithEvents(&state.eventQueue);

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

    state.vnScript = try vnBuilder.build();
    state.vnDialogue = dialogue.Runner.init(mem.scene(), &state.vnScript);

    // Initialize VN state and connect all references
    state.vnState = vn.VNState.init(screenWidth, screenHeight);
    state.vnState.setDialogueRunner(&state.vnDialogue);
    state.vnState.setStoryState(&state.storyState);
    state.vnState.setEventQueue(&state.eventQueue);

    state.manager = try scenes.SceneManager.init(10);
    state.manager.setOnTransition(onSceneTransition);
    state.sceneBuilder = try scenes.Builder.init(mem.permanent(), screenWidth, screenHeight);

    // Bind all game systems to event queue for automatic event routing
    state.eventQueue.bindSystems(.{
        .sceneManager = &state.manager,
        .storyState = &state.storyState,
    });

    state.manager.scenes[0] = state.sceneBuilder
        .camera("main_camera", .{
            .offset = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
            .target = .{ .x = 0, .y = 0 },
            .rotation = 0,
            .zoom = 1.0,
        })
        .player("player", .{
            .texture = state.playerTexture,
            .speed = 100,
            .spawn = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
        })
        .circle("origin_circle", .{ .x = 0, .y = 0 }, 4, rl.Color.blue)
        .rect("trigger_zone", .{ .x = 300, .y = 200 }, .{ .x = 50, .y = 50 }, rl.Color.green)
        .triggerZone("dialogue_trigger", .{ .x = 300, .y = 200, .width = 50, .height = 50 }, ecs.TriggerDialogueStart(&state.gameDialogue, null), false)
        .build();

    initialized = true;
}

fn deinit() void {
    if (!initialized) return;

    state.manager.deinit();
    state.gameDialogue.deinit();
    state.script.deinit();

    state.vnDialogue.deinit();
    state.vnScript.deinit();
    state.eventQueue.deinit();

    rl.unloadTexture(state.playerTexture);
    rl.closeWindow();

    mem.deinit();
}

fn update() !void {
    if (!initialized) return;

    mem.resetFrame();

    const deltaTime = rl.getFrameTime();

    if (rl.isKeyPressed(.v)) {
        state.vnActive = !state.vnActive;
        if (state.vnActive) {
            state.vnDialogue.start(&state.storyState);
        }
    }

    if (state.vnActive) {
        state.vnState.handleInput();
        state.vnState.update(deltaTime);

        state.eventQueue.process(deltaTime);
        return;
    }

    state.manager.update(deltaTime);
    state.gameDialogue.update(deltaTime);

    dialogue.handleInput(&state.gameDialogue);

    if (rl.isKeyPressed(.r)) {
        const nextSceneIdx = state.manager.currentIndex + 1;
        if (nextSceneIdx < 10 and !state.isTransitioning) {
            state.isTransitioning = true;
            mem.resetScene();

            state.manager.changeScene(nextSceneIdx) catch {};
            state.isTransitioning = false;
        }
    }

    const currentScene = state.manager.currentScene();

    const isPaused = state.gameDialogue.isActive() or state.manager.inputBlocked;
    currentScene.runSystems(deltaTime, isPaused);

    state.eventQueue.process(deltaTime);
}

fn draw() void {
    if (!initialized) return;

    rl.beginDrawing();
    rl.clearBackground(.white);

    if (state.vnActive) {
        state.vnState.draw();
        defer rl.endDrawing();
        return;
    }

    const currentScene = state.manager.currentScene();
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
    dialogue.draw(&state.gameDialogue, dialogueBounds, .{});

    rl.drawText(rl.textFormat("Scene: %d", .{state.manager.currentIndex}), 10, 10, 20, .green);

    ui.drawFromEventQueue(state.eventQueue, .{
        .toast = .{
            .origin = .{ .x = 10, .y = 40 },
            .lineHeight = 24,
            .fontSize = 20,
            .color = .black,
            .maxLines = 4,
        }
    });

    state.manager.draw();

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
