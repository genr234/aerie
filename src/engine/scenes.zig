const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs.zig");
const vn = @import("vn.zig");
const mem = @import("memory.zig");
const state = @import("state.zig");

pub const SceneType = enum {
    exploration,
    visual_novel,
};

const SceneTypeVTable = struct {
    update: ?*const fn (*Scene, f32) void = null,
    draw: ?*const fn (*Scene) void = null,
    onEnter: ?*const fn (*Scene) void = null,
    onExit: ?*const fn (*Scene) void = null,
    onTransition: ?*const fn (*Scene, *SceneManager, usize) bool = null,
};

fn explorationUpdate(scene: *Scene, dt: f32) void {
    if (scene.update) |u| u(scene, dt);
}

fn explorationDraw(scene: *Scene) void {
    if (scene.draw) |d| d(scene);
}

fn explorationOnEnter(scene: *Scene) void {
    if (scene.onEnter) |f| f(scene);
}

fn explorationOnExit(scene: *Scene) void {
    if (scene.onExit) |f| f(scene);
}

fn explorationOnTransition(scene: *Scene, mgr: *SceneManager, dst_index: usize) bool {
    if (scene.onTransition) |f| {
        return f(scene, mgr, dst_index);
    }
    return true;
}

// VN mode vtable functions
fn vnUpdate(scene: *Scene, dt: f32) void {
    if (scene.vnState) |*s| {
        s.update(dt);
    }
    if (scene.update) |u| u(scene, dt);
}

fn vnDraw(scene: *Scene) void {
    if (scene.vnState) |*s| {
        s.draw();
    }
    if (scene.draw) |d| d(scene);
}

fn vnOnEnter(scene: *Scene) void {
    if (scene.vnState) |*s| {
        s.fadeIn(0.5);
    }
    if (scene.onEnter) |f| f(scene);
}

fn vnOnExit(scene: *Scene) void {
    if (scene.onExit) |f| f(scene);
}

fn vnOnTransition(scene: *Scene, mgr: *SceneManager, dst_index: usize) bool {
    if (scene.onTransition) |f| {
        return f(scene, mgr, dst_index);
    }
    return true;
}

fn vtableFor(scene_type: SceneType) SceneTypeVTable {
    return switch (scene_type) {
        .exploration => .{
            .update = explorationUpdate,
            .draw = explorationDraw,
            .onEnter = explorationOnEnter,
            .onExit = explorationOnExit,
            .onTransition = explorationOnTransition,
        },
        .visual_novel => .{
            .update = vnUpdate,
            .draw = vnDraw,
            .onEnter = vnOnEnter,
            .onExit = vnOnExit,
            .onTransition = vnOnTransition,
        },
    };
}

pub const SceneConfig = struct {
    width: i32 = 800,
    height: i32 = 450,

    scene_type: SceneType = .exploration,

    update: ?*const fn (*Scene, f32) void = null,
    draw: ?*const fn (*Scene) void = null,
    onEnter: ?*const fn (*Scene) void = null,
    onExit: ?*const fn (*Scene) void = null,
    onTransition: ?*const fn (*Scene, *SceneManager, usize) bool = null,
    setup: ?*const fn (*Scene, *anyopaque) void = null,
};

