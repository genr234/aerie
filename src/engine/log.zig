const std = @import("std");
const builtin = @import("builtin");

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    switch (builtin.os.tag) {
        .emscripten => {},
        else => std.debug.print(fmt, args),
    }
}
