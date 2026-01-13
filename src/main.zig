const builtin = @import("builtin");
const engine_mod = @import("engine/engine.zig");

// Emscripten imports
extern "c" fn emscripten_set_main_loop(func: *const fn () callconv(.c) void, fps: i32, simulate_infinite_loop: i32) void;

var engine: engine_mod.Engine = .{};

fn gameLoop() callconv(.c) void {
    engine.tick();
    engine.draw();
}

pub fn main() !void {
    try engine.init();
    defer engine.deinit();

    if (builtin.os.tag == .emscripten) {
        emscripten_set_main_loop(gameLoop, 0, 1);
    } else {
        while (!engine_mod.rl.windowShouldClose()) {
            engine.tick();
            engine.draw();
        }
    }
}
