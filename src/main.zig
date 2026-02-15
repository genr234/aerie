const std = @import("std");
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
    var project_root: []const u8 = ".";

    if (builtin.os.tag != .emscripten) {
        const allocator = std.heap.page_allocator;
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        if (args.len > 1) {
            project_root = args[1];
        }
    }

    try engine.init(project_root);
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
