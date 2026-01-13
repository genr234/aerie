const std = @import("std");
const builtin = @import("builtin");
const assets = @import("../utils/assets.zig");
const wren_c = @import("wren_c.zig");

pub const Loader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Loader {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Loader) void {
        _ = self;
    }

    fn moduleNameToAssetPath(allocator: std.mem.Allocator, raw_name: [*:0]const u8) ![:0]u8 {
        const name = std.mem.span(raw_name);
        // wren module names are passed without extension.
        // we map "game" -> "scripts/game.wren" and "ui/dialogue" -> "scripts/ui/dialogue.wren".
        const rel = try std.fmt.allocPrint(allocator, "scripts/{s}.wren", .{name});
        defer allocator.free(rel);
        return assets.parseAssetPath(allocator, rel, builtin.os.tag);
    }

    pub fn loadModule(
        self: *Loader,
        vm: ?*wren_c.c.WrenVM,
        name: [*:0]const u8,
    ) callconv(.c) wren_c.c.WrenLoadModuleResult {
        _ = vm;

        const asset_path = moduleNameToAssetPath(self.allocator, name) catch {
            return .{ .source = null, .onComplete = null, .userData = null };
        };

        const cwd = std.fs.cwd();
        const file = cwd.openFileZ(asset_path, .{}) catch {
            self.allocator.free(asset_path);
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        defer file.close();

        const src = file.readToEndAlloc(self.allocator, 1 << 20) catch {
            self.allocator.free(asset_path);
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        self.allocator.free(asset_path);

        // wren expects a null-terminated C string and an onComplete callback to free.
        const zsrc = self.allocator.allocSentinel(u8, src.len, 0) catch {
            self.allocator.free(src);
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        @memcpy(zsrc[0..src.len], src);
        self.allocator.free(src);

        return .{
            .source = @ptrCast(zsrc.ptr),
            .onComplete = &onModuleComplete,
            .userData = zsrc.ptr,
        };
    }

    fn onModuleComplete(
        vm: ?*wren_c.c.WrenVM,
        name: [*c]const u8,
        result: wren_c.c.WrenLoadModuleResult,
    ) callconv(.c) void {
        _ = vm;
        _ = name;

        if (result.userData) |ud| {
            // we don't have allocator here; the runtime owns Loader and will free
            // through a trampoline instead. right now, we leak on purpose only when
            // running in exceptional cases.
            _ = ud;
        }
    }
};
