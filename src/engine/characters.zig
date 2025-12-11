const std = @import("std");
const sprites = @import("sprites.zig");
const scenes = @import("scenes.zig");

const rl = @import("raylib");

const MAX_TRIGGERS: usize = 32;
const TriggerError = error{TooManyTriggers};

pub const TriggerAction = union(enum) {
    print_message: [:0]const u8,
};

const Trigger = struct {
    rectangle: rl.Rectangle,
    action: TriggerAction,
};

pub const Player = struct {
    texture: rl.Texture2D,
    speed: f32 = 100,
    initialX: f32 = 0,
    initialY: f32 = 0,
    sprite: sprites.Sprite,
    scene: *scenes.Scene,
    range: rl.Rectangle,
    triggers: [MAX_TRIGGERS]Trigger,
    triggers_count: usize,

    pub fn init(texture: rl.Texture2D, scene: *scenes.Scene, x: f32, y: f32) !Player {
        return Player{
            .texture = texture,
            .initialX = x,
            .initialY = y,
            .sprite = sprites.Sprite{
                .texture = texture,
                .x = x,
                .y = y,
            },
            .scene = scene,
            .range = rl.Rectangle{
                .x = x - 50,
                .y = y - 50,
                .width = 70,
                .height = 70,
            },
            // initialize the fixed-size array as `undefined`; we'll track used entries via triggers_count
            .triggers = undefined,
            .triggers_count = 0,
        };
    }

    // pub fn deinit(self: *Player) void {}

    pub fn update(self: *Player, deltaTime: f32) !void {
        if (rl.isKeyDown(.right)) {
            self.sprite.x += self.speed * deltaTime;
            self.sprite.scale = -1.0;
        }
        if (rl.isKeyDown(.left)) {
            self.sprite.x -= self.speed * deltaTime;
            self.sprite.scale = 1.0;
        }
        if (rl.isKeyDown(.up)) {
            self.sprite.y -= self.speed * deltaTime;
        }
        if (rl.isKeyDown(.down)) {
            self.sprite.y += self.speed * deltaTime;
        }

        const spriteW: f32 = @floatFromInt(self.texture.width);
        const spriteH: f32 = @floatFromInt(self.texture.height);
        const sceneW: f32 = @floatFromInt(self.scene.width);
        const sceneH: f32 = @floatFromInt(self.scene.height);

        if (self.sprite.x < 0) self.sprite.x = 0;
        if (self.sprite.y < 0) self.sprite.y = 0;

        var target = rl.Vector2{
            .x = self.sprite.x + spriteW / 2,
            .y = self.sprite.y + spriteH / 2,
        };

        self.range.x = self.sprite.x + spriteW / 2 - self.range.width / 2;
        self.range.y = self.sprite.y + spriteH / 2 - self.range.height / 2;
        rl.drawRectangleRec(self.range, .pink);

        const halfW: f32 = self.scene.camera.offset.x / self.scene.camera.zoom;
        const halfH: f32 = self.scene.camera.offset.y / self.scene.camera.zoom;

        if (target.x < halfW) target.x = halfW;
        if (target.y < halfH) target.y = halfH;
        if (self.sprite.x + spriteW > sceneW) self.sprite.x = sceneW - spriteW;
        if (self.sprite.y + spriteH > sceneH) self.sprite.y = sceneH - spriteH;


        self.scene.camera.target = target;

        self.checkTriggers();

        try self.draw();
    }

    pub fn addTrigger(self: *Player, rectangle: rl.Rectangle, action: TriggerAction) !void {
        if (self.triggers_count >= MAX_TRIGGERS) return TriggerError.TooManyTriggers;
        self.triggers[self.triggers_count] = Trigger{ .rectangle = rectangle, .action = action };
        self.triggers_count += 1;
    }

    fn checkTriggers(self: *Player) void {
        // build player rectangle (match how sprites are drawn)
        const spriteW: f32 = @floatFromInt(self.texture.width);
        const spriteH: f32 = @floatFromInt(self.texture.height);
        const absScale = if (self.sprite.scale < 0.0) -self.sprite.scale else self.sprite.scale;
        const playerRec = rl.Rectangle{
            .x = self.sprite.x,
            .y = self.sprite.y,
            .width = spriteW * absScale,
            .height = spriteH * absScale,
        };

        var i: usize = 0;
        while (i < self.triggers_count) : (i += 1) {
            const t = &self.triggers[i];
            if (rl.checkCollisionRecs(playerRec, t.rectangle)) {
                // execute the action
                switch (t.action) {
                    .print_message => |msg| {
                        self.scene.message = msg;
                        self.scene.messageTimer = 2.0; // show for 2 seconds
                    },
                }
            }
        }
    }

    fn draw(self: *Player) !void {
        self.sprite.draw();
    }
};