pub const Scene = struct {
    name: []const u8 = "",
    width: i32 = 800,
    height: i32 = 450,

    scene_type: SceneType = .exploration,

    update: ?*const fn (*Scene, f32) void = null,
    draw: ?*const fn (*Scene) void = null,
    onEnter: ?*const fn (*Scene) void = null,
    onExit: ?*const fn (*Scene) void = null,
    onTransition: ?*const fn (*Scene, *SceneManager, usize) bool = null,

    message: ?[:0]const u8 = null,
    messageTimer: f32 = 0.0,

    world: ecs.World = undefined,
    world_initialized: bool = false,

    // VN mode state
    vnState: ?vn.VNState = null,

    const Self = @This();

    /// Initialize scene with explicit allocator
    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32, game_state: *state.GameState) !Scene {
        var scene = Scene{
            .width = width,
            .height = height,
            .scene_type = .exploration,
            .world = try ecs.World.init(allocator, 1024, game_state),
            .world_initialized = true,
        };
        scene.world.bounds_width = @floatFromInt(width);
        scene.world.bounds_height = @floatFromInt(height);
        return scene;
    }

    /// Initialize using the scene arena allocator
    pub fn initForScene(width: i32, height: i32, game_state: *state.GameState) !Scene {
        return Scene.init(mem.scene(), width, height, game_state);
    }

    /// Initialize VN scene with explicit allocator
    pub fn initVN(allocator: std.mem.Allocator, width: i32, height: i32, game_state: *state.GameState) !Scene {
        const scene = Scene{
            .width = width,
            .height = height,
            .scene_type = .visual_novel,
            .vnState = vn.VNState.init(width, height),
            .world = try ecs.World.init(allocator, 1024, game_state),
            .world_initialized = true,
        };
        return scene;
    }

    /// Initialize VN scene using the scene arena allocator
    pub fn initVNForScene(width: i32, height: i32, game_state: *state.GameState) !Scene {
        return Scene.initVN(mem.scene(), width, height, game_state);
    }

    /// Deinit - optional when using arena allocation
    pub fn deinit(self: *Self) void {
        if (self.world_initialized) {
            self.world.deinit();
            self.world_initialized = false;
        }
    }

    fn vtable(self: *Self) SceneTypeVTable {
        return vtableFor(self.scene_type);
    }

    pub fn dispatchUpdate(self: *Self, dt: f32) void {
        const vt = self.vtable();
        if (vt.update) |f| f(self, dt);
    }

    pub fn dispatchDraw(self: *Self) void {
        const vt = self.vtable();
        if (vt.draw) |f| f(self);
    }

    pub fn dispatchOnEnter(self: *Self) void {
        const vt = self.vtable();
        if (vt.onEnter) |f| f(self);
    }

    pub fn dispatchOnExit(self: *Self) void {
        const vt = self.vtable();
        if (vt.onExit) |f| f(self);
    }

    pub fn dispatchOnTransition(self: *Self, mgr: *SceneManager, dst_index: usize) bool {
        const vt = self.vtable();
        if (vt.onTransition) |f| return f(self, mgr, dst_index);
        return true;
    }

    pub fn spawn(self: *Self) ecs.Entity {
        return self.world.spawn();
    }

    pub fn entity(self: *Self) ecs.EntityBuilder {
        return ecs.EntityBuilder.init(&self.world);
    }

    pub fn findEntity(self: *Self, tag: []const u8) ?ecs.Entity {
        return self.world.findByTag(tag);
    }

    pub fn runSystems(self: *Self, dt: f32, paused: bool) void {
        ecs.Systems.setPlayerPaused(&self.world, paused);
        ecs.Systems.playerMovement(&self.world, dt);
        ecs.Systems.cameraFollow(&self.world);
        ecs.Systems.triggerCheck(&self.world);
        ecs.Systems.processEvents(&self.world, dt);
    }

    pub fn drawWorld(self: *Self) void {
        ecs.Systems.render(&self.world);
    }

    pub fn get(self: *Self, tag: []const u8) ?ecs.Entity {
        return self.world.findByTag(tag);
    }

    pub fn getCamera(self: *Self) !rl.Camera2D {
        return ecs.Systems.getActiveCamera(&self.world);
    }

    pub fn getPlayerRect(self: *Self) ?rl.Rectangle {
        return ecs.Systems.getPlayerRect(&self.world);
    }

    pub fn getVNState(self: *Self) ?*vn.VNState {
        if (self.vnState) |*s| {
            return s;
        }
        return null;
    }

    pub fn handleVNInput(self: *Self) void {
        if (self.vnState) |*s| {
            s.handleInput();
        }
    }

    pub fn isVNDialogueActive(self: *const Self) bool {
        if (self.vnState) |*s| {
            return s.isDialogueActive();
        }
        return false;
    }
};

