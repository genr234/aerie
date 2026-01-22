const std = @import("std");
const builtin = @import("builtin");
pub const rl = @import("raylib");

const mem = @import("memory.zig");
const scenes = @import("scenes.zig");
const project = @import("project.zig");
const dialogue = @import("dialogue.zig");
const ecs = @import("ecs.zig");
const story = @import("story.zig");
const events = @import("events.zig");
const assets = @import("utils/assets.zig");
const ui = @import("ui.zig");
const state = @import("state.zig");
const vn = @import("vn.zig");

const scripting = @import("scripting/runtime.zig");
const scripting_context = @import("scripting/context.zig");

const sceneio_json = @import("sceneio/json.zig");
const sceneio_instantiate = @import("sceneio/instantiate.zig");

pub const screenWidth = 800;
pub const screenHeight = 450;

pub const Engine = struct {
    gameState: state.GameState = undefined,
    initialized: bool = false,

    sceneManager: scenes.SceneManager = undefined,
    sceneBuilder: scenes.Builder = undefined,

    scriptCtx: scripting_context.ScriptingContext = undefined,
    wrenRuntime: ?scripting.Runtime = null,

    modeStack: ModeStack = .{},

    const Self = @This();

    pub fn init(self: *Self) !void {
        mem.init();

        const project_cfg = project.loadProjectConfig(mem.permanent(), ".") catch project.ProjectConfig{
            .id = "demo",
            .title = "Test Game",
        };

        const ztitle = try std.fmt.allocPrint(mem.frame(), "{s}", .{project_cfg.window_title});
        ztitle.ptr[ztitle.len] = 0;
        rl.initWindow(project_cfg.window_width, project_cfg.window_height, @ptrCast(ztitle.ptr[0..ztitle.len :0]));
        rl.setTargetFPS(60);

        const player_path = try assets.parseAssetPath(mem.frame(), "player.png", builtin.os.tag);
        self.gameState.playerTexture = rl.loadTexture(player_path) catch |err| {
            std.debug.print("Failed to load texture: {s}\n", .{player_path});
            return err;
        };

        // Systems
        self.gameState.eventQueue = events.EventQueue.init();
        self.gameState.storyState = story.StoryState.initWithEvents(&self.gameState.eventQueue);

        var builder = dialogue.Builder.init(mem.permanent());
        defer builder.deinit();
        _ = builder.done();
        self.gameState.script = try builder.build();
        self.gameState.gameDialogue = dialogue.Runner.init(mem.scene(), &self.gameState.script);

        var vnBuilder = dialogue.Builder.init(mem.permanent());
        defer vnBuilder.deinit();
        _ = vnBuilder.done();
        self.gameState.vnScript = try vnBuilder.build();
        self.gameState.vnDialogue = dialogue.Runner.init(mem.scene(), &self.gameState.vnScript);

        self.gameState.vnState = vn.VNState.init(screenWidth, screenHeight);
        self.gameState.vnState.setDialogueRunner(&self.gameState.vnDialogue);
        self.gameState.vnState.setStoryState(&self.gameState.storyState);
        self.gameState.vnState.setEventQueue(&self.gameState.eventQueue);

        self.gameState.manager = undefined;
        self.gameState.sceneBuilder = undefined;

        self.sceneManager = try scenes.SceneManager.init(10, &self.gameState);
        self.sceneManager.setOnTransition(onSceneTransition);
        self.sceneBuilder = try scenes.Builder.init(mem.permanent(), screenWidth, screenHeight, &self.gameState);

        self.gameState.manager = &self.sceneManager;
        self.gameState.sceneBuilder = &self.sceneBuilder;

        self.gameState.eventQueue.bindSystems(.{
            .sceneManager = self.gameState.manager,
            .storyState = &self.gameState.storyState,
        });

        var scene0 = try scenes.Scene.initForScene(project_cfg.window_width, project_cfg.window_height, &self.gameState);
        const ir = try sceneio_json.loadSceneIR(mem.frame(), project_cfg.start_scene);

        const textures = sceneio_instantiate.TextureTable{ .player = self.gameState.playerTexture };
        const dialogue_bindings = sceneio_instantiate.DialogueBindings{
            .game = @ptrCast(&self.gameState.gameDialogue),
            .vn = @ptrCast(&self.gameState.vnDialogue),
        };

        try sceneio_instantiate.instantiateSceneIR(mem.frame(), &scene0, &ir, &textures, dialogue_bindings);
        self.gameState.manager.scenes[0] = scene0;

        self.scriptCtx = .{
            .eventQueue = &self.gameState.eventQueue,
            .storyState = &self.gameState.storyState,
            .sceneManager = self.gameState.manager,
            .gameDialogue = &self.gameState.gameDialogue,
            .vnDialogue = &self.gameState.vnDialogue,
            .vnActive = &self.gameState.vnActive,
        };
        self.wrenRuntime = scripting.Runtime.init(mem.permanent(), &self.scriptCtx, project_cfg.entry_module, project_cfg.entry_class) catch |err| blk: {
            std.debug.print("[wren] runtime init failed: {any}\n", .{err});
            break :blk null;
        };

        self.modeStack.push(@constCast(&ExplorationMode)) catch {};

        self.initialized = true;
    }

    pub fn deinit(self: *Self) void {
        if (!self.initialized) return;

        if (self.wrenRuntime) |*rt| {
            rt.deinit();
            self.wrenRuntime = null;
        }

        self.gameState.manager.deinit();
        self.gameState.gameDialogue.deinit();
        self.gameState.script.deinit();

        self.gameState.vnDialogue.deinit();
        self.gameState.vnScript.deinit();
        self.gameState.eventQueue.deinit();

        rl.unloadTexture(self.gameState.playerTexture);
        rl.closeWindow();

        mem.deinit();
        self.initialized = false;
    }

    pub fn tick(self: *Self) void {
        if (!self.initialized) return;

        mem.resetFrame();
        const dt = rl.getFrameTime();

        if (rl.isKeyPressed(.v)) {
            if (!self.gameState.vnActive) {
                self.gameState.vnActive = true;
                self.gameState.vnDialogue.start(&self.gameState.storyState);
                self.modeStack.push(@constCast(&VNMode)) catch {};
            } else {
                self.gameState.vnActive = false;
                _ = self.modeStack.pop();
            }
        }

        if (self.modeStack.top()) |mode| {
            mode.update(self, dt);
        }

        if (self.wrenRuntime) |*rt| {
            rt.reloadIfChanged();
            _ = rt.callOnUpdate(dt);
        }

        self.gameState.eventQueue.process(dt);
    }

    pub fn draw(self: *Self) void {
        if (!self.initialized) return;

        rl.beginDrawing();
        rl.clearBackground(.white);

        if (self.modeStack.top()) |mode| {
            mode.draw(self);
        }

        rl.endDrawing();
    }
};

