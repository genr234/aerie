const std = @import("std");

const dialogue = @import("../dialogue.zig");
const events = @import("../events.zig");
const story = @import("../story.zig");

const context = @import("context.zig");
const runtime_mod = @import("runtime.zig");
const wren_c = @import("wren_c.zig");

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

        if (is_static and std.mem.eql(u8, klass, "Engine")) {
            if (std.mem.eql(u8, sig, "showMessage(_,_)")) return &events_showMessage;
            if (std.mem.eql(u8, sig, "playSound(_,_,_)")) return &events_playSound;
            if (std.mem.eql(u8, sig, "pause(_)")) return &events_pause;
            if (std.mem.eql(u8, sig, "quit()") or std.mem.eql(u8, sig, "quit")) return &events_quit;

            if (std.mem.eql(u8, sig, "setFlag(_,_)")) return &story_setFlag;
            if (std.mem.eql(u8, sig, "getFlag(_)")) return &story_getFlag;
            if (std.mem.eql(u8, sig, "toggleFlag(_)")) return &story_toggleFlag;
            if (std.mem.eql(u8, sig, "hasFlag(_)")) return &story_hasFlag;

            if (std.mem.eql(u8, sig, "setInt(_,_)")) return &story_setInt;
            if (std.mem.eql(u8, sig, "getInt(_)")) return &story_getInt;
            if (std.mem.eql(u8, sig, "addInt(_,_)")) return &story_addInt;

            if (std.mem.eql(u8, sig, "setFloat(_,_)")) return &story_setFloat;
            if (std.mem.eql(u8, sig, "getFloat(_)")) return &story_getFloat;

            if (std.mem.eql(u8, sig, "setString(_,_)")) return &story_setString;
            if (std.mem.eql(u8, sig, "getString(_)")) return &story_getString;

            if (std.mem.eql(u8, sig, "setRelationship(_,_)")) return &story_setRelationship;
            if (std.mem.eql(u8, sig, "getRelationship(_)")) return &story_getRelationship;
            if (std.mem.eql(u8, sig, "modifyRelationship(_,_)")) return &story_modifyRelationship;

            if (std.mem.eql(u8, sig, "setChapter(_)")) return &story_setChapter;
            if (std.mem.eql(u8, sig, "getChapter()") or std.mem.eql(u8, sig, "getChapter")) return &story_getChapter;
            if (std.mem.eql(u8, sig, "setRoute(_)")) return &story_setRoute;
            if (std.mem.eql(u8, sig, "getRoute()") or std.mem.eql(u8, sig, "getRoute")) return &story_getRoute;
            if (std.mem.eql(u8, sig, "getPlayTimeMinutes()") or std.mem.eql(u8, sig, "getPlayTimeMinutes")) return &story_getPlayTimeMinutes;

            if (std.mem.eql(u8, sig, "change(_)")) return &scene_change;
            if (std.mem.eql(u8, sig, "changeByName(_)")) return &scene_changeByName;
            if (std.mem.eql(u8, sig, "currentIndex()") or std.mem.eql(u8, sig, "currentIndex")) return &scene_currentIndex;
            if (std.mem.eql(u8, sig, "findIndex(_)")) return &scene_findIndex;
            if (std.mem.eql(u8, sig, "sceneCount()") or std.mem.eql(u8, sig, "sceneCount")) return &scene_count;

            if (std.mem.eql(u8, sig, "start()") or std.mem.eql(u8, sig, "start")) return &dialogue_start;
            if (std.mem.eql(u8, sig, "startAt(_)")) return &dialogue_startAt;
            if (std.mem.eql(u8, sig, "stopDialogue()") or std.mem.eql(u8, sig, "stopDialogue")) return &dialogue_stop;
            if (std.mem.eql(u8, sig, "dialogueIsActive()") or std.mem.eql(u8, sig, "dialogueIsActive")) return &dialogue_isActive;
            if (std.mem.eql(u8, sig, "dialogueSkip()") or std.mem.eql(u8, sig, "dialogueSkip")) return &dialogue_skip;
            if (std.mem.eql(u8, sig, "dialogueAdvance()") or std.mem.eql(u8, sig, "dialogueAdvance")) return &dialogue_advance;

            if (std.mem.eql(u8, sig, "entityExists(_)")) return &entity_exists;
            if (std.mem.eql(u8, sig, "entitySetActive(_,_)")) return &entity_setActive;
            if (std.mem.eql(u8, sig, "entityGetPosition(_)")) return &entity_getPosition;
            if (std.mem.eql(u8, sig, "entitySetPosition(_,_,_)")) return &entity_setPosition;

            if (std.mem.eql(u8, sig, "onKeyPressed(_,_)")) return &input_onKeyPressed;
            if (std.mem.eql(u8, sig, "onKeyReleased(_,_)")) return &input_onKeyReleased;
            if (std.mem.eql(u8, sig, "onAnyKey(_)")) return &input_onAnyKey;
            if (std.mem.eql(u8, sig, "onMousePressed(_,_)")) return &input_onMousePressed;
            if (std.mem.eql(u8, sig, "onMouseMove(_)")) return &input_onMouseMove;
            if (std.mem.eql(u8, sig, "onTick(_)")) return &input_onTick;
            return null;
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

    fn events_playSound(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var id_buf: [events.MAX_ID_LEN]u8 = undefined;
        const sound_id = getSlotString(vm, 1, &id_buf);
        const volume = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const loop = wren_c.c.wrenGetSlotBool(vm, 3);

        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.playSound(sound_id, volume, loop)) catch {};
    }

    fn events_pause(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const paused = wren_c.c.wrenGetSlotBool(vm, 1);

        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.pauseGame(paused)) catch {};
    }

    fn events_quit(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.quitGame()) catch {};
    }

    fn story_setFlag(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        const value = wren_c.c.wrenGetSlotBool(vm, 2);

        var ctx = getCtx(vm);
        ctx.storyState.setFlag(name, value);
    }

    fn story_getFlag(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);

        const ctx = getCtx(vm);
        const value = ctx.storyState.getFlag(name);
        wren_c.c.wrenSetSlotBool(vm, 0, value);
    }

    fn story_toggleFlag(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);

        var ctx = getCtx(vm);
        ctx.storyState.toggleFlag(name);
    }

    fn story_hasFlag(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);

        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotBool(vm, 0, ctx.storyState.hasFlag(name));
    }

    fn story_setInt(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        const value = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2)));

        var ctx = getCtx(vm);
        ctx.storyState.setInt(name, value);
    }

    fn story_getInt(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);

        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(ctx.storyState.getInt(name)));
    }

    fn story_addInt(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        const delta = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2)));

        var ctx = getCtx(vm);
        ctx.storyState.addInt(name, delta);
    }

    fn story_setFloat(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        const value = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));

        var ctx = getCtx(vm);
        ctx.storyState.setFloat(name, value);
    }

    fn story_getFloat(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);

        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotDouble(vm, 0, @floatCast(ctx.storyState.getFloat(name)));
    }

    fn story_setString(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        var value_buf: [story.MAX_STRING_VAR_LEN]u8 = undefined;
        const value = getSlotString(vm, 2, &value_buf);

        var ctx = getCtx(vm);
        ctx.storyState.setString(name, value);
    }

    fn story_getString(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);

        const ctx = getCtx(vm);
        const value = ctx.storyState.getString(name);
        wren_c.c.wrenSetSlotBytes(vm, 0, value.ptr, value.len);
    }

    fn story_setRelationship(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        const value = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2)));

        var ctx = getCtx(vm);
        ctx.storyState.setRelationship(name, value);
    }

    fn story_getRelationship(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);

        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(ctx.storyState.getRelationship(name)));
    }

    fn story_modifyRelationship(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        const delta = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2)));

        var ctx = getCtx(vm);
        ctx.storyState.modifyRelationship(name, delta);
    }

    fn story_setChapter(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const chapter = @as(usize, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 1)));

        var ctx = getCtx(vm);
        ctx.storyState.setChapter(chapter);
    }

    fn story_getChapter(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(ctx.storyState.getChapter()));
    }

    fn story_setRoute(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var route_buf: [events.MAX_ID_LEN]u8 = undefined;
        const route = getSlotString(vm, 1, &route_buf);

        var ctx = getCtx(vm);
        ctx.storyState.setRoute(route);
    }

    fn story_getRoute(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const ctx = getCtx(vm);
        const route = ctx.storyState.getRoute();
        wren_c.c.wrenSetSlotBytes(vm, 0, route.ptr, route.len);
    }

    fn story_getPlayTimeMinutes(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotDouble(vm, 0, ctx.storyState.getPlayTimeMinutes());
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

    fn scene_currentIndex(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(ctx.sceneManager.currentIndex));
    }

    fn scene_findIndex(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var name_buf: [events.MAX_ID_LEN]u8 = undefined;
        const name = getSlotString(vm, 1, &name_buf);
        const ctx = getCtx(vm);
        if (ctx.sceneManager.findSceneByName(name)) |idx| {
            wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(idx));
        } else {
            wren_c.c.wrenSetSlotNull(vm, 0);
        }
    }

    fn scene_count(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(ctx.sceneManager.capacity));
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

    fn dialogue_stop(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var ctx = getCtx(vm);
        ctx.activeDialogue().stop();
    }

    fn dialogue_isActive(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotBool(vm, 0, ctx.activeDialogue().isActive());
    }

    fn dialogue_skip(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var ctx = getCtx(vm);
        ctx.activeDialogue().skip();
    }

    fn dialogue_advance(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var ctx = getCtx(vm);
        ctx.activeDialogue().advance();
    }

    fn entity_exists(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        wren_c.c.wrenSetSlotBool(vm, 0, scene.world.findByTag(tag) != null);
    }

    fn entity_setActive(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const active = wren_c.c.wrenGetSlotBool(vm, 2);
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        if (scene.world.findByTag(tag)) |entity| {
            scene.world.setActive(entity, active);
        }
    }

    fn entity_getPosition(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        if (scene.world.findByTag(tag)) |entity| {
            if (scene.world.transforms.get(entity)) |tr| {
                wren_c.c.wrenSetSlotNewList(vm, 0);
                wren_c.c.wrenSetSlotDouble(vm, 1, @floatCast(tr.position.x));
                wren_c.c.wrenInsertInList(vm, 0, 0, 1);
                wren_c.c.wrenSetSlotDouble(vm, 1, @floatCast(tr.position.y));
                wren_c.c.wrenInsertInList(vm, 0, 1, 1);
                return;
            }
        }
        wren_c.c.wrenSetSlotNull(vm, 0);
    }

    fn entity_setPosition(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        if (scene.world.findByTag(tag)) |entity| {
            if (scene.world.transforms.get(entity)) |tr| {
                tr.position.x = x;
                tr.position.y = y;
                wren_c.c.wrenSetSlotBool(vm, 0, true);
                return;
            }
        }
        wren_c.c.wrenSetSlotBool(vm, 0, false);
    }

    fn input_onKeyPressed(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const rt = wren_c.c.wrenGetUserData(vm) orelse return;
        const runtime: *runtime_mod.Runtime = @ptrCast(@alignCast(rt));
        switch (wren_c.c.wrenGetSlotType(vm, 1)) {
            wren_c.c.WREN_TYPE_NUM => {
                const key = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 1)));
                runtime.registerKeyPressed(key, vm, 2);
            },
            wren_c.c.WREN_TYPE_STRING => {
                const key_name = std.mem.span(wren_c.c.wrenGetSlotString(vm, 1));
                runtime.registerKeyPressedFromString(key_name, vm, 2);
            },
            else => {},
        }
    }

    fn input_onKeyReleased(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const rt = wren_c.c.wrenGetUserData(vm) orelse return;
        const runtime: *runtime_mod.Runtime = @ptrCast(@alignCast(rt));
        switch (wren_c.c.wrenGetSlotType(vm, 1)) {
            wren_c.c.WREN_TYPE_NUM => {
                const key = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 1)));
                runtime.registerKeyReleased(key, vm, 2);
            },
            wren_c.c.WREN_TYPE_STRING => {
                const key_name = std.mem.span(wren_c.c.wrenGetSlotString(vm, 1));
                runtime.registerKeyReleasedFromString(key_name, vm, 2);
            },
            else => {},
        }
    }

    fn input_onAnyKey(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const rt = wren_c.c.wrenGetUserData(vm) orelse return;
        const runtime: *runtime_mod.Runtime = @ptrCast(@alignCast(rt));
        runtime.registerAnyKey(vm, 1);
    }

    fn input_onMousePressed(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const button = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 1)));
        const rt = wren_c.c.wrenGetUserData(vm) orelse return;
        const runtime: *runtime_mod.Runtime = @ptrCast(@alignCast(rt));
        runtime.registerMousePressed(button, vm, 2);
    }

    fn input_onMouseMove(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const rt = wren_c.c.wrenGetUserData(vm) orelse return;
        const runtime: *runtime_mod.Runtime = @ptrCast(@alignCast(rt));
        runtime.registerMouseMove(vm, 1);
    }

    fn input_onTick(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const rt = wren_c.c.wrenGetUserData(vm) orelse return;
        const runtime: *runtime_mod.Runtime = @ptrCast(@alignCast(rt));
        runtime.registerTick(vm, 1);
    }
};
