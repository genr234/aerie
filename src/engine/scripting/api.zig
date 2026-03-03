const std = @import("std");

const dialogue = @import("../dialogue.zig");
const events = @import("../events.zig");
const story = @import("../story.zig");
const ui = @import("../ui.zig");

const context = @import("context.zig");
const runtime_mod = @import("runtime.zig");
const wren_c = @import("wren_c.zig");

pub const Api = struct {
    const engine_map = std.StaticStringMap(wren_c.c.WrenForeignMethodFn).initComptime(.{
        .{ "showMessage(_,_)", &events_showMessage },
        .{ "playSound(_,_,_)", &events_playSound },
        .{ "pause(_)", &events_pause },
        .{ "quit", &events_quit },
        .{ "quit()", &events_quit },
        .{ "setFlag(_,_)", &story_setFlag },
        .{ "getFlag(_)", &story_getFlag },
        .{ "toggleFlag(_)", &story_toggleFlag },
        .{ "hasFlag(_)", &story_hasFlag },
        .{ "setInt(_,_)", &story_setInt },
        .{ "getInt(_)", &story_getInt },
        .{ "addInt(_,_)", &story_addInt },
        .{ "setFloat(_,_)", &story_setFloat },
        .{ "getFloat(_)", &story_getFloat },
        .{ "setString(_,_)", &story_setString },
        .{ "getString(_)", &story_getString },
        .{ "setRelationship(_,_)", &story_setRelationship },
        .{ "getRelationship(_)", &story_getRelationship },
        .{ "modifyRelationship(_,_)", &story_modifyRelationship },
        .{ "setChapter(_)", &story_setChapter },
        .{ "getChapter", &story_getChapter },
        .{ "getChapter()", &story_getChapter },
        .{ "setRoute(_)", &story_setRoute },
        .{ "getRoute", &story_getRoute },
        .{ "getRoute()", &story_getRoute },
        .{ "getPlayTimeMinutes", &story_getPlayTimeMinutes },
        .{ "getPlayTimeMinutes()", &story_getPlayTimeMinutes },
        .{ "change(_)", &scene_change },
        .{ "changeByName(_)", &scene_changeByName },
        .{ "currentIndex", &scene_currentIndex },
        .{ "currentIndex()", &scene_currentIndex },
        .{ "findIndex(_)", &scene_findIndex },
        .{ "sceneCount", &scene_count },
        .{ "sceneCount()", &scene_count },
        .{ "start", &dialogue_start },
        .{ "start()", &dialogue_start },
        .{ "startAt(_)", &dialogue_startAt },
        .{ "stopDialogue", &dialogue_stop },
        .{ "stopDialogue()", &dialogue_stop },
        .{ "dialogueIsActive", &dialogue_isActive },
        .{ "dialogueIsActive()", &dialogue_isActive },
        .{ "dialogueSkip", &dialogue_skip },
        .{ "dialogueSkip()", &dialogue_skip },
        .{ "dialogueAdvance", &dialogue_advance },
        .{ "dialogueAdvance()", &dialogue_advance },
        .{ "entityExists(_)", &entity_exists },
        .{ "entitySetActive(_,_)", &entity_setActive },
        .{ "entityGetPosition(_)", &entity_getPosition },
        .{ "entitySetPosition(_,_,_)", &entity_setPosition },
        .{ "onKeyPressed(_,_)", &input_onKeyPressed },
        .{ "onKeyReleased(_,_)", &input_onKeyReleased },
        .{ "onAnyKey(_)", &input_onAnyKey },
        .{ "onMousePressed(_,_)", &input_onMousePressed },
        .{ "onMouseMove(_)", &input_onMouseMove },
        .{ "onTick(_)", &input_onTick },
    });

    const ui_map = std.StaticStringMap(wren_c.c.WrenForeignMethodFn).initComptime(.{
        .{ "button(_,_,_,_,_)", &ui_button },
        .{ "text(_,_,_)", &ui_text },
        .{ "panel(_,_,_,_)", &ui_panel },
        .{ "bar(_,_,_,_,_,_)", &ui_bar },
        .{ "inputField(_,_,_,_,_)", &ui_inputField },
        .{ "getInputText", &ui_getInputText },
        .{ "getInputText()", &ui_getInputText },
        .{ "setInputText(_)", &ui_setInputText },
        .{ "clearInput", &ui_clearInput },
        .{ "clearInput()", &ui_clearInput },
    });

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
            return @This().engine_map.get(sig) orelse null;
        }

        if (is_static and std.mem.eql(u8, klass, "UI")) {
            return @This().ui_map.get(sig) orelse null;
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

    fn ui_button(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 1)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const w = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const h = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 4)));
        const label = std.mem.span(wren_c.c.wrenGetSlotString(vm, 5));

        const clicked = ui.UI.button(x, y, w, h, label);
        wren_c.c.wrenSetSlotBool(vm, 0, clicked);
    }

    fn ui_text(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 1)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const content = std.mem.span(wren_c.c.wrenGetSlotString(vm, 3));

        ui.UI.text(x, y, content);
    }

    fn ui_panel(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 1)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const w = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const h = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 4)));

        ui.UI.panel(x, y, w, h);
    }

    fn ui_bar(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 1)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const w = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const h = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 4)));
        const value = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 5)));
        const max_value = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 6)));

        ui.UI.bar(x, y, w, h, value, max_value);
    }

    fn ui_inputField(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 1)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const w = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const h = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 4)));
        const field_id = @as(u32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 5)));

        const submitted = ui.UI.inputField(x, y, w, h, field_id);
        wren_c.c.wrenSetSlotBool(vm, 0, submitted);
    }

    fn ui_getInputText(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const text = ui.UI.getInputText();
        wren_c.c.wrenSetSlotBytes(vm, 0, text.ptr, text.len);
    }

    fn ui_setInputText(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const text = std.mem.span(wren_c.c.wrenGetSlotString(vm, 1));
        ui.UI.setInputText(text);
    }

    fn ui_clearInput(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        _ = vm;
        ui.UI.clearInput();
    }
};
