const rl = @import("raylib");

pub const Scene = struct {
    width: i32 = 800,
    height: i32 = 450,
    camera: rl.Camera2D = rl.Camera2D{
        .offset = rl.Vector2{ .x = 0.0, .y = 0.0 },
        .target = rl.Vector2{ .x = 0.0, .y = 0.0 },
        .rotation = 0.0,
        .zoom = 1.0,
    },
    message: ?[:0]const u8 = null,
    messageTimer: f32 = 0.0,

    pub fn init(width: i32, height: i32) Scene {
        return Scene{
            .width = width,
            .height = height,
            .camera = rl.Camera2D{
                .offset = rl.Vector2{ .x = 0.0, .y = 0.0 },
                .target = rl.Vector2{ .x = 0.0, .y = 0.0 },
                .rotation = 0.0,
                .zoom = 1.0,
            },
            .message = null,
            .messageTimer = 0.0,
        };
    }

    // pub fn setup(self: *Scene) void {}
};
