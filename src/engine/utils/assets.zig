const std = @import("std");

pub fn parseAssetPath(allocator: std.mem.Allocator, path: []const u8, platform: std.Target.Os.Tag) ![:0]u8 {
    const base = switch (platform) {
        .emscripten => "/assets/",
        else => "assets/",
    };
    var assetPath = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base, path });
    assetPath.ptr[assetPath.len] = 0;
    return @ptrCast(assetPath.ptr[0..assetPath.len :0]);
}