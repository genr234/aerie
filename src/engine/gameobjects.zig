const std = @import("std");
const rl = @import("raylib");
const characters = @import("characters.zig");
const dialogue = @import("dialogue.zig");
const sprites = @import("sprites.zig");

const MAX_GAMEOBJECTS: usize = 128;
const MAX_TRIGGERS_PER_GAMEOBJECT: usize = 16;

pub const TriggerAction = union(enum) {
    print_message: [:0]const u8,
    start_dialogue: *dialogue.Dialogue
};

pub const Trigger = struct {
    rectangle: rl.Rectangle,
    action: TriggerAction,
    was_inside: bool = false,
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
        self.triggers[self.triggers_count] = Trigger{ .rectangle = rectangle, .action = action, .was_inside = false };
        self.triggers_count += 1;
    }

    pub fn checkTriggersWithPlayer(self: *Self, playerRect: rl.Rectangle, scene: *@import("scenes.zig").Scene) void {
        var i: usize = 0;
        while (i < self.triggers_count) : (i += 1) {
            var t = &self.triggers[i];
            const inside = rl.checkCollisionRecs(playerRect, t.rectangle);
            if (inside) {
                if (!t.was_inside) {
                    switch (t.action) {
                        .print_message => |msg| {
                            scene.message = msg;
                            scene.messageTimer = 2.0;
                        },
                        .start_dialogue => |dlg| {
                            dlg.start();
                        },
                    }
                }
                t.was_inside = true;
            } else {
                t.was_inside = false;
            }
        }
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
            }
        }
    }

    pub fn clear(self: *Self) void {
        self.count = 0;
    }
};

