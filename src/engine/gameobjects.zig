const std = @import("std");
const rl = @import("raylib");
const characters = @import("characters.zig");
const dialogue = @import("dialogue.zig");
const sprites = @import("sprites.zig");

const MAX_GAMEOBJECTS: usize = 128;
const MAX_TRIGGERS_PER_GAMEOBJECT: usize = 16;

pub const TriggerAction = union(enum) {
    print_message: [:0]const u8,
    start_dialogue: struct {
        runner: *dialogue.Runner,
        context: ?*anyopaque,
    },
    run_action: dialogue.ActionFn,
};

pub const Trigger = struct {
    rectangle: rl.Rectangle,
    action: TriggerAction,
    was_inside: bool = false,
    one_shot: bool = false,
    triggered: bool = false,
};

pub const GameObject = struct {
    tag: [64]u8 = [_]u8{0} ** 64,
    tag_len: usize = 0,
    active: bool = true,
    position: rl.Vector2 = rl.Vector2{ .x = 0, .y = 0 },
    data: GameObjectData,
    triggers: [MAX_TRIGGERS_PER_GAMEOBJECT]Trigger = undefined,
    triggers_count: usize = 0,

    const Self = @This();

    pub fn init(tag: []const u8, data: GameObjectData) Self {
        var go = Self{
            .data = data,
            .triggers_count = 0,
        };
        @memcpy(go.tag[0..tag.len], tag);
        go.tag_len = tag.len;
        return go;
    }

    pub fn setTag(self: *Self, tag: []const u8) void {
        if (tag.len > self.tag.len) return;
        @memcpy(self.tag[0..tag.len], tag);
        self.tag_len = tag.len;
    }

    pub fn getTag(self: *const Self) []const u8 {
        return self.tag[0..self.tag_len];
    }

    pub fn addTrigger(self: *Self, rectangle: rl.Rectangle, action: TriggerAction) void {
        if (self.triggers_count >= MAX_TRIGGERS_PER_GAMEOBJECT) return;
        self.triggers[self.triggers_count] = Trigger{
            .rectangle = rectangle,
            .action = action,
            .was_inside = false,
            .one_shot = false,
            .triggered = false,
        };
        self.triggers_count += 1;
    }

    pub fn addOneShotTrigger(self: *Self, rectangle: rl.Rectangle, action: TriggerAction) void {
        if (self.triggers_count >= MAX_TRIGGERS_PER_GAMEOBJECT) return;
        self.triggers[self.triggers_count] = Trigger{
            .rectangle = rectangle,
            .action = action,
            .was_inside = false,
            .one_shot = true,
            .triggered = false,
        };
        self.triggers_count += 1;
    }

    pub fn checkTriggersWithPlayer(self: *Self, playerRect: rl.Rectangle, scene: *@import("scenes.zig").Scene) void {
        var i: usize = 0;
        while (i < self.triggers_count) : (i += 1) {
            var t = &self.triggers[i];

            // Skip already-triggered one-shots
            if (t.one_shot and t.triggered) continue;

            const inside = rl.checkCollisionRecs(playerRect, t.rectangle);
            if (inside and !t.was_inside) {
                switch (t.action) {
                    .print_message => |msg| {
                        scene.message = msg;
                        scene.messageTimer = 2.0;
                    },
                    .start_dialogue => |payload| {
                        payload.runner.start(payload.context);
                    },
                    .run_action => |action| {
                        action(null);
                    },
                }
                if (t.one_shot) t.triggered = true;
            }
            t.was_inside = inside;
        }
    }

    pub fn resetTriggers(self: *Self) void {
        var i: usize = 0;
        while (i < self.triggers_count) : (i += 1) {
            self.triggers[i].was_inside = false;
            self.triggers[i].triggered = false;
        }
    }

    pub fn updatePlayer(self: *Self, deltaTime: f32, paused: bool, scene: *@import("scenes.zig").Scene) void {
        if (self.data != .player) return;

        var player = &self.data.player;
        const spriteW: f32 = @floatFromInt(player.texture.width);
        const spriteH: f32 = @floatFromInt(player.texture.height);
        const sceneW: f32 = @floatFromInt(scene.width);
        const sceneH: f32 = @floatFromInt(scene.height);

        if (!paused) {
            if (rl.isKeyDown(.right)) {
                player.sprite.x += player.speed * deltaTime;
                player.sprite.scale = -1.0;
            }
            if (rl.isKeyDown(.left)) {
                player.sprite.x -= player.speed * deltaTime;
                player.sprite.scale = 1.0;
            }
            if (rl.isKeyDown(.up)) {
                player.sprite.y -= player.speed * deltaTime;
            }
            if (rl.isKeyDown(.down)) {
                player.sprite.y += player.speed * deltaTime;
            }
        }

        if (player.sprite.x < 0) player.sprite.x = 0;
        if (player.sprite.y < 0) player.sprite.y = 0;
        if (player.sprite.x + spriteW > sceneW) player.sprite.x = sceneW - spriteW;
        if (player.sprite.y + spriteH > sceneH) player.sprite.y = sceneH - spriteH;

        self.position = rl.Vector2{ .x = player.sprite.x, .y = player.sprite.y };
        player.scale = player.sprite.scale;
    }

    pub fn getPlayerRect(self: *const Self) rl.Rectangle {
        if (self.data != .player) {
            return rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
        }

        const player = self.data.player;
        const spriteW: f32 = @floatFromInt(player.texture.width);
        const spriteH: f32 = @floatFromInt(player.texture.height);
        const absScale = if (player.scale < 0.0) -player.scale else player.scale;

        return rl.Rectangle{
            .x = player.sprite.x,
            .y = player.sprite.y,
            .width = spriteW * absScale,
            .height = spriteH * absScale,
        };
    }

    pub fn updateCamera(self: *Self, newTarget: rl.Vector2) void {
        if (self.data != .camera) return;
        self.data.camera.target = newTarget;
    }

    pub fn getCamera(self: *const Self) ?rl.Camera2D {
        if (self.data != .camera) return null;
        const cam = self.data.camera;
        return rl.Camera2D{
            .offset = cam.offset,
            .target = cam.target,
            .rotation = cam.rotation,
            .zoom = cam.zoom,
        };
    }
};

