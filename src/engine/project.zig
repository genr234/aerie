const std = @import("std");

pub const ProjectError = error{ InvalidJson, MissingField, InvalidType };

pub const ProjectConfig = struct {
    id: []const u8,
    title: []const u8,
    version: []const u8 = "0.1.0",

    entry_module: []const u8 = "main",
    entry_class: []const u8 = "Game",

    start_scene: []const u8 = "assets/scenes/start.json",

    window_width: i32 = 800,
    window_height: i32 = 450,
    window_title: []const u8 = "Game",
};

pub fn loadProjectConfig(allocator: std.mem.Allocator, project_root: []const u8) !ProjectConfig {
    const manifest_path = try std.fs.path.join(allocator, &.{ project_root, "game.json" });
    defer allocator.free(manifest_path);

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch return ProjectError.MissingField;
    defer file.close();

    const text = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(text);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return ProjectError.InvalidJson;
    defer parsed.deinit();

    return parseProjectConfig(allocator, parsed.value);
}

fn parseProjectConfig(allocator: std.mem.Allocator, root: std.json.Value) !ProjectConfig {
    if (root != .object) return ProjectError.InvalidType;
    const obj = root.object;

    const id = try dupString(allocator, try getString(obj, "id"));
    const title = try dupString(allocator, try getString(obj, "title"));

    var cfg: ProjectConfig = .{
        .id = id,
        .title = title,
        .window_title = title,
    };

    if (obj.get("version")) |v| cfg.version = try dupString(allocator, try asString(v));

    if (obj.get("entry")) |e| {
        if (e != .object) return ProjectError.InvalidType;
        if (e.object.get("module")) |m| cfg.entry_module = try dupString(allocator, try asString(m));
        if (e.object.get("class")) |c| cfg.entry_class = try dupString(allocator, try asString(c));
    }

    if (obj.get("start_scene")) |s| cfg.start_scene = try dupString(allocator, try asString(s));

    if (obj.get("window")) |w| {
        if (w != .object) return ProjectError.InvalidType;
        if (w.object.get("width")) |vv| cfg.window_width = @intCast(try asInt(vv));
        if (w.object.get("height")) |vv| cfg.window_height = @intCast(try asInt(vv));
        if (w.object.get("title")) |vv| cfg.window_title = try dupString(allocator, try asString(vv));
    }

    return cfg;
}

fn getString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const v = obj.get(key) orelse return ProjectError.MissingField;
    return asString(v);
}

fn asString(v: std.json.Value) ![]const u8 {
    return switch (v) {
        .string => v.string,
        else => ProjectError.InvalidType,
    };
}

fn asInt(v: std.json.Value) !i64 {
    return switch (v) {
        .integer => v.integer,
        .float => @intFromFloat(v.float),
        else => ProjectError.InvalidType,
    };
}

fn dupString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    return buf;
}
