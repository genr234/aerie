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

        // Wren module names are passed without extension.
        // We map "main" -> "assets/scripts/main.wren".
        // Note: parseAssetPath already prepends "assets/" on desktop.
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

        const mod_name = std.mem.span(name);
        std.debug.print("[wren] loadModule '{s}'\n", .{mod_name});
        std.debug.print("[wren]   (raw) ", .{});
        for (mod_name) |ch| std.debug.print("{X:0>2} ", .{ch});
        std.debug.print("\n", .{});

        if (std.mem.eql(u8, mod_name, "engine/api")) {
            return loadEngineApiModule();
        }

        const asset_path = moduleNameToAssetPath(self.allocator, name) catch {
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        std.debug.print("[wren]   -> '{s}'\n", .{asset_path});

        const cwd = std.fs.cwd();
        const file = cwd.openFileZ(asset_path, .{}) catch {
            self.allocator.free(asset_path);
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        defer file.close();

        // Allocate module source using the C allocator so `onComplete` can free
        // it reliably (Wren doesn't pass a Loader instance back).
        // Wren expects a null-terminated C string whose lifetime extends until
        // `onComplete` is called.
        const src = file.readToEndAlloc(std.heap.c_allocator, 1 << 20) catch {
            self.allocator.free(asset_path);
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        defer std.heap.c_allocator.free(src);
        self.allocator.free(asset_path);

        const zsrc = std.heap.c_allocator.allocSentinel(u8, src.len, 0) catch {
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        @memcpy(zsrc[0..src.len], src);

        return .{
            .source = @ptrCast(zsrc.ptr),
            .onComplete = &onModuleSourceFree,
            .userData = zsrc.ptr,
        };
    }

    fn loadEngineApiModule() wren_c.c.WrenLoadModuleResult {
        // The module source is embedded (static storage); no onComplete needed.
        std.debug.print("[wren] providing embedded module 'engine/api'\n", .{});
        return .{ .source = engine_api_source.ptr, .onComplete = null, .userData = null };
    }

    fn onModuleSourceFree(
        vm: ?*wren_c.c.WrenVM,
        name: [*c]const u8,
        result: wren_c.c.WrenLoadModuleResult,
    ) callconv(.c) void {
        _ = vm;
        _ = name;
        if (result.userData) |ud| {
            const zptr: [*:0]u8 = @ptrCast(@alignCast(ud));
            const len = std.mem.len(zptr);
            std.heap.c_allocator.free(zptr[0 .. len + 1]);
        }
        if (result.source != null and result.userData == null) {
            // If we ever return a source pointer without userData, it must be
            // static storage (like the embedded engine/api module).
            // Nothing to clean up here.
        }
    }

    const engine_api_source =
        \\foreign class Engine {
        \\  foreign static showMessage(text, duration)
        \\
        \\  foreign static setFlag(name, value)
        \\  foreign static getFlag(name)
        \\
        \\  foreign static change(index)
        \\  foreign static changeByName(name)
        \\
        \\  foreign static start()
        \\  foreign static startAt(label)
        \\}
        \\
        \\class Events {
        \\  static message(text, duration) { Engine.showMessage(text, duration) }
        \\}
        \\
        \\class Flags {
        \\  static set(name, value) { Engine.setFlag(name, value) }
        \\  static get(name) { Engine.getFlag(name) }
        \\}
        \\
        \\class Scene {
        \\  static change(index) { Engine.change(index) }
        \\  static go(name) { Engine.changeByName(name) }
        \\}
        \\
        \\class Dialogue {
        \\  static start() { Engine.start() }
        \\  static startAt(label) { Engine.startAt(label) }
        \\}
    ;
};