pub const GameObjectData = union(enum) {
    circle: struct {
        radius: f32,
        color: rl.Color,
    },
    rectangle: struct {
        width: f32,
        height: f32,
        color: rl.Color,
    },
    sprite: struct {
        texture: rl.Texture2D,
        scale: f32 = 1.0,
    },
    player: struct {
        texture: rl.Texture2D,
        speed: f32 = 100,
        sprite: sprites.Sprite,
        scale: f32 = 1.0,
    },
    camera: struct {
        offset: rl.Vector2,
        target: rl.Vector2,
        rotation: f32 = 0.0,
        zoom: f32 = 1.0,
    },
};

pub const SceneGameObjects = struct {
    gameObjects: [MAX_GAMEOBJECTS]GameObject = undefined,
    count: usize = 0,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .count = 0,
        };
    }

    pub fn addGameObject(self: *Self, go: GameObject) ?usize {
        if (self.count >= MAX_GAMEOBJECTS) return null;
        const index = self.count;
        self.gameObjects[index] = go;
        self.count += 1;
        return index;
    }

    pub fn getGameObject(self: *Self, index: usize) ?*GameObject {
        if (index >= self.count) return null;
        return &self.gameObjects[index];
    }

    pub fn getGameObjectByTag(self: *Self, tag: []const u8) ?*GameObject {
        for (0..self.count) |i| {
            if (std.mem.eql(u8, self.gameObjects[i].getTag(), tag)) {
                return &self.gameObjects[i];
            }
        }
        return null;
    }

    pub fn removeGameObject(self: *Self, index: usize) void {
        if (index >= self.count) return;
        for (index..(self.count - 1)) |i| {
            self.gameObjects[i] = self.gameObjects[i + 1];
        }
        self.count -= 1;
    }

    pub fn checkAllTriggersWithPlayer(self: *Self, playerRect: rl.Rectangle, scene: *@import("scenes.zig").Scene) void {
        for (0..self.count) |i| {
            const go = &self.gameObjects[i];
            if (!go.active) continue;
            go.checkTriggersWithPlayer(playerRect, scene);
        }
    }

    pub fn resetAllTriggers(self: *Self) void {
        for (0..self.count) |i| {
            self.gameObjects[i].resetTriggers();
        }
    }

    pub fn updatePlayer(self: *Self, deltaTime: f32, paused: bool, scene: *@import("scenes.zig").Scene) void {
        for (0..self.count) |i| {
            const go = &self.gameObjects[i];
            if (!go.active or go.data != .player) continue;
            go.updatePlayer(deltaTime, paused, scene);
        }
    }

    pub fn getPlayerRect(self: *Self) ?rl.Rectangle {
        for (0..self.count) |i| {
            const go = &self.gameObjects[i];
            if (!go.active or go.data != .player) continue;
            return go.getPlayerRect();
        }
        return null;
    }

    pub fn getCamera(self: *Self) ?rl.Camera2D {
        for (0..self.count) |i| {
            const go = &self.gameObjects[i];
            if (!go.active or go.data != .camera) continue;
            return go.getCamera();
        }
        return null;
    }

    pub fn updateCamera(self: *Self, newTarget: rl.Vector2) void {
        for (0..self.count) |i| {
            const go = &self.gameObjects[i];
            if (!go.active or go.data != .camera) continue;
            go.updateCamera(newTarget);
            break;
        }
    }

    pub fn updateCameraZoom(self: *Self, zoomValue: f32) void {
        for (0..self.count) |i| {
            const go = &self.gameObjects[i];
            if (!go.active or go.data != .camera) continue;
            go.data.camera.zoom = zoomValue;
            break;
        }
    }

    pub fn draw(self: *Self) void {
        for (0..self.count) |i| {
            const go = &self.gameObjects[i];
            if (!go.active) continue;

            switch (go.data) {
                .circle => |circ| {
                    rl.drawCircle(@intFromFloat(go.position.x), @intFromFloat(go.position.y), circ.radius, circ.color);
                },
                .rectangle => |rect| {
                    rl.drawRectangle(@intFromFloat(go.position.x), @intFromFloat(go.position.y), @intFromFloat(rect.width), @intFromFloat(rect.height), rect.color);
                },
                .sprite => |spr| {
                    rl.drawTextureEx(spr.texture, go.position, 0.0, spr.scale, rl.Color.white);
                },
                .player => |plr| {
                    const spriteW: f32 = @floatFromInt(plr.texture.width);
                    const spriteH: f32 = @floatFromInt(plr.texture.height);

                    // flip source horizontally when scale is negative
                    const src = rl.Rectangle{
                        .x = if (plr.scale < 0.0) spriteW else 0.0,
                        .y = 0.0,
                        .width = if (plr.scale < 0.0) -spriteW else spriteW,
                        .height = spriteH,
                    };

                    const absScale = if (plr.scale < 0.0) -plr.scale else plr.scale;
                    const dest = rl.Rectangle{
                        .x = go.position.x,
                        .y = go.position.y,
                        .width = spriteW * absScale,
                        .height = spriteH * absScale,
                    };

                    const origin = rl.Vector2{ .x = 0.0, .y = 0.0 };
                    rl.drawTexturePro(plr.texture, src, dest, origin, 0.0, .white);
                },
                .camera => {},
            }
        }
    }

    pub fn clear(self: *Self) void {
        self.count = 0;
    }
};

