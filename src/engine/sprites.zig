const rl = @import("raylib");

pub const Sprite = struct {
    texture: rl.Texture2D,
    x: f32 = 0,
    y: f32 = 0,
    rotation: f32 = 0,
    scale: f32 = 1.0,

    pub fn draw(self: *Sprite) void {
        rl.drawTextureEx(self.texture, rl.Vector2{ .x = self.x, .y = self.y }, self.rotation, self.scale, rl.Color.white);
    }
};