pub const Builder = struct {
    scene: Scene,
    allocator: std.mem.Allocator,

    /// Initialize with explicit allocator
    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32, game_state: *state.GameState) !Builder {
        return .{
            .scene = try Scene.init(allocator, width, height, game_state),
            .allocator = allocator,
        };
    }

    /// Initialize using scene arena allocator
    pub fn initForScene(width: i32, height: i32, game_state: *state.GameState) !Builder {
        return Builder.init(mem.scene(), width, height, game_state);
    }

    /// Initialize VN scene with explicit allocator
    pub fn initVN(allocator: std.mem.Allocator, width: i32, height: i32, game_state: *state.GameState) !Builder {
        return .{
            .scene = try Scene.initVN(allocator, width, height, game_state),
            .allocator = allocator,
        };
    }

    /// Initialize VN scene using scene arena allocator
    pub fn initVNForScene(width: i32, height: i32, game_state: *state.GameState) !Builder {
        return Builder.initVN(mem.scene(), width, height, game_state);
    }

    pub fn reset(self: *Builder, width: i32, height: i32, game_state: *state.GameState) !*Builder {
        if (self.scene.world_initialized) {
            self.scene.deinit();
        }
        self.scene = try Scene.init(self.allocator, width, height, game_state);
        return self;
    }

    pub fn resetVN(self: *Builder, width: i32, height: i32, game_state: *state.GameState) !*Builder {
        if (self.scene.world_initialized) {
            self.scene.deinit();
        }
        self.scene = try Scene.initVN(self.allocator, width, height, game_state);
        return self;
    }

    pub fn buildAndReset(self: *Builder, width: i32, height: i32, game_state: *state.GameState) !Scene {
        const out = self.scene;
        self.scene = try Scene.init(self.allocator, width, height, game_state);
        return out;
    }

    pub fn sceneType(self: *Builder, t: SceneType) *Builder {
        self.scene.scene_type = t;
        // Initialize VN state if switching to VN mode
        if (t == .visual_novel and self.scene.vnState == null) {
            self.scene.vnState = vn.VNState.init(self.scene.width, self.scene.height);
        }
        return self;
    }

    pub fn camera(self: *Builder, tag: []const u8, cam: struct {
        offset: rl.Vector2,
        target: rl.Vector2,
        rotation: f32 = 0.0,
        zoom: f32 = 1.0,
    }) *Builder {
        var eb = self.scene.entity();
        _ = eb.withTag(tag)
            .withTransform(.{ .x = 0, .y = 0 })
            .withCameraFull(.{
                .offset = cam.offset,
                .target = cam.target,
                .rotation = cam.rotation,
                .zoom = cam.zoom,
            })
            .build();
        return self;
    }

    pub fn player(self: *Builder, tag: []const u8, config: struct {
        texture: rl.Texture2D,
        speed: f32 = 100,
        spawn: rl.Vector2,
    }) *Builder {
        var eb = self.scene.entity();
        const player_entity = eb.withTag(tag)
            .withTransform(config.spawn)
            .withSprite(config.texture)
            .withPlayerController(config.speed)
            .withBoxCollider(
                @floatFromInt(config.texture.width),
                @floatFromInt(config.texture.height),
            )
            .build();

        if (self.scene.world.findByTag("main_camera")) |cam_entity| {
            if (self.scene.world.cameras.get(cam_entity)) |cam| {
                cam.follow_target = player_entity;
            }
        }
        return self;
    }

    pub fn circle(self: *Builder, tag: []const u8, pos: rl.Vector2, radius: f32, color: rl.Color) *Builder {
        var eb = self.scene.entity();
        _ = eb.withTag(tag)
            .withTransform(pos)
            .withCircle(radius, color)
            .build();
        return self;
    }

    pub fn rect(self: *Builder, tag: []const u8, pos: rl.Vector2, size: rl.Vector2, color: rl.Color) *Builder {
        var eb = self.scene.entity();
        _ = eb.withTag(tag)
            .withTransform(pos)
            .withRect(size.x, size.y, color)
            .build();
        return self;
    }

    pub fn triggerZone(self: *Builder, tag: []const u8, bounds: rl.Rectangle, action: ecs.TriggerAction, one_shot: bool) *Builder {
        var eb = self.scene.entity();
        _ = eb.withTag(tag)
            .withTransform(.{ .x = bounds.x, .y = bounds.y })
            .withTrigger(bounds, action, one_shot)
            .build();
        return self;
    }

    pub fn onTransition(self: *Builder, func: *const fn (*Scene, *SceneManager, usize) bool) *Builder {
        self.scene.onTransition = func;
        return self;
    }

    pub fn build(self: *Builder) Scene {
        return self.scene;
    }
};

