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
const resources = @import("resources.zig");
const ui = @import("ui.zig");
const state = @import("state.zig");
const vn = @import("vn.zig");

const scripting = @import("scripting/runtime.zig");
const scripting_context = @import("scripting/context.zig");

const sceneio_json = @import("sceneio/json.zig");
const sceneio_instantiate = @import("sceneio/instantiate.zig");
const sceneio_types = @import("sceneio/types.zig");

pub const screenWidth = 800;
pub const screenHeight = 450;

pub const Engine = struct {
    gameState: state.GameState = undefined,
    initialized: bool = false,

    sceneManager: scenes.SceneManager = undefined,
    sceneBuilder: scenes.Builder = undefined,

    scriptCtx: scripting_context.ScriptingContext = undefined,
    wrenRuntime: ?scripting.Runtime = null,
    textureEntries: []sceneio_instantiate.TextureTable.Entry = &.{},

    project_root: []const u8 = ".",

    modeStack: ModeStack = .{},

    const Self = @This();

    pub fn init(self: *Self, project_root: []const u8) !void {
        mem.init();
        errdefer mem.deinit();

        const bundle = try project.loadProjectBundleFromFs(mem.permanent(), project_root);
        try self.initBundle(&bundle);
    }

    pub fn initBundle(self: *Self, bundle: *const project.ProjectBundle) !void {
        if (!mem.isInitialized()) {
            mem.init();
        }

        self.project_root = bundle.asset_root;
        const project_cfg = bundle.config;

        const ztitle = try std.fmt.allocPrint(mem.frame(), "{s}", .{project_cfg.window_title});
        ztitle.ptr[ztitle.len] = 0;
        rl.initWindow(project_cfg.window_width, project_cfg.window_height, @ptrCast(ztitle.ptr[0..ztitle.len :0]));
        rl.setTargetFPS(60);

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

        const scene_count = @max(bundle.scenes.len, 1);
        self.sceneManager = try scenes.SceneManager.init(scene_count, &self.gameState);
        self.sceneManager.setOnTransition(onSceneTransition);
        self.sceneBuilder = try scenes.Builder.init(mem.permanent(), screenWidth, screenHeight, &self.gameState);

        self.gameState.manager = &self.sceneManager;
        self.gameState.sceneBuilder = &self.sceneBuilder;

        self.gameState.eventQueue.bindSystems(.{
            .sceneManager = self.gameState.manager,
            .storyState = &self.gameState.storyState,
        });

        const scene_irs = try mem.permanent().alloc(sceneio_types.SceneIR, bundle.scenes.len);
        for (bundle.scenes, 0..) |scene_source, i| {
            scene_irs[i] = sceneio_json.parseSceneIR(mem.permanent(), scene_source.json) catch |err| {
                std.debug.print("Failed to parse scene '{s}': {any}\n", .{ scene_source.name, err });
                return err;
            };
        }

        self.textureEntries = try loadSceneTextures(bundle, scene_irs);
        const textures = sceneio_instantiate.TextureTable{ .entries = self.textureEntries };
        if (self.textureEntries.len == 0) return error.MissingTexture;
        self.gameState.playerTexture = if (textures.get("player.png")) |tex| tex else self.textureEntries[0].texture;

        const dialogue_bindings = sceneio_instantiate.DialogueBindings{
            .game = @ptrCast(&self.gameState.gameDialogue),
            .vn = @ptrCast(&self.gameState.vnDialogue),
        };

        for (bundle.scenes, scene_irs, 0..) |scene_source, *ir, i| {
            var scene = switch (ir.scene_type) {
                .exploration => try scenes.Scene.initForScene(ir.width, ir.height, &self.gameState),
                .visual_novel => try scenes.Scene.initVNForScene(ir.width, ir.height, &self.gameState),
            };
            scene.name = scene_source.name;
            sceneio_instantiate.instantiateSceneIR(mem.frame(), &scene, ir, &textures, dialogue_bindings) catch |err| {
                std.debug.print("Failed to instantiate scene '{s}': {any}\n", .{ scene_source.name, err });
                return err;
            };
            self.gameState.manager.scenes[i] = scene;
        }

        const start_scene = bundle.startScene() orelse return error.MissingStartScene;
        self.gameState.manager.currentIndex = self.gameState.manager.findSceneByName(start_scene.name) orelse 0;

        self.scriptCtx = .{
            .eventQueue = &self.gameState.eventQueue,
            .storyState = &self.gameState.storyState,
            .sceneManager = self.gameState.manager,
            .gameDialogue = &self.gameState.gameDialogue,
            .vnDialogue = &self.gameState.vnDialogue,
            .vnActive = &self.gameState.vnActive,
        };
        self.wrenRuntime = scripting.Runtime.init(mem.permanent(), &self.scriptCtx, bundle.asset_root, bundle.scripts, bundle.resources, project_cfg.entry_module, project_cfg.entry_class) catch |err| blk: {
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

        for (self.textureEntries) |entry| {
            rl.unloadTexture(entry.texture);
        }
        self.textureEntries = &.{};
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
            rt.dispatchInput(dt);
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

fn loadTexture(bundle: *const project.ProjectBundle, path: []const u8) !rl.Texture2D {
    if (bundle.resources) |provider| {
        const bytes = try readAssetBytes(provider, mem.frame(), path);
        defer mem.frame().free(bytes);

        const ext = try imageFileType(mem.frame(), path);
        defer mem.frame().free(ext);

        var image = try rl.loadImageFromMemory(ext, bytes);
        defer image.unload();

        return rl.Texture.fromImage(image);
    }

    const player_path = try assets.parseAssetPath(mem.frame(), bundle.asset_root, path, builtin.os.tag);
    return rl.loadTexture(player_path) catch |err| {
        std.debug.print("Failed to load texture: {s}\n", .{player_path});
        return err;
    };
}

fn loadSceneTextures(bundle: *const project.ProjectBundle, scene_irs: []const sceneio_types.SceneIR) ![]sceneio_instantiate.TextureTable.Entry {
    var paths = std.ArrayList([]const u8).empty;
    defer paths.deinit(mem.frame());

    for (scene_irs) |ir| {
        for (ir.entities) |entity| {
            for (entity.components) |component| {
                switch (component) {
                    .Sprite => |sprite| try appendUniquePath(&paths, sprite.texture),
                    else => {},
                }
            }
        }
    }

    const entries = try mem.permanent().alloc(sceneio_instantiate.TextureTable.Entry, paths.items.len);
    for (paths.items, 0..) |path, i| {
        entries[i] = .{
            .name = try mem.permanent().dupe(u8, path),
            .texture = loadTexture(bundle, path) catch |err| {
                std.debug.print("Failed to load texture asset '{s}': {any}\n", .{ path, err });
                return err;
            },
        };
    }

    return entries;
}

fn appendUniquePath(paths: *std.ArrayList([]const u8), path: []const u8) !void {
    for (paths.items) |existing| {
        if (std.mem.eql(u8, existing, path)) return;
    }
    try paths.append(mem.frame(), path);
}

fn readAssetBytes(provider: resources.ResourceProvider, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const asset_path = if (std.mem.startsWith(u8, path, "assets/") or std.mem.startsWith(u8, path, "/assets/"))
        path
    else
        try std.fmt.allocPrint(allocator, "assets/{s}", .{path});

    const should_free = asset_path.ptr != path.ptr;
    defer if (should_free) allocator.free(asset_path);

    return provider.readBytes(allocator, asset_path);
}

fn imageFileType(allocator: std.mem.Allocator, path: []const u8) ![:0]const u8 {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return allocator.dupeZ(u8, ".png");
    return allocator.dupeZ(u8, ext);
}

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

    engine.gameState.manager.draw();

    // Call Wren onDraw for custom UI
    if (engine.wrenRuntime) |*rt| {
        _ = rt.callOnDraw();
    }

    // Draw event messages as toasts
    var msg_idx: usize = 0;
    var y_offset: f32 = 40;
    while (msg_idx < engine.gameState.eventQueue.len()) : (msg_idx += 1) {
        const evt_ptr = engine.gameState.eventQueue.peek(msg_idx) orelse break;
        switch (evt_ptr.*) {
            .ShowMessage => |msg| {
                if (msg.elapsed < msg.duration) {
                    ui.UI.toast(msg.getText(), y_offset, msg.duration, msg.elapsed, .{ .font_size = 20, .color = .black });
                    y_offset += 24;
                }
            },
            else => {},
        }
    }
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
