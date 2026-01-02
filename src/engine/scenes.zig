const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs.zig");

pub const SceneType = enum {
    exploration,
};

const SceneTypeVTable = struct {
    update: ?*const fn (*Scene, f32) void = null,
    draw: ?*const fn (*Scene) void = null,
    onEnter: ?*const fn (*Scene) void = null,
    onExit: ?*const fn (*Scene) void = null,
    onTransition: ?*const fn (*Scene, *SceneManager, usize) void = null,
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

fn explorationOnTransition(scene: *Scene, mgr: *SceneManager, dst_index: usize) void {
    if (scene.onTransition) |f| f(scene, mgr, dst_index);
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
    onTransition: ?*const fn (*Scene, *SceneManager, usize) void = null,
    setup: ?*const fn (*Scene, *anyopaque) void = null,
};

pub const Scene = struct {
    width: i32 = 800,
    height: i32 = 450,

    scene_type: SceneType = .exploration,

    update: ?*const fn (*Scene, f32) void = null,
    draw: ?*const fn (*Scene) void = null,
    onEnter: ?*const fn (*Scene) void = null,
    onExit: ?*const fn (*Scene) void = null,
    onTransition: ?*const fn (*Scene, *SceneManager, usize) void = null,

    message: ?[:0]const u8 = null,
    messageTimer: f32 = 0.0,

    world: ecs.World = ecs.World.init(),

    const Self = @This();

    pub fn init(width: i32, height: i32) Scene {
        var scene = Scene{
            .width = width,
            .height = height,
            .scene_type = .exploration,
        };
        scene.world.bounds_width = @floatFromInt(width);
        scene.world.bounds_height = @floatFromInt(height);
        return scene;
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

    pub fn dispatchOnTransition(self: *Self, mgr: *SceneManager, dst_index: usize) void {
        const vt = self.vtable();
        if (vt.onTransition) |f| f(self, mgr, dst_index);
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
        ecs.Systems.handleEvents(&self.world, dt);
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
};

pub const Builder = struct {
    scene: Scene,

    pub fn init(width: i32, height: i32) Builder {
        return .{ .scene = Scene.init(width, height) };
    }

    pub fn reset(self: *Builder, width: i32, height: i32) *Builder {
        self.scene = Scene.init(width, height);
        return self;
    }

    pub fn buildAndReset(self: *Builder, width: i32, height: i32) Scene {
        const out = self.scene;
        self.scene = Scene.init(width, height);
        return out;
    }

    pub fn sceneType(self: *Builder, t: SceneType) *Builder {
        self.scene.scene_type = t;
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

    pub fn onTransition(self: *Builder, func: *const fn (*Scene, *SceneManager, usize) void) *Builder {
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

    pub fn initStatic(scenes_ptr: []Scene) SceneManager {
        return .{
            .scenes = scenes_ptr,
            .capacity = scenes_ptr.len,
            .history = &.{},
            .objectsToCleanup = undefined,
        };
    }

    pub fn initWithAllocator(allocator: *std.mem.Allocator, capacity: usize) !SceneManager {
        const scenes_ptr = try allocator.alloc(Scene, capacity);
        for (scenes_ptr) |*s| {
            s.* = Scene.init(800, 450);
        }
        const history_ptr = try allocator.alloc(usize, capacity);
        @memset(history_ptr, 0);

        return .{
            .scenes = scenes_ptr,
            .allocator = allocator,
            .capacity = capacity,
            .history = history_ptr,
            .objectsToCleanup = undefined,
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

    fn startTransition(self: *SceneManager, index: usize) void {
        if (index >= self.scenes.len) return;
        if (self.transitionState != .None) return;

        self.cleanupCount = 0;

        const cs = self.currentScene();
        const cc = cs.getCamera() catch {
            return;
        };
        self.zoomStart = cc.zoom;

        cs.dispatchOnTransition(self, index);

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

    fn transferSingleEntity(self: *SceneManager, src_world: *ecs.World, dst_world: *ecs.World, tag: []const u8) void {
        _ = self;

        const src_entity = src_world.findByTag(tag) orelse return;

        if (dst_world.findByTag(tag)) |existing| {
            dst_world.despawn(existing);
        }

        const dst_entity = dst_world.spawn();

        if (src_world.tags.get(src_entity)) |t| dst_world.tags.set(dst_entity, t.*);
        if (src_world.transforms.get(src_entity)) |t| dst_world.transforms.set(dst_entity, t.*);
        if (src_world.sprite_renderers.get(src_entity)) |t| dst_world.sprite_renderers.set(dst_entity, t.*);
        if (src_world.circle_renderers.get(src_entity)) |t| dst_world.circle_renderers.set(dst_entity, t.*);
        if (src_world.rect_renderers.get(src_entity)) |t| dst_world.rect_renderers.set(dst_entity, t.*);
        if (src_world.player_controllers.get(src_entity)) |t| dst_world.player_controllers.set(dst_entity, t.*);
        if (src_world.box_colliders.get(src_entity)) |t| dst_world.box_colliders.set(dst_entity, t.*);
        if (src_world.actives.get(src_entity)) |t| dst_world.actives.set(dst_entity, t.*);

        if (src_world.cameras.get(src_entity)) |cam| {
            var new_cam = cam.*;
            if (cam.follow_target.isValid()) {
                new_cam.follow_target = ecs.Entity.INVALID;
            }
            dst_world.cameras.set(dst_entity, new_cam);
        }

        if (src_world.triggers.get(src_entity)) |trig| {
            dst_world.triggers.set(dst_entity, trig.*);
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
