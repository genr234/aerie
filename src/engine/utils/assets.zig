const std = @import("std");

fn normalizeAssetPath(path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, "/assets/")) return path["/assets/".len..];
    if (std.mem.startsWith(u8, path, "assets/")) return path["assets/".len..];
    return path;
}

pub fn resolveAssetPath(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    path: []const u8,
    platform: std.Target.Os.Tag,
) ![]u8 {
    if (platform == .emscripten) {
        const rel = normalizeAssetPath(path);
        return std.fmt.allocPrint(allocator, "/assets/{s}", .{rel});
    }

    if (std.fs.path.isAbsolute(path)) {
        return allocator.dupe(u8, path);
    }

    const rel = normalizeAssetPath(path);
    return std.fs.path.join(allocator, &.{ project_root, "assets", rel });
}

pub fn parseAssetPath(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    path: []const u8,
    platform: std.Target.Os.Tag,
) ![:0]u8 {
    var resolved = try resolveAssetPath(allocator, project_root, path, platform);
    const len = resolved.len;
    resolved = try allocator.realloc(resolved, len + 1);
    resolved[len] = 0;
    return @ptrCast(resolved[0..len :0]);
}
