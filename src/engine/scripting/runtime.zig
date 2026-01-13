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

    game_class: ?*wren_c.c.WrenHandle = null,
    on_boot: ?*wren_c.c.WrenHandle = null,
    on_update: ?*wren_c.c.WrenHandle = null,

    // desktop auto-reload.
    last_mtime_ns: ?i128 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, ctx: *context.ScriptingContext) !Self {
        const loader = loader_mod.Loader.init(allocator);
        var self: Self = .{
            .allocator = allocator,
            .loader = loader,
            .ctx = ctx,
        };
        try self.createVm();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.destroyVm();
        self.loader.deinit();
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

        // store ScriptingContext in user data so foreign methods can access engine state.
        config.userData = self.ctx;

        self.vm = wren_c.c.wrenNewVM(&config);

        try self.loadAndBindGame();
    }

    fn loadAndBindGame(self: *Self) !void {
        const vm = self.vm.?;

        // load root module; its imports will resolve via loadModuleFn.
        const res = wren_c.c.wrenInterpret(vm, "game", "import \"game\" for Game\n");
        if (res != wren_c.c.WREN_RESULT_SUCCESS) return error.WrenLoadFailed;

        wren_c.c.wrenEnsureSlots(vm, 2);
        wren_c.c.wrenGetVariable(vm, "game", "Game", 0);
        self.game_class = wren_c.c.wrenGetSlotHandle(vm, 0);

        wren_c.c.wrenSetSlotHandle(vm, 0, self.game_class.?);
        self.on_boot = wren_c.c.wrenMakeCallHandle(vm, "onBoot()");
        self.on_update = wren_c.c.wrenMakeCallHandle(vm, "onUpdate(_)");

        // call once on init.
        _ = self.callOnBoot();

        // seed mtime for auto reload.
        _ = self.checkAndUpdateMtime();
    }

    pub fn callOnBoot(self: *Self) bool {
        const vm = self.vm orelse return false;
        wren_c.c.wrenEnsureSlots(vm, 1);
        wren_c.c.wrenSetSlotHandle(vm, 0, self.game_class.?);
        const res = wren_c.c.wrenCall(vm, self.on_boot.?);
        return res == wren_c.c.WREN_RESULT_SUCCESS;
    }

    pub fn callOnUpdate(self: *Self, dt: f32) bool {
        const vm = self.vm orelse return false;
        wren_c.c.wrenEnsureSlots(vm, 2);
        wren_c.c.wrenSetSlotHandle(vm, 0, self.game_class.?);
        wren_c.c.wrenSetSlotDouble(vm, 1, @floatCast(dt));
        const res = wren_c.c.wrenCall(vm, self.on_update.?);
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

        const stat = std.fs.cwd().statFile("assets/scripts/game.wren") catch return false;
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
        _ = vm;
        const t: []const u8 = switch (typ) {
            wren_c.c.WREN_ERROR_COMPILE => "compile",
            wren_c.c.WREN_ERROR_RUNTIME => "runtime",
            wren_c.c.WREN_ERROR_STACK_TRACE => "trace",
            else => "unknown",
        };
        if (module == null or message == null) return;
        std.debug.print("[wren:{s}] {s}:{d}: {s}\n", .{ t, std.mem.span(module), line, std.mem.span(message) });
    }

    fn loadModuleTrampoline(vm: ?*wren_c.c.WrenVM, name: [*c]const u8) callconv(.c) wren_c.c.WrenLoadModuleResult {
        // wren passes us the VM, so we can retrieve runtime data from userData.
        const raw_ctx = wren_c.c.wrenGetUserData(vm.?);
        _ = raw_ctx;

        // we can't reach `self` directly from C callback without a separate pointer.
        // for now: rely on Loader allocating with the same allocator but avoid freeing.
        // this keeps V1 working and we can tighten memory management later.
        var tmp_loader = loader_mod.Loader.init(std.heap.c_allocator);
        return tmp_loader.loadModule(vm, @ptrCast(name));
    }
};
