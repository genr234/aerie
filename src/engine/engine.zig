const std = @import("std");
const builtin = @import("builtin");
pub const rl = @import("raylib");

const mem = @import("memory.zig");
const log = @import("log.zig");
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
const combat = @import("combat.zig");
const audio = @import("audio.zig");

const scripting = @import("scripting/runtime.zig");
const scripting_context = @import("scripting/context.zig");
const scripting_api = @import("scripting/api.zig");

const sceneio_json = @import("sceneio/json.zig");
const sceneio_instantiate = @import("sceneio/instantiate.zig");
const sceneio_types = @import("sceneio/types.zig");

pub const screenWidth = 800;
pub const screenHeight = 450;
const maxFrameDt: f32 = 1.0 / 15.0;

pub const Engine = struct {
    gameState: state.GameState = undefined,
    initialized: bool = false,

    sceneManager: scenes.SceneManager = undefined,
    sceneBuilder: scenes.Builder = undefined,

    scriptCtx: scripting_context.ScriptingContext = undefined,
    wrenRuntime: ?scripting.Runtime = null,
    textureEntries: []sceneio_instantiate.TextureTable.Entry = &.{},
    audioManager: audio.AudioManager = undefined,
    audioInitialized: bool = false,

    project_root: []const u8 = ".",

    modeStack: ModeStack = .{},
    saveMenuOpen: bool = false,
    saveStatus: [96]u8 = [_]u8{0} ** 96,
    saveStatusLen: usize = 0,
    saveStatusTimer: f32 = 0,

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

        const ztitle = try mem.frame().dupeZ(u8, project_cfg.window_title);
        rl.initWindow(project_cfg.window_width, project_cfg.window_height, ztitle);
        rl.setTargetFPS(60);
        self.audioInitialized = try self.loadAudioAssets(project_cfg.audio);

        // Systems
        self.gameState.eventQueue = events.EventQueue.init();
        self.gameState.storyState = story.StoryState.initWithEvents(&self.gameState.eventQueue);
        const combat_db = if (bundle.combatSource()) |source|
            try combat.parseDatabaseJson(mem.permanent(), source)
        else
            combat.Database.empty();
        self.gameState.combatState = combat.BattleState.init(combat_db, &self.gameState.storyState);

        if (bundle.dialogues.len > 0) {
            self.gameState.script = try dialogue.parseScriptJson(mem.permanent(), bundle.dialogues[0].source);
        } else {
            var builder = dialogue.Builder.init(mem.permanent());
            defer builder.deinit();
            _ = builder.done();
            self.gameState.script = try builder.build();
        }
        self.gameState.gameDialogue = dialogue.Runner.init(mem.scene(), &self.gameState.script);

        if (bundle.dialogues.len > 0) {
            self.gameState.vnScript = try dialogue.parseScriptJson(mem.permanent(), bundle.dialogues[0].source);
        } else {
            var vnBuilder = dialogue.Builder.init(mem.permanent());
            defer vnBuilder.deinit();
            _ = vnBuilder.done();
            self.gameState.vnScript = try vnBuilder.build();
        }
        self.gameState.vnDialogue = dialogue.Runner.init(mem.scene(), &self.gameState.vnScript);

        self.gameState.vnState = vn.VNState.init(screenWidth, screenHeight);
        self.gameState.vnState.setDialogueRunner(&self.gameState.vnDialogue);
        self.gameState.vnState.setStoryState(&self.gameState.storyState);
        self.gameState.vnState.setEventQueue(&self.gameState.eventQueue);
        if (self.audioInitialized) self.gameState.vnState.setAudioManager(&self.audioManager);

        self.gameState.manager = undefined;
        self.gameState.sceneBuilder = undefined;

        const scene_count = @max(bundle.scenes.len, 1);
        self.sceneManager = try scenes.SceneManager.init(scene_count, &self.gameState);
        self.sceneManager.setOnTransition(onSceneTransition);
        self.sceneBuilder = try scenes.Builder.init(mem.permanent(), screenWidth, screenHeight, &self.gameState);

        self.gameState.manager = &self.sceneManager;
        self.gameState.sceneBuilder = &self.sceneBuilder;

        var systems = events.GameSystems{
            .sceneManager = self.gameState.manager,
            .storyState = &self.gameState.storyState,
        };
        if (self.audioInitialized) systems.audioManager = &self.audioManager;
        self.gameState.eventQueue.bindSystems(systems);

        const scene_irs = try mem.permanent().alloc(sceneio_types.SceneIR, bundle.scenes.len);
        for (bundle.scenes, 0..) |scene_source, i| {
            scene_irs[i] = sceneio_json.parseSceneIR(mem.permanent(), scene_source.json) catch |err| {
                log.debug("Failed to parse scene '{s}': {any}\n", .{ scene_source.name, err });
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
            if (ir.background_color) |color| scene.background_color = color;
            sceneio_instantiate.instantiateSceneIR(mem.frame(), &scene, ir, &textures, dialogue_bindings) catch |err| {
                log.debug("Failed to instantiate scene '{s}': {any}\n", .{ scene_source.name, err });
                return err;
            };
            self.gameState.manager.scenes[i] = scene;
        }

        const start_scene = bundle.startScene() orelse return error.MissingStartScene;
        self.gameState.manager.currentIndex = self.gameState.manager.findSceneByName(start_scene.name) orelse 0;

        self.scriptCtx = .{
            .projectRoot = self.project_root,
            .eventQueue = &self.gameState.eventQueue,
            .storyState = &self.gameState.storyState,
            .sceneManager = self.gameState.manager,
            .gameDialogue = &self.gameState.gameDialogue,
            .vnDialogue = &self.gameState.vnDialogue,
            .vnActive = &self.gameState.vnActive,
            .combatState = &self.gameState.combatState,
        };
        self.wrenRuntime = scripting.Runtime.init(mem.permanent(), &self.scriptCtx, bundle.asset_root, bundle.scripts, bundle.resources, project_cfg.entry_module, project_cfg.entry_class) catch |err| blk: {
            log.debug("[wren] runtime init failed: {any}\n", .{err});
            break :blk null;
        };

        self.modeStack.push(@constCast(&ExplorationMode)) catch {};

        self.initialized = true;
    }

    fn loadAudioAssets(self: *Self, audio_decl: project.AudioDecl) !bool {
        if (audio_decl.sounds.len == 0 and audio_decl.music.len == 0) return false;

        self.audioManager = audio.AudioManager.init();
        errdefer self.audioManager.deinit();

        for (audio_decl.sounds) |decl| {
            const path = try assets.parseAssetPath(mem.frame(), self.project_root, decl.path, builtin.os.tag);
            self.audioManager.registerSound(decl.id, path) catch |err| {
                log.debug("Failed to load sound '{s}' from '{s}': {any}\n", .{ decl.id, decl.path, err });
            };
        }

        for (audio_decl.music) |decl| {
            const path = try assets.parseAssetPath(mem.frame(), self.project_root, decl.path, builtin.os.tag);
            self.audioManager.registerMusic(decl.id, path) catch |err| {
                log.debug("Failed to load music '{s}' from '{s}': {any}\n", .{ decl.id, decl.path, err });
            };
        }

        return true;
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
        if (self.audioInitialized) {
            self.audioManager.deinit();
            self.audioInitialized = false;
        }
        rl.closeWindow();

        mem.deinit();
        self.initialized = false;
    }

    pub fn tick(self: *Self) void {
        if (!self.initialized) return;

        mem.resetFrame();
        const dt = @min(rl.getFrameTime(), maxFrameDt);

        if (rl.isKeyPressed(.escape)) {
            self.saveMenuOpen = !self.saveMenuOpen;
        }

        if (self.saveStatusTimer > 0) {
            self.saveStatusTimer = @max(0, self.saveStatusTimer - dt);
        }

        if (self.saveMenuOpen) {
            if (self.audioInitialized) self.audioManager.update(dt);
            return;
        }

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

        self.syncCombatMode();

        if (self.modeStack.top()) |mode| {
            mode.update(self, dt);
        }

        if (!self.gameState.combatState.active) {
            if (self.wrenRuntime) |*rt| {
                if (builtin.os.tag != .emscripten) {
                    rt.reloadIfChanged();
                }
                rt.dispatchInput(dt);
                _ = rt.callOnUpdate(dt);
            }
        }

        self.gameState.eventQueue.process(dt);
        if (self.audioInitialized) self.audioManager.update(dt);
    }

    pub fn draw(self: *Self) void {
        if (!self.initialized) return;

        rl.beginDrawing();
        rl.clearBackground(.white);

        if (self.modeStack.top()) |mode| {
            mode.draw(self);
        }

        self.drawSaveMenu();

        rl.endDrawing();
    }

    fn setSaveStatus(self: *Self, text: []const u8) void {
        const len = @min(text.len, self.saveStatus.len - 1);
        @memcpy(self.saveStatus[0..len], text[0..len]);
        self.saveStatus[len] = 0;
        self.saveStatusLen = len;
        self.saveStatusTimer = 2.5;
    }

    fn drawSaveMenu(self: *Self) void {
        const slot = "slot1";
        const has_save = scripting_api.Api.saveExists(&self.scriptCtx, slot);

        if (!self.saveMenuOpen) {
            if (self.saveStatusTimer > 0 and self.saveStatusLen > 0) {
                rl.drawText(self.saveStatus[0..self.saveStatusLen :0], 18, rl.getScreenHeight() - 30, 18, rl.Color{ .r = 30, .g = 34, .b = 42, .a = 230 });
            }
            return;
        }

        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
        rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), rl.Color{ .r = 0, .g = 0, .b = 0, .a = 110 });

        const panel_w: f32 = 300;
        const panel_h: f32 = 282;
        const x = (screen_w - panel_w) / 2;
        const y = (screen_h - panel_h) / 2;
        ui.UI.panel(x, y, panel_w, panel_h);
        rl.drawRectangleLinesEx(.{ .x = x, .y = y, .width = panel_w, .height = panel_h }, 2, rl.Color{ .r = 230, .g = 236, .b = 245, .a = 255 });
        rl.drawText("Game Menu", @intFromFloat(x + 24), @intFromFloat(y + 20), 24, rl.Color.white);
        rl.drawText(if (has_save) "Save slot: ready" else "Save slot: empty", @intFromFloat(x + 24), @intFromFloat(y + 56), 16, rl.Color.light_gray);

        if (ui.UI.button(x + 24, y + 88, panel_w - 48, 34, "Save Game")) {
            self.setSaveStatus(if (scripting_api.Api.writeSave(&self.scriptCtx, slot)) "Game saved." else "Save failed.");
        }

        if (ui.UI.button(x + 24, y + 130, panel_w - 48, 34, if (has_save) "Load Game" else "No Save Found")) {
            self.setSaveStatus(if (has_save and scripting_api.Api.loadSave(&self.scriptCtx, slot)) "Game loaded." else "No save to load.");
            if (has_save) self.saveMenuOpen = false;
        }

        if (ui.UI.button(x + 24, y + 172, panel_w - 48, 34, if (has_save) "Clear Save" else "Clear Save")) {
            self.setSaveStatus(if (scripting_api.Api.clearSave(&self.scriptCtx, slot)) "Save cleared." else "Clear failed.");
        }

        if (ui.UI.button(x + 24, y + 214, panel_w - 48, 34, "Resume")) {
            self.saveMenuOpen = false;
        }

        if (self.saveStatusTimer > 0 and self.saveStatusLen > 0) {
            rl.drawText(self.saveStatus[0..self.saveStatusLen :0], @intFromFloat(x + 24), @intFromFloat(y + panel_h - 30), 16, rl.Color{ .r = 180, .g = 220, .b = 255, .a = 255 });
        }
    }

    fn syncCombatMode(self: *Self) void {
        const top_is_combat = if (self.modeStack.top()) |mode| mode == @constCast(&CombatMode) else false;
        if (self.gameState.combatState.active and !top_is_combat) {
            self.modeStack.push(@constCast(&CombatMode)) catch {};
        } else if (!self.gameState.combatState.active and top_is_combat) {
            _ = self.modeStack.pop();
            if (self.gameState.combatState.exit_scene_len > 0) {
                const name = self.gameState.combatState.exit_scene[0..self.gameState.combatState.exit_scene_len];
                self.gameState.manager.changeSceneByName(name) catch |err| {
                    log.debug("Combat exit scene failed for '{s}': {any}\n", .{ name, err });
                };
                self.gameState.combatState.exit_scene_len = 0;
            }
        }
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
        log.debug("Failed to load texture: {s}\n", .{player_path});
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
                log.debug("Failed to load texture asset '{s}': {any}\n", .{ path, err });
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
        ecs.Systems.drawInteractionPrompt(&currentScene.world);
    } else |_| {
        ecs.Systems.render(&currentScene.world);
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

    engine.gameState.manager.drawTransitionOverlay();
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

pub const CombatMode = Mode{
    .updateFn = combatUpdate,
    .drawFn = combatDraw,
};

fn combatUpdate(_: *Mode, engine: *Engine, dt: f32) void {
    engine.gameState.combatState.handleInput();
    engine.gameState.combatState.update(dt);
    engine.gameState.combatState.confirmExit();
}

fn combatDraw(_: *Mode, engine: *Engine) void {
    engine.gameState.combatState.draw(rl.getScreenWidth(), rl.getScreenHeight());
}
