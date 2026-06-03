const std = @import("std");

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn fseek(stream: *anyopaque, offset: c_long, origin: c_int) c_int;
extern "c" fn ftell(stream: *anyopaque) c_long;
extern "c" fn fread(ptr: [*]u8, size: usize, count: usize, stream: *anyopaque) usize;

const seek_set = 0;
const seek_end = 2;

pub const Error = error{
    MissingResource,
    InvalidPath,
};

pub const ResourceProvider = struct {
    ctx: *anyopaque,
    readTextFn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]u8,
    readBytesFn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]u8,

    pub fn readText(self: ResourceProvider, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return self.readTextFn(self.ctx, allocator, path);
    }

    pub fn readBytes(self: ResourceProvider, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return self.readBytesFn(self.ctx, allocator, path);
    }
};

pub const FsResourceProvider = struct {
    root: []const u8,

    pub fn provider(self: *FsResourceProvider) ResourceProvider {
        return .{
            .ctx = self,
            .readTextFn = readText,
            .readBytesFn = readBytes,
        };
    }

    fn readText(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return readBytes(ctx, allocator, path);
    }

    fn readBytes(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const self: *FsResourceProvider = @ptrCast(@alignCast(ctx));
        const full_path = try self.resolve(allocator, path);
        defer allocator.free(full_path);
        return readFileAlloc(allocator, full_path);
    }

    pub fn resolve(self: *const FsResourceProvider, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const clean = normalize(path);
        if (std.fs.path.isAbsolute(clean)) return allocator.dupe(u8, clean);
        return std.fs.path.join(allocator, &.{ self.root, clean });
    }
};

pub const MemoryResource = struct {
    path: []const u8,
    bytes: []const u8,
};

pub const MemoryResourceProvider = struct {
    entries: []const MemoryResource,

    pub fn provider(self: *MemoryResourceProvider) ResourceProvider {
        return .{
            .ctx = self,
            .readTextFn = readText,
            .readBytesFn = readBytes,
        };
    }

    fn readText(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return readBytes(ctx, allocator, path);
    }

    fn readBytes(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const self: *MemoryResourceProvider = @ptrCast(@alignCast(ctx));
        const clean = normalize(path);
        for (self.entries) |entry| {
            if (std.mem.eql(u8, normalize(entry.path), clean)) {
                return allocator.dupe(u8, entry.bytes);
            }
        }
        return Error.MissingResource;
    }
};

pub fn normalize(path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, "/")) return path[1..];
    return path;
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const zpath = try allocator.dupeZ(u8, path);
    defer allocator.free(zpath);

    const file = fopen(zpath.ptr, "rb") orelse return error.FileNotFound;
    defer _ = fclose(file);

    if (fseek(file, 0, seek_end) != 0) return error.ReadFailed;
    const len = ftell(file);
    if (len < 0 or len > 1 << 20) return error.ReadFailed;
    if (fseek(file, 0, seek_set) != 0) return error.ReadFailed;

    const out = try allocator.alloc(u8, @intCast(len));
    const read_count = fread(out.ptr, 1, out.len, file);
    if (read_count != out.len) return error.ReadFailed;
    return out;
}

test "memory resource provider reads normalized text paths" {
    const entries = [_]MemoryResource{
        .{ .path = "assets/scenes/start.json", .bytes = "{\"entities\":[]}" },
    };
    var provider_state = MemoryResourceProvider{ .entries = &entries };
    const provider = provider_state.provider();

    const text = try provider.readText(std.testing.allocator, "/assets/scenes/start.json");
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("{\"entities\":[]}", text);
}

test "memory resource provider reports missing resources" {
    var provider_state = MemoryResourceProvider{ .entries = &.{} };
    const provider = provider_state.provider();

    try std.testing.expectError(Error.MissingResource, provider.readBytes(std.testing.allocator, "missing.bin"));
}
