const std = @import("std");

const dialogue = @import("../dialogue.zig");
const events = @import("../events.zig");
const story = @import("../story.zig");

const context = @import("context.zig");
const wren_c = @import("wren_c.zig");

pub const Api = struct {
    pub fn bind(vm: *wren_c.c.WrenVM) void {
        _ = vm;
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

        if (is_static and std.mem.eql(u8, klass, "Events") and std.mem.eql(u8, sig, "showMessage(_,_)")) {
            return &events_showMessage;
        }

        if (is_static and std.mem.eql(u8, klass, "Story") and std.mem.eql(u8, sig, "setFlag(_,_)")) {
            return &story_setFlag;
        }

        if (is_static and std.mem.eql(u8, klass, "Story") and std.mem.eql(u8, sig, "getFlag(_)")) {
            return &story_getFlag;
        }

        if (is_static and std.mem.eql(u8, klass, "Scene") and std.mem.eql(u8, sig, "change(_)")) {
            return &scene_change;
        }

        if (is_static and std.mem.eql(u8, klass, "Scene") and std.mem.eql(u8, sig, "changeByName(_)")) {
            return &scene_changeByName;
        }

        if (is_static and std.mem.eql(u8, klass, "Dialogue") and std.mem.eql(u8, sig, "start()")) {
            return &dialogue_start;
        }

        if (is_static and std.mem.eql(u8, klass, "Dialogue") and std.mem.eql(u8, sig, "startAt(_)")) {
            return &dialogue_startAt;
        }

        return null;
    }

    fn getCtx(vm: *wren_c.c.WrenVM) *context.ScriptingContext {
        const ud = wren_c.c.wrenGetUserData(vm);
        return @ptrCast(@alignCast(ud));
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

        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.showMessage(text, duration)) catch {};
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
