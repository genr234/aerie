const std = @import("std");
const builtin = @import("builtin");

const wren_c = @import("wren_c.zig");
const loader_mod = @import("loader.zig");
const api = @import("api.zig");
const context = @import("context.zig");

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    vm: ?*wren_c.c.WrenVM = null,

    loader: loader_mod.Loader,
    ctx: *context.ScriptingContext,

    entry_module: [:0]const u8,
    entry_class: [:0]const u8,

    game_class: ?*wren_c.c.WrenHandle = null,
    on_boot: ?*wren_c.c.WrenHandle = null,
    on_update: ?*wren_c.c.WrenHandle = null,
    boot_ok: bool = false,

    // desktop auto-reload.
    last_mtime_ns: ?i128 = null,

    // Captured by errorFn for easier debugging.
    last_error: [256]u8 = [_]u8{0} ** 256,
    last_error_len: usize = 0,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        ctx: *context.ScriptingContext,
        entry_module: []const u8,
        entry_class: []const u8,
    ) !Self {
        const loader = loader_mod.Loader.init(allocator);
        var self: Self = .{
            .allocator = allocator,
            .loader = loader,
            .ctx = ctx,
            .entry_module = try allocator.dupeZ(u8, entry_module),
            .entry_class = try allocator.dupeZ(u8, entry_class),
        };
        try self.createVm();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.destroyVm();
        self.loader.deinit();
        self.allocator.free(self.entry_module);
        self.allocator.free(self.entry_class);
    }

    fn destroyVm(self: *Self) void {
        if (self.vm) |vm| {
            if (self.game_class) |h| wren_c.c.wrenReleaseHandle(vm, h);
            if (self.on_boot) |h| wren_c.c.wrenReleaseHandle(vm, h);
            if (self.on_update) |h| wren_c.c.wrenReleaseHandle(vm, h);
            self.game_class = null;
            self.on_boot = null;
            self.on_update = null;

            wren_c.c.wrenFreeVM(vm);
            self.vm = null;
        }
    }

    fn createVm(self: *Self) !void {
        var config: wren_c.c.WrenConfiguration = undefined;
        wren_c.c.wrenInitConfiguration(&config);

        config.writeFn = &writeFn;
        config.errorFn = &errorFn;
        config.loadModuleFn = &loadModuleTrampoline;
        config.bindForeignMethodFn = &api.Api.foreignMethod;
        config.bindForeignClassFn = &api.Api.foreignClass;

        // Store Runtime in user data so callbacks can access loader+ctx.
        // Wren stores userData as `?*anyopaque`; keep pointer stable.
        config.userData = @ptrCast(self);

        self.vm = wren_c.c.wrenNewVM(&config);

        try self.loadAndBindGame();
    }

    fn loadAndBindGame(self: *Self) !void {
        const vm = self.vm.?;

        // Load and compile the entry module directly (no scratch import).
        // This follows Wren's embedding docs: interpret module source, then
        // look up variables from that same module.
        const module_name = self.entry_module;
        const asset_path = try std.fmt.allocPrint(self.allocator, "assets/scripts/{s}.wren", .{module_name});
        defer self.allocator.free(asset_path);

        const file = std.fs.cwd().openFile(asset_path, .{}) catch |err| {
            std.debug.print("[wren] failed to open {s}: {any}\\n", .{ asset_path, err });
            return error.WrenLoadFailed;
        };
        defer file.close();

        const src = try file.readToEndAlloc(self.allocator, 1 << 20);
        defer self.allocator.free(src);

        const zsrc = try self.allocator.allocSentinel(u8, src.len, 0);
        defer self.allocator.free(zsrc);
        @memcpy(zsrc[0..src.len], src);

        const interpret_res = wren_c.c.wrenInterpret(vm, module_name.ptr, zsrc.ptr);
        std.debug.print("[wren] interpret '{s}' res={d}\\n", .{ module_name, @as(u32, @intCast(interpret_res)) });
        if (interpret_res != wren_c.c.WREN_RESULT_SUCCESS) {
            if (self.last_error_len > 0) {
                std.debug.print("[wren] interpret error: {s}\\n", .{self.last_error[0..self.last_error_len]});
            }
            return error.WrenLoadFailed;
        }

        // Fetch the Game class (as an object in slot 0).
        // Note: vanilla Wren will ASSERT in debug builds if module/variable missing.
        wren_c.c.wrenEnsureSlots(vm, 1);

        wren_c.c.wrenGetVariable(vm, module_name.ptr, self.entry_class.ptr, 0);

        const slot_type = wren_c.c.wrenGetSlotType(vm, 0);
        // Class objects show up as WREN_TYPE_UNKNOWN (non-primitive object).
        // If we get NULL or a primitive like BOOL, the lookup failed.
        if (slot_type == wren_c.c.WREN_TYPE_NULL or slot_type == wren_c.c.WREN_TYPE_BOOL or
            slot_type == wren_c.c.WREN_TYPE_NUM or slot_type == wren_c.c.WREN_TYPE_STRING)
        {
            std.debug.print("[wren] getVariable '{s}' in module '{s}' returned type {d}, expected class\n", .{ self.entry_class, module_name, slot_type });
            return error.WrenLoadFailed;
        }
        self.game_class = wren_c.c.wrenGetSlotHandle(vm, 0);

        // Methods are static, but in Wren's C API you call them on the class
        // object using the regular method signature (no "static" prefix).
        // Per Wren's own API tests, 0-arg methods may be "name" or "name()".
        self.on_boot = wren_c.c.wrenMakeCallHandle(vm, "onBoot()");
        self.on_update = wren_c.c.wrenMakeCallHandle(vm, "onUpdate(_)");

        // Note: `wrenHasVariable()` requires the variable name to include the
        // full declaration prefix (e.g. "Game"), and in practice it tends to be
        // more confusing than helpful. If `wrenGetVariable()` failed, the slot
        // value will be null/invalid and calls will fail with a runtime error.
        // We'll rely on the call result + errorFn for diagnostics.
        if (!wren_c.c.wrenHasModule(vm, module_name.ptr)) {
            std.debug.print("[wren] module not loaded: {s}\\n", .{module_name});
        }

        // call once on init.
        self.boot_ok = self.callOnBoot();
        std.debug.print("[wren] callOnBoot ok={any}\n", .{self.boot_ok});

        // seed mtime for auto reload.
        _ = self.checkAndUpdateMtime();
    }

    pub fn callOnBoot(self: *Self) bool {
        const vm = self.vm orelse return false;
        wren_c.c.wrenEnsureSlots(vm, 1);
        wren_c.c.wrenSetSlotHandle(vm, 0, self.game_class.?);
        self.last_error_len = 0;

        const res = wren_c.c.wrenCall(vm, self.on_boot.?);
        if (res != wren_c.c.WREN_RESULT_SUCCESS) {
            std.debug.print("[wren] onBoot call failed res={d}\n", .{@as(u32, @intCast(res))});
            if (self.last_error_len > 0) {
                std.debug.print("[wren] last error: {s}\n", .{self.last_error[0..self.last_error_len]});
            }
        }
        return res == wren_c.c.WREN_RESULT_SUCCESS;
    }

    pub fn callOnUpdate(self: *Self, dt: f32) bool {
        // Skip if boot failed or handles are missing.
        if (!self.boot_ok) return false;
        const vm = self.vm orelse return false;
        const game_class = self.game_class orelse return false;
        const on_update = self.on_update orelse return false;

        wren_c.c.wrenEnsureSlots(vm, 2);
        wren_c.c.wrenSetSlotHandle(vm, 0, game_class);
        wren_c.c.wrenSetSlotDouble(vm, 1, @floatCast(dt));
        self.last_error_len = 0;

        const res = wren_c.c.wrenCall(vm, on_update);
        if (res != wren_c.c.WREN_RESULT_SUCCESS) {
            std.debug.print("[wren] onUpdate call failed res={d}\n", .{@as(u32, @intCast(res))});
            if (self.last_error_len > 0) {
                std.debug.print("[wren] last error: {s}\n", .{self.last_error[0..self.last_error_len]});
            }
            // Stop further calls if we get an error.
            self.boot_ok = false;
        }
        return res == wren_c.c.WREN_RESULT_SUCCESS;
    }

    pub fn reloadIfChanged(self: *Self) void {
        if (builtin.os.tag == .emscripten) return;

        if (!self.checkAndUpdateMtime()) return;

        self.destroyVm();
        self.createVm() catch {};
    }

    fn checkAndUpdateMtime(self: *Self) bool {
        if (builtin.os.tag == .emscripten) return false;

        // We only do auto-reload in dev with a conventional asset path.
        // Module name is like "main" and maps to "assets/scripts/main.wren".
        var buf: [1024]u8 = undefined;
        const watch_path = std.fmt.bufPrint(&buf, "assets/scripts/{s}.wren", .{self.entry_module}) catch return false;

        const stat = std.fs.cwd().statFile(watch_path) catch return false;
        const mtime = stat.mtime;

        if (self.last_mtime_ns) |prev| {
            if (mtime <= prev) return false;
        }
        self.last_mtime_ns = mtime;
        return true;
    }

    fn writeFn(vm: ?*wren_c.c.WrenVM, text: [*c]const u8) callconv(.c) void {
        _ = vm;
        if (text == null) return;
        std.debug.print("[wren] {s}", .{std.mem.span(text)});
    }

    fn errorFn(
        vm: ?*wren_c.c.WrenVM,
        typ: wren_c.c.WrenErrorType,
        module: [*c]const u8,
        line: c_int,
        message: [*c]const u8,
    ) callconv(.c) void {
        if (vm == null or message == null) return;

        const t: []const u8 = switch (typ) {
            wren_c.c.WREN_ERROR_COMPILE => "compile",
            wren_c.c.WREN_ERROR_RUNTIME => "runtime",
            wren_c.c.WREN_ERROR_STACK_TRACE => "trace",
            else => "unknown",
        };

        const ud = wren_c.c.wrenGetUserData(vm.?) orelse return;
        const rt: *Self = @ptrCast(@alignCast(ud));

        const msg = std.mem.span(message);
        const n = @min(msg.len, rt.last_error.len - 1);
        @memcpy(rt.last_error[0..n], msg[0..n]);
        rt.last_error[n] = 0;
        rt.last_error_len = n;

        const mod_name: []const u8 = if (module) |m| std.mem.span(m) else "<none>";
        std.debug.print("[wren:{s}] {s}:{d}: {s}\\n", .{ t, mod_name, line, msg });
    }

    fn loadModuleTrampoline(vm: ?*wren_c.c.WrenVM, name: [*c]const u8) callconv(.c) wren_c.c.WrenLoadModuleResult {
        const ud = wren_c.c.wrenGetUserData(vm.?) orelse return .{ .source = null, .onComplete = null, .userData = null };
        const rt: *Self = @ptrCast(@alignCast(ud));
        return rt.loader.loadModule(vm, @ptrCast(name));
    }
};
