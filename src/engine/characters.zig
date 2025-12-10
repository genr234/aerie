const sprites = @import("sprites.zig");
const scenes = @import("scenes.zig");

const rl = @import("raylib");

pub const Player = struct {
    texture: rl.Texture2D,
    speed: f32 = 100,
    initialX: f32 = 0,
    initialY: f32 = 0,
    sprite: sprites.Sprite,
    scene: scenes.Scene,

    pub fn init(texture: rl.Texture2D, scene: scenes.Scene, x: f32, y: f32) Player {
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
        };
    }

    pub fn update(self: *Player, deltaTime: f32) void {
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

        const halfW: f32 = self.scene.camera.offset.x / self.scene.camera.zoom;
        const halfH: f32 = self.scene.camera.offset.y / self.scene.camera.zoom;

        if (target.x < halfW) target.x = halfW;
        if (target.y < halfH) target.y = halfH;
        if (self.sprite.x + spriteW > sceneW) self.sprite.x = sceneW - spriteW;
        if (self.sprite.y + spriteH > sceneH) self.sprite.y = sceneH - spriteH;


        self.scene.camera.target = target;

        self.draw();
    }

    fn draw(self: *Player) void {
        self.sprite.draw();
    }
};
