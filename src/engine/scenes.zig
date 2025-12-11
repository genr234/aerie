const std = @import("std");
const rl = @import("raylib");
const gameobjects = @import("gameobjects.zig");

pub const Scene = struct {
    width: i32 = 800,
    height: i32 = 450,
    camera: rl.Camera2D = rl.Camera2D{
        .offset = rl.Vector2{ .x = 0.0, .y = 0.0 },
        .target = rl.Vector2{ .x = 0.0, .y = 0.0 },
        .rotation = 0.0,
        .zoom = 1.0,
    },
    update: ?*const fn (scene: *Scene, deltaTime: f32) void = null,
    draw: ?*const fn (scene: *Scene) void = null,
    onEnter: ?*const fn (scene: *Scene) void = null,
    onExit: ?*const fn (scene: *Scene) void = null,
    message: ?[:0]const u8 = null,
    messageTimer: f32 = 0.0,

    // Scene game objects
    gameObjects: gameobjects.SceneGameObjects = gameobjects.SceneGameObjects.init(),

    const Self = @This();

    pub fn init(
        width: i32,
        height: i32,
        update: ?*const fn (scene: *Scene, deltaTime: f32) void,
        draw: ?*const fn (scene: *Scene) void,
        onEnter: ?*const fn (scene: *Scene) void,
        onExit: ?*const fn (scene: *Scene) void,
    ) Scene {
        return Scene{
            .width = width,
            .height = height,
            .camera = rl.Camera2D{
                .offset = rl.Vector2{ .x = 0.0, .y = 0.0 },
                .target = rl.Vector2{ .x = 0.0, .y = 0.0 },
                .rotation = 0.0,
                .zoom = 1.0,
            },
            .update = update,
            .draw = draw,
            .onEnter = onEnter,
            .onExit = onExit,
            .message = null,
            .messageTimer = 0.0,
            .gameObjects = gameobjects.SceneGameObjects.init(),
        };
    }

    pub fn addGameObject(self: *Self, go: gameobjects.GameObject) ?usize {
        return self.gameObjects.addGameObject(go);
    }

    pub fn getGameObject(self: *Self, index: usize) ?*gameobjects.GameObject {
        return self.gameObjects.getGameObject(index);
    }

    pub fn getGameObjectByTag(self: *Self, tag: []const u8) ?*gameobjects.GameObject {
        return self.gameObjects.getGameObjectByTag(tag);
    }

    pub fn removeGameObject(self: *Self, index: usize) void {
        self.gameObjects.removeGameObject(index);
    }

    pub fn checkGameObjectTriggers(self: *Self, playerRect: rl.Rectangle) void {
        self.gameObjects.checkAllTriggersWithPlayer(playerRect, self);
    }

    pub fn drawGameObjects(self: *Self) void {
        self.gameObjects.draw();
    }

    pub fn clearGameObjects(self: *Self) void {
        self.gameObjects.clear();
    }

    // pub fn setup(self: *Scene) void {}
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

    // initialize with an external buffer (caller must ensure buffer outlives manager)
    pub fn initStatic(scenes: []Scene) SceneManager {
        return SceneManager{
            .scenes = scenes,
            .currentIndex = 0,
            .lastIndex = 0,
            .allocator = null,
            .capacity = scenes.len,
            .history = []usize{},
            .historyTop = 0,
            .transitionState = TransitionState.None,
            .transitionTimer = 0.0,
            .transitionDuration = 0.4,
            .transitionNextIndex = null,
            .inputBlocked = false,
        };
    }

    pub fn initWithAllocator(allocator: *std.mem.Allocator, capacity: usize) !SceneManager {
        const scenes_ptr = try allocator.alloc(Scene, capacity);
        // initialize entries with sensible defaults
        for (scenes_ptr[0..capacity]) |*s| {
            s.* = Scene.init(800, 450, null, null, null, null);
        }
        const history_ptr = try allocator.alloc(usize, capacity);
        // zero history
        for (history_ptr[0..capacity]) |*h| h.* = 0;

        return SceneManager{
            .scenes = scenes_ptr[0..capacity],
            .currentIndex = 0,
            .lastIndex = 0,
            .allocator = allocator,
            .capacity = capacity,
            .history = history_ptr[0..capacity],
            .historyTop = 0,
            .transitionState = TransitionState.None,
            .transitionTimer = 0.0,
            .transitionDuration = 0.4,
            .transitionNextIndex = null,
            .inputBlocked = false,
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
            self.allocator = null;
            self.capacity = 0;
            self.currentIndex = 0;
            self.lastIndex = 0;
            self.transitionState = TransitionState.None;
            self.transitionTimer = 0.0;
            self.transitionNextIndex = null;
            self.inputBlocked = false;
        }
    }

    pub fn init(scenes: []Scene) SceneManager {
        return SceneManager.initStatic(scenes);
    }

    pub fn currentScene(self: *SceneManager) *Scene {
        return &self.scenes[self.currentIndex];
    }

    fn startTransition(self: *SceneManager, index: usize) void {
        if (index >= self.scenes.len) return;
        if (self.transitionState != TransitionState.None) return;
        self.transitionNextIndex = index;
        self.transitionState = TransitionState.FadingOut;
        self.transitionTimer = 0.0;
        self.inputBlocked = true;
    }

    pub fn changeScene(self: *SceneManager, index: usize) void {
        if (index >= self.scenes.len) return;
        self.lastIndex = self.currentIndex;
        self.startTransition(index);
    }

    pub fn pushScene(self: *SceneManager, index: usize) void {
        if (index >= self.scenes.len) return;
        if (self.history.len != 0) {
            if (self.historyTop < self.history.len) {
                self.history[self.historyTop] = self.currentIndex;
                self.historyTop += 1;
            } else {
                for (0..(self.history.len - 1)) |i| {
                    self.history[i] = self.history[i + 1];
                }
                self.history[self.history.len - 1] = self.currentIndex;
            }
        } else {
            self.lastIndex = self.currentIndex;
        }
        self.startTransition(index);
    }

    pub fn nextScene(self: *SceneManager) void {
        if (self.currentIndex + 1 < self.scenes.len) {
            self.lastIndex = self.currentIndex;
            self.startTransition(self.currentIndex + 1);
        }
    }

    pub fn popScene(self: *SceneManager) void {
        var target: ?usize = null;
        if (self.history.len != 0 and self.historyTop > 0) {
            self.historyTop -= 1;
            target = self.history[self.historyTop];
        } else if (self.lastIndex < self.scenes.len) {
            target = self.lastIndex;
        }
        if (target) |t| {
            self.startTransition(t);
        }
    }

    pub fn update(self: *SceneManager, deltaTime: f32) void {
        if (self.transitionState == TransitionState.None) {
            const cs = self.currentScene();
            if (cs.update) |u| u(cs, deltaTime);
            return;
        }

        self.transitionTimer += deltaTime;
        const dur = self.transitionDuration;
        if (self.transitionState == TransitionState.FadingOut) {
            if (self.transitionTimer >= dur) {
                const old = self.currentIndex;
                if (self.scenes[old].onExit) |oe| oe(&self.scenes[old]);
                if (self.transitionNextIndex) |next| {
                    self.currentIndex = next;
                    if (self.scenes[self.currentIndex].onEnter) |ie| ie(&self.scenes[self.currentIndex]);
                }
                self.transitionState = TransitionState.FadingIn;
                self.transitionTimer = 0.0;
            } else {

            }
        } else if (self.transitionState == TransitionState.FadingIn) {
            if (self.transitionTimer >= dur) {
                self.transitionState = TransitionState.None;
                self.transitionTimer = 0.0;
                self.transitionNextIndex = null;
                self.inputBlocked = false;
            }
        }

        if (self.transitionState == TransitionState.FadingIn) {
            const cs2 = self.currentScene();
            if (cs2.update) |upfn| upfn(cs2, deltaTime);
        }
    }

    pub fn draw(self: *SceneManager) void {
        const cs = self.currentScene();
        if (cs.draw) |d| d(cs);

        if (self.transitionState != TransitionState.None) {
             const dur = self.transitionDuration;
             var alpha_f: f32 = 0.0;
             if (self.transitionState == TransitionState.FadingOut) {
                 alpha_f = std.math.clamp(self.transitionTimer / dur, 0.0, 1.0);
             } else {
                 alpha_f = std.math.clamp(1.0 - (self.transitionTimer / dur), 0.0, 1.0);
             }
             const alpha_u8 = @as(u8, @intFromFloat(alpha_f * 255.0));
             const col = rl.Color{ .r = 0, .g = 0, .b = 0, .a = alpha_u8 };
             const w = rl.getScreenWidth();
             const h = rl.getScreenHeight();
             rl.drawRectangle(0, 0, w, h, col);
        }
    }
};