fn onSceneTransition(scene: *scenes.Scene, manager: *scenes.SceneManager, toSceneIndex: usize) bool {
    _ = scene;
    const tags = [_][]const u8{ "player", "origin_circle", "main_camera" };
    manager.transferPersistentEntities(manager.currentIndex, toSceneIndex, &tags);
    return false;
}

pub const Mode = struct {
    updateFn: *const fn (*Mode, *Engine, f32) void,
    drawFn: *const fn (*Mode, *Engine) void,

    pub fn update(self: *Mode, engine: *Engine, dt: f32) void {
        self.updateFn(self, engine, dt);
    }

    pub fn draw(self: *Mode, engine: *Engine) void {
        self.drawFn(self, engine);
    }
};

pub const ModeStack = struct {
    modes: [8]*Mode = undefined,
    count: usize = 0,

    pub fn push(self: *ModeStack, mode: *Mode) !void {
        if (self.count >= self.modes.len) return error.ModeOverflow;
        self.modes[self.count] = mode;
        self.count += 1;
    }

    pub fn pop(self: *ModeStack) ?*Mode {
        if (self.count == 0) return null;
        self.count -= 1;
        return self.modes[self.count];
    }

    pub fn top(self: *ModeStack) ?*Mode {
        if (self.count == 0) return null;
        return self.modes[self.count - 1];
    }
};

pub const ExplorationMode = Mode{
    .updateFn = explorationUpdate,
    .drawFn = explorationDraw,
};

fn explorationUpdate(_: *Mode, engine: *Engine, dt: f32) void {
    engine.gameState.manager.update(dt);
    engine.gameState.gameDialogue.update(dt);

    dialogue.handleInput(&engine.gameState.gameDialogue);

    if (rl.isKeyPressed(.r)) {
        // Transition hotkey was for the old demo multi-scene setup.
        // With project-driven loading we keep this disabled for now.
    }

    const currentScene = engine.gameState.manager.currentScene();
    const isPaused = engine.gameState.gameDialogue.isActive() or engine.gameState.manager.inputBlocked;
    currentScene.runSystems(dt, isPaused);
}

fn explorationDraw(_: *Mode, engine: *Engine) void {
    const currentScene = engine.gameState.manager.currentScene();
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
    dialogue.draw(&engine.gameState.gameDialogue, dialogueBounds, .{});

    rl.drawText(rl.textFormat("Scene: %d", .{engine.gameState.manager.currentIndex}), 10, 10, 20, .green);

    ui.drawFromEventQueue(engine.gameState.eventQueue, .{
        .toast = .{
            .origin = .{ .x = 10, .y = 40 },
            .lineHeight = 24,
            .fontSize = 20,
            .color = .black,
            .maxLines = 4,
        },
    });

    engine.gameState.manager.draw();
}

pub const VNMode = Mode{
    .updateFn = vnUpdate,
    .drawFn = vnDraw,
};

fn vnUpdate(_: *Mode, engine: *Engine, dt: f32) void {
    engine.gameState.vnState.handleInput();
    engine.gameState.vnState.update(dt);
}

fn vnDraw(_: *Mode, engine: *Engine) void {
    engine.gameState.vnState.draw();
}