pub const TransitionState = enum {
    None,
    FadingOut,
    FadingIn,
};

pub const SceneManager = struct {
    game_state: *state.GameState = undefined,

    scenes: []Scene,
    currentIndex: usize = 0,
    lastIndex: usize = 0,

    // allocator is set if the SceneManager allocated the buffer itself
    allocator: ?*std.mem.Allocator = null,
    capacity: usize = 0,

    // optional history stack (indexes) - present if allocator used
    history: []usize,
    historyTop: usize = 0,

    // transition state
    transitionState: TransitionState = TransitionState.None,
    transitionTimer: f32 = 0.0,
    transitionDuration: f32 = 0.4,
    transitionNextIndex: ?usize = null,
    inputBlocked: bool = false,
    zoomTarget: f32 = 1.0,
    zoomStart: f32 = 1.0,

    // Track objects to cleanup from old scene after transition
    objectsToCleanup: [64][]const u8 = undefined,
    cleanupCount: usize = 0,

    /// Global transition callback invoked on any scene transition.
    /// Called before the source scene's own `Scene.onTransition` (if any).
    onTransition: ?*const fn (*Scene, *SceneManager, usize) bool = null,

    /// Initialize using the permanent arena for scene manager data
    pub fn init(capacity: usize, game_state: *state.GameState) !SceneManager {
        const allocator = mem.permanent();
        const scenes_ptr = try allocator.alloc(Scene, capacity);
        for (scenes_ptr) |*s| {
            s.* = try Scene.init(allocator, 800, 450, game_state);
        }
        const history_ptr = try allocator.alloc(usize, capacity);
        @memset(history_ptr, 0);

        return .{
            .scenes = scenes_ptr,
            .game_state = game_state,
            .allocator = null,
            .capacity = capacity,
            .history = history_ptr,
            .objectsToCleanup = undefined,
            .onTransition = null,
        };
    }

    pub fn deinit(self: *SceneManager) void {
        if (self.allocator) |alloc| {
            // free history first
            if (self.history.len != 0) {
                alloc.free(self.history);
            }
            // free scenes
            alloc.free(self.scenes);
        }
    }

    pub fn currentScene(self: *SceneManager) *Scene {
        return &self.scenes[self.currentIndex];
    }

    pub fn setOnTransition(self: *SceneManager, func: ?*const fn (*Scene, *SceneManager, usize) bool) void {
        self.onTransition = func;
    }

    fn startTransition(self: *SceneManager, index: usize) void {
        if (index >= self.scenes.len) return;
        if (self.transitionState != .None) return;

        self.cleanupCount = 0;

        const cs = self.currentScene();
        const cc = cs.getCamera() catch {
            return;
        };
        self.zoomStart = cc.zoom;

        // Check scene-specific callback - if it returns false, block transition entirely
        if (!cs.dispatchOnTransition(self, index)) return;

        // Global callback - if it returns false, skip it but continue transition
        if (self.onTransition) |f| {
            _ = f(cs, self, index);
        }

        self.zoomTarget = 1.5;
        self.transitionNextIndex = index;
        self.transitionState = .FadingOut;
        self.transitionTimer = 0.0;
        self.inputBlocked = true;
    }

    pub fn changeScene(self: *SceneManager, index: usize) !void {
        if (index >= self.capacity) return;
        if (self.transitionState != .None) return;
        self.lastIndex = self.currentIndex;
        self.startTransition(index);
    }

    /// Change scene by declared scene name.
    pub fn changeSceneByName(self: *SceneManager, name: []const u8) !void {
        if (self.findSceneByName(name)) |index| {
            try self.changeScene(index);
            return;
        }
        return error.UnknownScene;
    }

    /// Find scene index by declared scene name.
    pub fn findSceneByName(self: *SceneManager, name: []const u8) ?usize {
        for (self.scenes[0..self.capacity], 0..) |*scene, i| {
            if (std.mem.eql(u8, scene.name, name)) {
                return i;
            }
        }
        return null;
    }

    pub fn transferPersistentEntities(self: *SceneManager, from: usize, to: usize, tags: []const []const u8) void {
        if (from >= self.scenes.len or to >= self.scenes.len) return;

        const src_world = &self.scenes[from].world;
        const dst_world = &self.scenes[to].world;

        // First pass: transfer all entities
        for (tags) |tag| {
            self.transferSingleEntity(src_world, dst_world, tag);
        }

        // Second pass: re-link camera follow targets
        var it = dst_world.cameras.iterator();
        while (it.next()) |item| {
            const cam = item.data;
            if (!cam.follow_target.isValid()) {
                if (dst_world.findByTag("player")) |player_entity| {
                    cam.follow_target = player_entity;
                }
            }
        }

        // Defer cleanup
        for (tags) |tag| {
            if (self.cleanupCount < self.objectsToCleanup.len) {
                self.objectsToCleanup[self.cleanupCount] = tag;
                self.cleanupCount += 1;
            }
        }
    }

    fn copyIfPresent(allocator: std.mem.Allocator, src_store: anytype, dst_store: anytype, src: ecs.Entity, dst: ecs.Entity) void {
        if (src_store.get(src)) |c| {
            dst_store.set(allocator, dst, c.*) catch {};
        }
    }

    fn transferSingleEntity(self: *SceneManager, src_world: *ecs.World, dst_world: *ecs.World, tag: []const u8) void {
        _ = self;

        const src_entity = src_world.findByTag(tag) orelse return;

        if (dst_world.findByTag(tag)) |existing| {
            dst_world.despawn(existing);
        }

        const dst_entity = dst_world.spawn();

        // Use the destination world's allocator (scene lifetime) to avoid mixing lifetimes.
        const alloc = dst_world.allocator;
        copyIfPresent(alloc, &src_world.tags, &dst_world.tags, src_entity, dst_entity);
        copyIfPresent(alloc, &src_world.transforms, &dst_world.transforms, src_entity, dst_entity);
        copyIfPresent(alloc, &src_world.sprite_renderers, &dst_world.sprite_renderers, src_entity, dst_entity);
        copyIfPresent(alloc, &src_world.circle_renderers, &dst_world.circle_renderers, src_entity, dst_entity);
        copyIfPresent(alloc, &src_world.rect_renderers, &dst_world.rect_renderers, src_entity, dst_entity);
        copyIfPresent(alloc, &src_world.player_controllers, &dst_world.player_controllers, src_entity, dst_entity);
        copyIfPresent(alloc, &src_world.box_colliders, &dst_world.box_colliders, src_entity, dst_entity);
        copyIfPresent(alloc, &src_world.actives, &dst_world.actives, src_entity, dst_entity);
        copyIfPresent(alloc, &src_world.triggers, &dst_world.triggers, src_entity, dst_entity);

        if (src_world.cameras.get(src_entity)) |cam| {
            var new_cam = cam.*;
            if (cam.follow_target.isValid()) {
                new_cam.follow_target = ecs.Entity.INVALID;
            }
            dst_world.cameras.set(alloc, dst_entity, new_cam) catch {};
        }
    }

    pub fn cleanupTransferredObjects(self: *SceneManager, fromIdx: usize) void {
        if (fromIdx >= self.scenes.len) return;
        const src_world = &self.scenes[fromIdx].world;

        var i: usize = 0;
        while (i < self.cleanupCount) : (i += 1) {
            const tag = self.objectsToCleanup[i];
            if (src_world.findByTag(tag)) |entity| {
                src_world.despawn(entity);
            }
        }
        self.cleanupCount = 0;
    }

    pub fn update(self: *SceneManager, deltaTime: f32) void {
        if (self.transitionState == .None) {
            const cs = self.currentScene();
            cs.dispatchUpdate(deltaTime);
            return;
        }

        self.transitionTimer += deltaTime;
        const dur = self.transitionDuration;

        if (self.transitionState == .FadingOut) {
            const progress = std.math.clamp(self.transitionTimer / dur, 0.0, 1.0);
            const zoomValue = std.math.lerp(self.zoomStart, self.zoomTarget, progress);

            const cs = self.currentScene();
            ecs.Systems.setCameraZoom(&cs.world, zoomValue);

            cs.dispatchUpdate(deltaTime);

            if (self.transitionTimer >= dur) {
                const old = self.currentIndex;
                self.scenes[old].dispatchOnExit();

                if (self.transitionNextIndex) |next| {
                    self.currentIndex = next;
                    self.scenes[self.currentIndex].dispatchOnEnter();
                    self.cleanupTransferredObjects(old);
                }
                self.transitionState = .FadingIn;
                self.transitionTimer = 0.0;
            }
            return;
        }

        if (self.transitionState == .FadingIn) {
            if (self.transitionTimer >= dur) {
                self.transitionState = .None;
                self.transitionTimer = 0.0;
                self.transitionNextIndex = null;
                self.inputBlocked = false;
                ecs.Systems.setCameraZoom(&self.currentScene().world, 1.0);
                return;
            }

            const cs2 = self.currentScene();
            cs2.dispatchUpdate(deltaTime);
            return;
        }
    }

    pub fn draw(self: *SceneManager) void {
        const cs = self.currentScene();
        cs.dispatchDraw();

        if (self.transitionState != .None) {
            const dur = self.transitionDuration;
            var alpha_f: f32 = 0.0;
            if (self.transitionState == .FadingOut) {
                alpha_f = std.math.clamp(self.transitionTimer / dur, 0.0, 1.0);
            } else {
                alpha_f = std.math.clamp(1.0 - (self.transitionTimer / dur), 0.0, 1.0);
            }
            const alpha_u8 = @as(u8, @intFromFloat(alpha_f * 255.0));
            rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), rl.Color{ .r = 0, .g = 0, .b = 0, .a = alpha_u8 });
        }
    }
};

test "scene manager resolves declared scene names" {
    mem.init();
    defer mem.deinit();

    var game_state: state.GameState = undefined;
    var manager = try SceneManager.init(2, &game_state);
    manager.scenes[0].name = "crossroads";
    manager.scenes[1].name = "clearing";

    try std.testing.expectEqual(@as(?usize, 0), manager.findSceneByName("crossroads"));
    try std.testing.expectEqual(@as(?usize, 1), manager.findSceneByName("clearing"));
    try std.testing.expectEqual(@as(?usize, null), manager.findSceneByName("missing"));
}
