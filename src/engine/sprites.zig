const rl = @import("raylib");

pub const Sprite = struct {
    texture: rl.Texture2D,
    x: f32,
    y: f32,
    scale: f32 = 1.0,

    pub fn init(texture: rl.Texture2D, x: f32, y: f32) Sprite {
        return Sprite{
            .texture = texture,
            .x = x,
            .y = y,
            .scale = 1.0,
        };
    }

    pub fn draw(self: *Sprite) void {
        const spriteW: f32 = @floatFromInt(self.texture.width);
        const spriteH: f32 = @floatFromInt(self.texture.height);

        // flip source horizontally when scale is negative, keep dest.x unchanged
        const src = rl.Rectangle{
            .x = if (self.scale < 0.0) spriteW else 0.0,
            .y = 0.0,
            .width = if (self.scale < 0.0) -spriteW else spriteW,
            .height = spriteH,
        };

        const absScale = if (self.scale < 0.0) -self.scale else self.scale;
        const dest = rl.Rectangle{
            .x = self.x,
            .y = self.y,
            .width = spriteW * absScale,
            .height = spriteH * absScale,
        };

        const origin = rl.Vector2{ .x = 0.0, .y = 0.0 };
        rl.drawTexturePro(self.texture, src, dest, origin, 0.0, .white);
    }
};
