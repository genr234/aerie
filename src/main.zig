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

pub fn main(init_ctx: std.process.Init.Minimal) void {
    var project_root: []const u8 = ".";

    if (comptime builtin.os.tag != .emscripten) {
        var args = std.process.Args.Iterator.initAllocator(init_ctx.args, std.heap.page_allocator) catch return;
        defer args.deinit();
        _ = args.skip();
        if (args.next()) |arg| {
            project_root = arg;
        }
    }

    engine_mod.rl.setExitKey(engine_mod.rl.KeyboardKey.f4);
    engine.init(project_root) catch |err| {
        if (comptime builtin.os.tag != .emscripten) {
            std.debug.print("[runtime] engine init failed for '{s}': {any}\n", .{ project_root, err });
        }
        return;
    };
    defer engine.deinit();

    if (builtin.os.tag == .emscripten) {
        engine.tick();
        engine.draw();
        emscripten_set_main_loop(gameLoop, 0, 1);
    } else {
        while (!engine_mod.rl.windowShouldClose()) {
            engine.tick();
            engine.draw();
        }
    }
}
