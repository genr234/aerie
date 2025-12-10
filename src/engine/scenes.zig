pub const Scene = struct {
    width: i32 = 800,
    height: i32 = 450,

    pub fn init(width: i32, height: i32) Scene {
        return Scene{
            .width = width,
            .height = height,
        };
    }

    // pub fn setup(self: *Scene) void {
        // Placeholder for scene setup logic
    // }
};
