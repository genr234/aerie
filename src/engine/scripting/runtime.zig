const std = @import("std");
const builtin = @import("builtin");

const wren_c = @import("wren_c.zig");
const loader_mod = @import("loader.zig");
const api = @import("api.zig");
const context = @import("context.zig");
const assets = @import("../utils/assets.zig");
const rl = @import("raylib");

pub const Runtime = struct {
    const KeyHandler = struct {
        key: i32,
        callback: *wren_c.c.WrenHandle,
    };

    const MouseHandler = struct {
        button: i32,
        callback: *wren_c.c.WrenHandle,
    };

    const MaxKeyHandlers: usize = 32;
    const MaxAnyHandlers: usize = 16;
    const MaxMouseHandlers: usize = 16;
    const MaxMoveHandlers: usize = 8;
    const MaxTickHandlers: usize = 8;

    allocator: std.mem.Allocator,
    vm: ?*wren_c.c.WrenVM = null,

    loader: loader_mod.Loader,
    ctx: *context.ScriptingContext,

    project_root: []const u8,
    entry_module: [:0]const u8,
    entry_class: [:0]const u8,

    game_class: ?*wren_c.c.WrenHandle = null,
    on_boot: ?*wren_c.c.WrenHandle = null,
    on_update: ?*wren_c.c.WrenHandle = null,
    on_draw: ?*wren_c.c.WrenHandle = null,
    boot_ok: bool = false,

    call_0: ?*wren_c.c.WrenHandle = null,
    call_1: ?*wren_c.c.WrenHandle = null,
    call_2: ?*wren_c.c.WrenHandle = null,
    call_4: ?*wren_c.c.WrenHandle = null,

    key_pressed_handlers: [MaxKeyHandlers]KeyHandler = undefined,
    key_pressed_count: usize = 0,
    key_released_handlers: [MaxKeyHandlers]KeyHandler = undefined,
    key_released_count: usize = 0,
    any_key_handlers: [MaxAnyHandlers]*wren_c.c.WrenHandle = undefined,
    any_key_count: usize = 0,
    mouse_pressed_handlers: [MaxMouseHandlers]MouseHandler = undefined,
    mouse_pressed_count: usize = 0,
    mouse_move_handlers: [MaxMoveHandlers]*wren_c.c.WrenHandle = undefined,
    mouse_move_count: usize = 0,
    tick_handlers: [MaxTickHandlers]*wren_c.c.WrenHandle = undefined,
    tick_count: usize = 0,

    // desktop auto-reload.
    last_mtime_ns: ?i128 = null,

    // Captured by errorFn for easier debugging.
    last_error: [256]u8 = [_]u8{0} ** 256,
    last_error_len: usize = 0,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        ctx: *context.ScriptingContext,
        project_root: []const u8,
        entry_module: []const u8,
        entry_class: []const u8,
    ) !Self {
        const loader = loader_mod.Loader.init(allocator, project_root);
        var self: Self = .{
            .allocator = allocator,
            .loader = loader,
            .ctx = ctx,
            .project_root = project_root,
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
            if (self.call_0) |h| wren_c.c.wrenReleaseHandle(vm, h);
            if (self.call_1) |h| wren_c.c.wrenReleaseHandle(vm, h);
            if (self.call_2) |h| wren_c.c.wrenReleaseHandle(vm, h);
            if (self.call_4) |h| wren_c.c.wrenReleaseHandle(vm, h);
            for (self.key_pressed_handlers[0..self.key_pressed_count]) |handler| {
                wren_c.c.wrenReleaseHandle(vm, handler.callback);
            }
            for (self.key_released_handlers[0..self.key_released_count]) |handler| {
                wren_c.c.wrenReleaseHandle(vm, handler.callback);
            }
            for (self.any_key_handlers[0..self.any_key_count]) |handler| {
                wren_c.c.wrenReleaseHandle(vm, handler);
            }
            for (self.mouse_pressed_handlers[0..self.mouse_pressed_count]) |handler| {
                wren_c.c.wrenReleaseHandle(vm, handler.callback);
            }
            for (self.mouse_move_handlers[0..self.mouse_move_count]) |handler| {
                wren_c.c.wrenReleaseHandle(vm, handler);
            }
            for (self.tick_handlers[0..self.tick_count]) |handler| {
                wren_c.c.wrenReleaseHandle(vm, handler);
            }
            self.game_class = null;
            self.on_boot = null;
            self.on_update = null;
            self.on_draw = null;
            self.call_0 = null;
            self.call_1 = null;
            self.call_2 = null;
            self.call_4 = null;
            self.key_pressed_count = 0;
            self.key_released_count = 0;
            self.any_key_count = 0;
            self.mouse_pressed_count = 0;
            self.mouse_move_count = 0;
            self.tick_count = 0;

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

        self.call_0 = wren_c.c.wrenMakeCallHandle(self.vm.?, "call()");
        self.call_1 = wren_c.c.wrenMakeCallHandle(self.vm.?, "call(_)");
        self.call_2 = wren_c.c.wrenMakeCallHandle(self.vm.?, "call(_,_)");
        self.call_4 = wren_c.c.wrenMakeCallHandle(self.vm.?, "call(_,_,_,_)");

        self.key_pressed_count = 0;
        self.key_released_count = 0;
        self.any_key_count = 0;
        self.mouse_pressed_count = 0;
        self.mouse_move_count = 0;
        self.tick_count = 0;

        try self.loadAndBindGame();
    }

    fn loadAndBindGame(self: *Self) !void {
        const vm = self.vm.?;

        // Load and compile the entry module directly (no scratch import).
        // This follows Wren's embedding docs: interpret module source, then
        // look up variables from that same module.
        const module_name = self.entry_module;
        const rel_path = try std.fmt.allocPrint(self.allocator, "scripts/{s}.wren", .{module_name});
        defer self.allocator.free(rel_path);

        const asset_path = try assets.resolveAssetPath(self.allocator, self.project_root, rel_path, builtin.os.tag);
        defer self.allocator.free(asset_path);

        const file = std.fs.cwd().openFile(asset_path, .{}) catch |err| {
            std.debug.print("[wren] failed to open {s}: {any}\n", .{ asset_path, err });
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
        self.on_draw = wren_c.c.wrenMakeCallHandle(vm, "onDraw()");

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

    pub fn callOnDraw(self: *Self) bool {
        // Skip if boot failed or handles are missing.
        if (!self.boot_ok) return false;
        const vm = self.vm orelse return false;
        const game_class = self.game_class orelse return false;
        const on_draw = self.on_draw orelse return false;

        wren_c.c.wrenEnsureSlots(vm, 1);
        wren_c.c.wrenSetSlotHandle(vm, 0, game_class);
        self.last_error_len = 0;

        const res = wren_c.c.wrenCall(vm, on_draw);
        if (res != wren_c.c.WREN_RESULT_SUCCESS) {
            std.debug.print("[wren] onDraw call failed res={d}\n", .{@as(u32, @intCast(res))});
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
        const rel_path = std.fmt.bufPrint(&buf, "scripts/{s}.wren", .{self.entry_module}) catch return false;
        const watch_path = assets.resolveAssetPath(self.allocator, self.project_root, rel_path, builtin.os.tag) catch return false;
        defer self.allocator.free(watch_path);

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

    fn normalizeKeyString(name: []const u8) ?i32 {
        if (name.len == 1) {
            const ch = name[0];
            if (ch >= 'a' and ch <= 'z') return @intCast(ch - 'a' + 'A');
            if (ch >= 'A' and ch <= 'Z') return @intCast(ch);
            if (ch >= '0' and ch <= '9') return @intCast(ch);
        }
        if (std.ascii.eqlIgnoreCase(name, "space")) return @intFromEnum(rl.KeyboardKey.space);
        if (std.ascii.eqlIgnoreCase(name, "enter")) return @intFromEnum(rl.KeyboardKey.enter);
        if (std.ascii.eqlIgnoreCase(name, "escape")) return @intFromEnum(rl.KeyboardKey.escape);
        if (std.ascii.eqlIgnoreCase(name, "tab")) return @intFromEnum(rl.KeyboardKey.tab);
        if (std.ascii.eqlIgnoreCase(name, "backspace")) return @intFromEnum(rl.KeyboardKey.backspace);
        if (std.ascii.eqlIgnoreCase(name, "left")) return @intFromEnum(rl.KeyboardKey.left);
        if (std.ascii.eqlIgnoreCase(name, "right")) return @intFromEnum(rl.KeyboardKey.right);
        if (std.ascii.eqlIgnoreCase(name, "up")) return @intFromEnum(rl.KeyboardKey.up);
        if (std.ascii.eqlIgnoreCase(name, "down")) return @intFromEnum(rl.KeyboardKey.down);
        if (std.ascii.eqlIgnoreCase(name, "f1")) return @intFromEnum(rl.KeyboardKey.f1);
        if (std.ascii.eqlIgnoreCase(name, "f2")) return @intFromEnum(rl.KeyboardKey.f2);
        if (std.ascii.eqlIgnoreCase(name, "f3")) return @intFromEnum(rl.KeyboardKey.f3);
        if (std.ascii.eqlIgnoreCase(name, "f4")) return @intFromEnum(rl.KeyboardKey.f4);
        if (std.ascii.eqlIgnoreCase(name, "f5")) return @intFromEnum(rl.KeyboardKey.f5);
        if (std.ascii.eqlIgnoreCase(name, "f6")) return @intFromEnum(rl.KeyboardKey.f6);
        if (std.ascii.eqlIgnoreCase(name, "f7")) return @intFromEnum(rl.KeyboardKey.f7);
        if (std.ascii.eqlIgnoreCase(name, "f8")) return @intFromEnum(rl.KeyboardKey.f8);
        if (std.ascii.eqlIgnoreCase(name, "f9")) return @intFromEnum(rl.KeyboardKey.f9);
        if (std.ascii.eqlIgnoreCase(name, "f10")) return @intFromEnum(rl.KeyboardKey.f10);
        if (std.ascii.eqlIgnoreCase(name, "f11")) return @intFromEnum(rl.KeyboardKey.f11);
        if (std.ascii.eqlIgnoreCase(name, "f12")) return @intFromEnum(rl.KeyboardKey.f12);
        return null;
    }

    pub fn registerKeyPressed(self: *Self, key: i32, vm: *wren_c.c.WrenVM, slot: c_int) void {
        if (self.key_pressed_count >= MaxKeyHandlers) return;
        const handle = wren_c.c.wrenGetSlotHandle(vm, slot) orelse return;
        self.key_pressed_handlers[self.key_pressed_count] = .{ .key = key, .callback = handle };
        self.key_pressed_count += 1;
    }

    pub fn registerKeyPressedFromString(self: *Self, key_name: []const u8, vm: *wren_c.c.WrenVM, slot: c_int) void {
        const key = normalizeKeyString(key_name) orelse return;
        self.registerKeyPressed(key, vm, slot);
    }

    pub fn registerKeyReleased(self: *Self, key: i32, vm: *wren_c.c.WrenVM, slot: c_int) void {
        if (self.key_released_count >= MaxKeyHandlers) return;
        const handle = wren_c.c.wrenGetSlotHandle(vm, slot) orelse return;
        self.key_released_handlers[self.key_released_count] = .{ .key = key, .callback = handle };
        self.key_released_count += 1;
    }

    pub fn registerKeyReleasedFromString(self: *Self, key_name: []const u8, vm: *wren_c.c.WrenVM, slot: c_int) void {
        const key = normalizeKeyString(key_name) orelse return;
        self.registerKeyReleased(key, vm, slot);
    }

    pub fn registerAnyKey(self: *Self, vm: *wren_c.c.WrenVM, slot: c_int) void {
        if (self.any_key_count >= MaxAnyHandlers) return;
        const handle = wren_c.c.wrenGetSlotHandle(vm, slot) orelse return;
        self.any_key_handlers[self.any_key_count] = handle;
        self.any_key_count += 1;
    }

    pub fn registerMousePressed(self: *Self, button: i32, vm: *wren_c.c.WrenVM, slot: c_int) void {
        if (self.mouse_pressed_count >= MaxMouseHandlers) return;
        const handle = wren_c.c.wrenGetSlotHandle(vm, slot) orelse return;
        self.mouse_pressed_handlers[self.mouse_pressed_count] = .{ .button = button, .callback = handle };
        self.mouse_pressed_count += 1;
    }

    pub fn registerMouseMove(self: *Self, vm: *wren_c.c.WrenVM, slot: c_int) void {
        if (self.mouse_move_count >= MaxMoveHandlers) return;
        const handle = wren_c.c.wrenGetSlotHandle(vm, slot) orelse return;
        self.mouse_move_handlers[self.mouse_move_count] = handle;
        self.mouse_move_count += 1;
    }

    pub fn registerTick(self: *Self, vm: *wren_c.c.WrenVM, slot: c_int) void {
        if (self.tick_count >= MaxTickHandlers) return;
        const handle = wren_c.c.wrenGetSlotHandle(vm, slot) orelse return;
        self.tick_handlers[self.tick_count] = handle;
        self.tick_count += 1;
    }

    pub fn dispatchInput(self: *Self, dt: f32) void {
        const vm = self.vm orelse return;

        const tick_count = self.tick_count;
        for (self.tick_handlers[0..tick_count]) |handler| {
            wren_c.c.wrenEnsureSlots(vm, 2);
            wren_c.c.wrenSetSlotHandle(vm, 0, handler);
            wren_c.c.wrenSetSlotDouble(vm, 1, @floatCast(dt));
            _ = wren_c.c.wrenCall(vm, self.call_1.?);
        }

        var key = rl.getKeyPressed();
        while (key != .null) : (key = rl.getKeyPressed()) {
            const key_value: i32 = @intFromEnum(key);
            for (self.any_key_handlers[0..self.any_key_count]) |handler| {
                wren_c.c.wrenEnsureSlots(vm, 2);
                wren_c.c.wrenSetSlotHandle(vm, 0, handler);
                wren_c.c.wrenSetSlotDouble(vm, 1, @floatFromInt(key_value));
                _ = wren_c.c.wrenCall(vm, self.call_1.?);
            }
        }

        for (self.key_pressed_handlers[0..self.key_pressed_count]) |handler| {
            if (rl.isKeyPressed(@enumFromInt(handler.key))) {
                wren_c.c.wrenEnsureSlots(vm, 2);
                wren_c.c.wrenSetSlotHandle(vm, 0, handler.callback);
                wren_c.c.wrenSetSlotDouble(vm, 1, @floatFromInt(handler.key));
                _ = wren_c.c.wrenCall(vm, self.call_1.?);
            }
        }

        for (self.key_released_handlers[0..self.key_released_count]) |handler| {
            if (rl.isKeyReleased(@enumFromInt(handler.key))) {
                wren_c.c.wrenEnsureSlots(vm, 2);
                wren_c.c.wrenSetSlotHandle(vm, 0, handler.callback);
                wren_c.c.wrenSetSlotDouble(vm, 1, @floatFromInt(handler.key));
                _ = wren_c.c.wrenCall(vm, self.call_1.?);
            }
        }

        for (self.mouse_pressed_handlers[0..self.mouse_pressed_count]) |handler| {
            if (rl.isMouseButtonPressed(@enumFromInt(handler.button))) {
                wren_c.c.wrenEnsureSlots(vm, 2);
                wren_c.c.wrenSetSlotHandle(vm, 0, handler.callback);
                wren_c.c.wrenSetSlotDouble(vm, 1, @floatFromInt(handler.button));
                _ = wren_c.c.wrenCall(vm, self.call_1.?);
            }
        }

        if (self.mouse_move_count > 0) {
            const delta = rl.getMouseDelta();
            if (delta.x != 0 or delta.y != 0) {
                for (self.mouse_move_handlers[0..self.mouse_move_count]) |handler| {
                    wren_c.c.wrenEnsureSlots(vm, 3);
                    wren_c.c.wrenSetSlotHandle(vm, 0, handler);
                    wren_c.c.wrenSetSlotDouble(vm, 1, @floatCast(delta.x));
                    wren_c.c.wrenSetSlotDouble(vm, 2, @floatCast(delta.y));
                    _ = wren_c.c.wrenCall(vm, self.call_2.?);
                }
            }
        }
    }

    fn loadModuleTrampoline(vm: ?*wren_c.c.WrenVM, name: [*c]const u8) callconv(.c) wren_c.c.WrenLoadModuleResult {
        const ud = wren_c.c.wrenGetUserData(vm.?) orelse return .{ .source = null, .onComplete = null, .userData = null };
        const rt: *Self = @ptrCast(@alignCast(ud));
        return rt.loader.loadModule(vm, @ptrCast(name));
    }
};
