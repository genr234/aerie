//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// modules
pub const memory = @import("engine/memory.zig");
pub const scenes = @import("engine/scenes.zig");
pub const ecs = @import("engine/ecs.zig");
pub const dialogue = @import("engine/dialogue.zig");
pub const events = @import("engine/events.zig");
pub const story = @import("engine/story.zig");
pub const vn = @import("engine/vn.zig");
pub const audio = @import("engine/audio.zig");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

