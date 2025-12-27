const std = @import("std");
const rl = @import("raylib");
const gameobjects = @import("gameobjects.zig");

pub const ObjectConfig = struct {
    tag: []const u8,
    position: rl.Vector2 = rl.Vector2{ .x = 0, .y = 0 },
    data: gameobjects.GameObjectData,
    trigger: ?TriggerConfig = null,
};

pub const TriggerConfig = struct {
    bounds: rl.Rectangle,
    action: gameobjects.TriggerAction,
};

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
    objects: []const ObjectConfig = &.{},

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
    camera: rl.Camera2D = rl.Camera2D{
        .offset = .{ .x = 0, .y = 0 },
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1.0,
    },

    scene_type: SceneType = .exploration,

    update: ?*const fn (*Scene, f32) void = null,
    draw: ?*const fn (*Scene) void = null,
    onEnter: ?*const fn (*Scene) void = null,
    onExit: ?*const fn (*Scene) void = null,
    onTransition: ?*const fn (*Scene, *SceneManager, usize) void = null,

    message: ?[:0]const u8 = null,
    messageTimer: f32 = 0.0,

    gameObjects: gameobjects.SceneGameObjects = gameobjects.SceneGameObjects.init(),

    const Self = @This();

    pub fn init(width: i32, height: i32) Scene {
        return .{
            .width = width,
            .height = height,
            .scene_type = .exploration,
        };
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

    pub fn add(self: *Self, go: gameobjects.GameObject) void {
        _ = self.gameObjects.addGameObject(go);
    }

    pub fn get(self: *Self, tag: []const u8) ?*gameobjects.GameObject {
        return self.gameObjects.getGameObjectByTag(tag);
    }

    pub fn drawGameObjects(self: *Self) void {
        self.gameObjects.draw();
    }

    pub fn updatePlayer(self: *Self, dt: f32, paused: bool) void {
        self.gameObjects.updatePlayer(dt, paused, self);
    }

    pub fn checkTriggers(self: *Self, player_rect: rl.Rectangle) void {
        self.gameObjects.checkAllTriggersWithPlayer(player_rect, self);
    }

    pub fn getCamera(self: *Self) ?rl.Camera2D {
        return self.gameObjects.getCamera();
    }

    pub fn updateCamera(self: *Self, target: rl.Vector2) void {
        self.gameObjects.updateCamera(target);
    }

    pub fn getPlayerRect(self: *Self) ?rl.Rectangle {
        return self.gameObjects.getPlayerRect();
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
        self.scene.add(gameobjects.GameObject.init(tag, gameobjects.GameObjectData{
            .camera = .{
                .offset = cam.offset,
                .target = cam.target,
                .rotation = cam.rotation,
                .zoom = cam.zoom,
            },
        }));
        return self;
    }

    pub fn player(self: *Builder, tag: []const u8, config: struct {
        texture: rl.Texture2D,
        speed: f32 = 100,
        scale: f32 = 1.0,
        spawn: rl.Vector2,
    }) *Builder {
        var go = gameobjects.GameObject.init(tag, gameobjects.GameObjectData{
            .player = .{
                .texture = config.texture,
                .speed = config.speed,
                .sprite = .{
                    .texture = config.texture,
                    .x = config.spawn.x,
                    .y = config.spawn.y,
                },
                .scale = config.scale,
            },
        });
        go.position = config.spawn;
        self.scene.add(go);
        return self;
    }

    pub fn circle(self: *Builder, tag: []const u8, pos: rl.Vector2, radius: f32, color: rl.Color) *Builder {
        var go = gameobjects.GameObject.init(tag, gameobjects.GameObjectData{
            .circle = .{ .radius = radius, .color = color },
        });
        go.position = pos;
        self.scene.add(go);
        return self;
    }

    pub fn rect(self: *Builder, tag: []const u8, pos: rl.Vector2, size: rl.Vector2, color: rl.Color) *Builder {
        var go = gameobjects.GameObject.init(tag, gameobjects.GameObjectData{
            .rectangle = .{ .width = size.x, .height = size.y, .color = color },
        });
        go.position = pos;
        self.scene.add(go);
        return self;
    }

    pub fn trigger(self: *Builder, tag: []const u8, bounds: rl.Rectangle, action: gameobjects.TriggerAction) *Builder {
        if (self.scene.get(tag)) |go| {
            go.addTrigger(bounds, action);
        }
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

        const cs = self.currentScene();
        if (cs.getCamera()) |cam| {
            self.zoomStart = cam.zoom;
        } else {
            self.zoomStart = 1.0;
        }

        self.cleanupCount = 0;
        cs.dispatchOnTransition(self, index);

        self.zoomTarget = 1.5;
        self.transitionNextIndex = index;
        self.transitionState = .FadingOut;
        self.transitionTimer = 0.0;
        self.inputBlocked = true;
    }

    pub fn changeScene(self: *SceneManager, index: usize) !void {
        if (index >= self.capacity) return error.IndexOutOfBounds;
        if (self.transitionState != .None) return error.TransitionInProgress;
        self.lastIndex = self.currentIndex;
        self.startTransition(index);
    }

    pub fn transferGameObject(self: *SceneManager, from: usize, to: usize, tag: []const u8) bool {
        if (from >= self.scenes.len or to >= self.scenes.len) return false;

        const src = &self.scenes[from];
        const dst = &self.scenes[to];

        {
            var j: usize = 0;
            while (j < dst.gameObjects.count) : (j += 1) {
                if (std.mem.eql(u8, dst.gameObjects.gameObjects[j].getTag(), tag)) {
                    dst.gameObjects.removeGameObject(j);
                    break;
                }
            }
        }

        var i: usize = 0;
        while (i < src.gameObjects.count) : (i += 1) {
            if (std.mem.eql(u8, src.gameObjects.gameObjects[i].getTag(), tag)) {
                const moved = src.gameObjects.gameObjects[i];
                src.gameObjects.removeGameObject(i);
                dst.add(moved);
                return true;
            }
        }

        return false;
    }

    pub fn cleanupTransferredObjects(self: *SceneManager, fromIdx: usize) void {
        _ = self;
        _ = fromIdx;
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
            cs.gameObjects.updateCameraZoom(zoomValue);

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
                self.currentScene().gameObjects.updateCameraZoom(1.0);
                return;
            }

            // Durante il fade-in, la scena visibile è quella nuova.
            const cs2 = self.currentScene();
            cs2.dispatchUpdate(deltaTime);
            return;
        }
    }

    pub fn draw(self: *SceneManager) void {
        // Durante il fade-out la scena visibile deve essere quella vecchia.
        // Durante il fade-in / None, quella corrente (che è già stata switchata).
        // Nota: il cambio indice avviene alla fine del fade-out (in update).
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
