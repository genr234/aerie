const std = @import("std");

const dialogue = @import("../dialogue.zig");
const events = @import("../events.zig");
const story = @import("../story.zig");

const context = @import("context.zig");
const runtime_mod = @import("runtime.zig");
const wren_c = @import("wren_c.zig");

pub const Functions = enum {
    showMessage,
    setFlag,
    getFlag,
    changeSceneByIndex,
    changeSceneByName,
    startDialogue,
    startDialogueAt,
};

pub const Api = struct {
    pub fn bind(vm: *wren_c.c.WrenVM) void {
        _ = vm;
    }

    pub fn foreignClass(
        vm: ?*wren_c.c.WrenVM,
        module: [*c]const u8,
        class_name: [*c]const u8,
    ) callconv(.c) wren_c.c.WrenForeignClassMethods {
        _ = vm;
        _ = module;
        _ = class_name;

        // All foreign classes we expose are only used for static methods, so they
        // should never be instantiated.
        return .{ .allocate = null, .finalize = null };
    }

    pub fn foreignMethod(
        vm: ?*wren_c.c.WrenVM,
        module: [*c]const u8,
        class_name: [*c]const u8,
        is_static: bool,
        signature: [*c]const u8,
    ) callconv(.c) wren_c.c.WrenForeignMethodFn {
        _ = vm;
        _ = module;
        if (class_name == null or signature == null) return null;

        const klass = std.mem.span(class_name);
        const sig = std.mem.span(signature);

        const call = std.meta.stringToEnum(Functions, sig);

        if (is_static and std.mem.eql(u8, klass, "Engine")) {
            if (call) |valid_call| {
                switch (valid_call) {
                    .showMessage => return &events_showMessage,
                    .setFlag => return &story_setFlag,
                    .getFlag => return &story_getFlag,
                    .changeSceneByIndex => return &scene_change,
                    .changeSceneByName => return &scene_changeByName,
                    .startDialogue => return &dialogue_start,
                    .startDialogueAt => return &dialogue_startAt,
                }
            } else {
                return null;
            }
        }

        return null;
    }

    fn getCtx(vm: *wren_c.c.WrenVM) *context.ScriptingContext {
        // userData stores `*Runtime`; ctx lives on that struct.
        const rt = wren_c.c.wrenGetUserData(vm) orelse unreachable;
        const runtime: *const runtime_mod.Runtime = @ptrCast(@alignCast(rt));
        return runtime.ctx;
    }

    fn getSlotString(vm: *wren_c.c.WrenVM, slot: c_int, buf: []u8) []const u8 {
        const z = wren_c.c.wrenGetSlotString(vm, slot);
        const s = std.mem.span(z);
        const n = @min(s.len, buf.len);
        @memcpy(buf[0..n], s[0..n]);
        return buf[0..n];
    }

    fn events_showMessage(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var text_buf: [events.MAX_MESSAGE_LEN]u8 = undefined;
        const text = getSlotString(vm, 1, &text_buf);
        const duration = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));

        std.debug.print("[wren->zig] showMessage '{s}' ({d:.2}s)\n", .{ text, duration });

        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.showMessage(text, duration)) catch |err| {
            std.debug.print("[wren->zig] eventQueue.push failed: {any}\n", .{err});
        };
    }

    fn story_setFlag(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        const value = wren_c.c.wrenGetSlotBool(vm, 2);

        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.setFlag(name, value)) catch {};
    }

    fn story_getFlag(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);

        const ctx = getCtx(vm);
        const value = ctx.storyState.getFlag(name);
        wren_c.c.wrenSetSlotBool(vm, 0, value);
    }

    fn scene_change(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const idx = @as(usize, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 1)));
        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.changeSceneByIndex(idx)) catch {};
    }

    fn scene_changeByName(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.changeSceneByName(name)) catch {};
    }

    fn dialogue_start(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var ctx = getCtx(vm);
        const runner: *dialogue.Runner = ctx.activeDialogue();
        ctx.eventQueue.push(events.startDialogue(runner, ctx.storyState)) catch {};
    }

    fn dialogue_startAt(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var label_buf: [events.MAX_ID_LEN]u8 = undefined;
        const label = getSlotString(vm, 1, &label_buf);

        var ctx = getCtx(vm);
        const runner: *dialogue.Runner = ctx.activeDialogue();
        ctx.eventQueue.push(events.startDialogueAt(runner, ctx.storyState, label)) catch {};
    }
};
