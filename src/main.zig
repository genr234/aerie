const rl = @import("raylib");
const std = @import("std");
const builtin = @import("builtin");
const scenes = @import("engine/scenes.zig");
const dialogue = @import("engine/dialogue.zig");
const ecs = @import("engine/ecs.zig");

// Emscripten imports
extern "c" fn emscripten_set_main_loop(func: *const fn () callconv(.c) void, fps: i32, simulate_infinite_loop: i32) void;

const screenWidth = 800;
const screenHeight = 450;

const GameState = struct {
    manager: scenes.SceneManager,
    gameDialogue: dialogue.Runner,
    playerTexture: rl.Texture2D,
    allocator: std.mem.Allocator,
    sceneBuilder: scenes.Builder,
    script: dialogue.Script,
    gpa: if (builtin.os.tag != .emscripten) std.heap.GeneralPurposeAllocator(.{}) else void,
};

var state: GameState = undefined;
var initialized: bool = false;

fn onSceneTransition(scene: *scenes.Scene, manager: *scenes.SceneManager, toSceneIndex: usize) void {
    _ = scene;
    const tags = [_][]const u8{ "player", "origin_circle", "main_camera" };
    manager.transferPersistentEntities(manager.currentIndex, toSceneIndex, &tags);
}

fn init() !void {
    rl.initWindow(screenWidth, screenHeight, "Test Game");

    rl.setTargetFPS(60);

    // Initialize allocator
    if (builtin.os.tag == .emscripten) {
        state.allocator = std.heap.c_allocator;
        state.gpa = {};
    } else {
        state.gpa = std.heap.GeneralPurposeAllocator(.{}){};
        state.allocator = state.gpa.allocator();
    }

    // Load assets
    const player_path = if (builtin.os.tag == .emscripten) "/assets/player.png" else "assets/player.png";
    state.playerTexture = rl.loadTexture(player_path) catch |err| {
        std.debug.print("Failed to load texture: {s}\n", .{player_path});
        return err;
    };

    // Setup Dialogue
    var builder = dialogue.Builder.init(state.allocator);
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
    state.gameDialogue = dialogue.Runner.init(state.allocator, &state.script);

    state.manager = try scenes.SceneManager.initWithAllocator(&state.allocator, 10);
    state.sceneBuilder = scenes.Builder.init(screenWidth, screenHeight);

    state.manager.scenes[0] = state.sceneBuilder
        .onTransition(onSceneTransition)
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
        .circle("origin_circle", .{ .x = 15, .y = 15 }, 4, rl.Color.blue)
        .rect("trigger_zone", .{ .x = 300, .y = 200 }, .{ .x = 50, .y = 50 }, rl.Color.green)
        .triggerZone("dialogue_trigger", .{ .x = 300, .y = 200, .width = 50, .height = 50 }, .{
            .start_dialogue = .{ .runner = &state.gameDialogue, .context = null },
        }, false)
        .build();

    initialized = true;
}

fn deinit() void {
    if (!initialized) return;

    state.manager.deinit();
    state.gameDialogue.deinit();
    state.script.deinit();
    rl.unloadTexture(state.playerTexture);
    rl.closeWindow();

    if (builtin.os.tag != .emscripten) {
        _ = state.gpa.deinit();
    }
}

fn update() !void {
    if (!initialized) return;

    const deltaTime = rl.getFrameTime();

    state.manager.update(deltaTime);
    state.gameDialogue.update(deltaTime);

    dialogue.handleInput(&state.gameDialogue);

    if (rl.isKeyPressed(.r)) {
        const nextSceneIdx = state.manager.currentIndex + 1;
        if (nextSceneIdx < 10) {
            state.manager.scenes[nextSceneIdx] = state.sceneBuilder
                .reset(screenWidth, screenHeight)
                .onTransition(onSceneTransition)
                .build();
            state.manager.changeScene(nextSceneIdx) catch {};
        }
    }

    const currentScene = state.manager.currentScene();

    const isPaused = state.gameDialogue.isActive() or state.manager.inputBlocked;
    currentScene.runSystems(deltaTime, isPaused);
}

fn draw() void {
    if (!initialized) return;

    rl.beginDrawing();
    rl.clearBackground(.white);

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
