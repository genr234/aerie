const std = @import("std");

const log = @import("../log.zig");
const dialogue = @import("../dialogue.zig");
const events = @import("../events.zig");
const story = @import("../story.zig");
const ui = @import("../ui.zig");
const resources = @import("../resources.zig");
const ecs = @import("../ecs.zig");
const rl = @import("raylib");

const context = @import("context.zig");
const runtime_mod = @import("runtime.zig");
const wren_c = @import("wren_c.zig");

extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
const c_mkdir = mkdir;

pub const Api = struct {
    const engine_map = std.StaticStringMap(wren_c.c.WrenForeignMethodFn).initComptime(.{
        .{ "showMessage(_,_)", &events_showMessage },
        .{ "playSound(_,_,_)", &events_playSound },
        .{ "playMusic(_,_)", &events_playMusic },
        .{ "stopMusic(_)", &events_stopMusic },
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
        .{ "saveWrite(_)", &save_write },
        .{ "saveLoad(_)", &save_load },
        .{ "saveExists(_)", &save_exists },
        .{ "saveClear(_)", &save_clear },
        .{ "change(_)", &scene_change },
        .{ "changeByName(_)", &scene_changeByName },
        .{ "currentIndex", &scene_currentIndex },
        .{ "currentIndex()", &scene_currentIndex },
        .{ "findIndex(_)", &scene_findIndex },
        .{ "sceneCount", &scene_count },
        .{ "sceneCount()", &scene_count },
        .{ "start", &dialogue_start },
        .{ "start()", &dialogue_start },
        .{ "start(_)", &dialogue_start_id },
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
        .{ "entityMove(_,_,_)", &entity_move },
        .{ "entityDespawn(_)", &entity_despawn },
        .{ "entitySpawnRect(_,_,_,_,_,_)", &entity_spawnRect },
        .{ "entitySpawnCircle(_,_,_,_,_)", &entity_spawnCircle },
        .{ "entitySetAnimation(_,_)", &entity_setAnimation },
        .{ "entityTweenTo(_,_,_,_)", &entity_tweenTo },
        .{ "entityEmitParticles(_,_)", &entity_emitParticles },
        .{ "cameraShake(_,_)", &camera_shake },
        .{ "inventoryAdd(_,_)", &inventory_add },
        .{ "inventoryCount(_)", &inventory_count },
        .{ "inventoryHas(_,_)", &inventory_has },
        .{ "questStart(_)", &quest_start },
        .{ "questComplete(_)", &quest_complete },
        .{ "questIsActive(_)", &quest_isActive },
        .{ "questIsComplete(_)", &quest_isComplete },
        .{ "combatSetHp(_,_)", &combat_setHp },
        .{ "combatDamage(_,_)", &combat_damage },
        .{ "combatHeal(_,_)", &combat_heal },
        .{ "combatHp(_)", &combat_hp },
        .{ "combatStart(_)", &combat_start },
        .{ "combatIsActive", &combat_isActive },
        .{ "combatIsActive()", &combat_isActive },
        .{ "combatState", &combat_state },
        .{ "combatState()", &combat_state },
        .{ "combatActorHp(_)", &combat_hp },
        .{ "combatActorMp(_)", &combat_mp },
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

    pub fn writeSave(ctx: *context.ScriptingContext, slot: []const u8) bool {
        return writeSaveSlot(ctx, slot) catch |err| blk: {
            log.debug("[save] write '{s}' failed: {any}\n", .{ slot, err });
            break :blk false;
        };
    }

    pub fn loadSave(ctx: *context.ScriptingContext, slot: []const u8) bool {
        return loadSaveSlot(ctx, slot) catch |err| blk: {
            log.debug("[save] load '{s}' failed: {any}\n", .{ slot, err });
            break :blk false;
        };
    }

    pub fn saveExists(ctx: *context.ScriptingContext, slot: []const u8) bool {
        const path = saveSlotPath(ctx.projectRoot, slot) catch return false;
        defer std.heap.page_allocator.free(path);
        const io = std.Io.Threaded.global_single_threaded.io();
        return if (std.Io.Dir.cwd().access(io, path, .{})) true else |_| false;
    }

    pub fn clearSave(ctx: *context.ScriptingContext, slot: []const u8) bool {
        const path = saveSlotPath(ctx.projectRoot, slot) catch return false;
        defer std.heap.page_allocator.free(path);
        const io = std.Io.Threaded.global_single_threaded.io();
        std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => {
                log.debug("[save] clear '{s}' failed: {any}\n", .{ slot, err });
                return false;
            },
        };
        return true;
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

        log.debug("[wren->zig] showMessage '{s}' ({d:.2}s)\n", .{ text, duration });

        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.showMessage(text, duration)) catch |err| {
            log.debug("[wren->zig] eventQueue.push failed: {any}\n", .{err});
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

    fn events_playMusic(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var id_buf: [events.MAX_ID_LEN]u8 = undefined;
        const music_id = getSlotString(vm, 1, &id_buf);
        const fade = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));

        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.playMusic(music_id, fade)) catch {};
    }

    fn events_stopMusic(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const fade = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 1)));

        var ctx = getCtx(vm);
        ctx.eventQueue.push(events.stopMusic(fade)) catch {};
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

    fn save_write(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var slot_buf: [events.MAX_ID_LEN]u8 = undefined;
        const slot = getSlotString(vm, 1, &slot_buf);
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotBool(vm, 0, writeSave(ctx, slot));
    }

    fn save_load(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var slot_buf: [events.MAX_ID_LEN]u8 = undefined;
        const slot = getSlotString(vm, 1, &slot_buf);
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotBool(vm, 0, loadSave(ctx, slot));
    }

    fn save_exists(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var slot_buf: [events.MAX_ID_LEN]u8 = undefined;
        const slot = getSlotString(vm, 1, &slot_buf);
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotBool(vm, 0, saveExists(ctx, slot));
    }

    fn save_clear(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var slot_buf: [events.MAX_ID_LEN]u8 = undefined;
        const slot = getSlotString(vm, 1, &slot_buf);
        const ctx = getCtx(vm);
        wren_c.c.wrenSetSlotBool(vm, 0, clearSave(ctx, slot));
    }

    fn writeSaveSlot(ctx: *context.ScriptingContext, slot: []const u8) !bool {
        const allocator = std.heap.page_allocator;
        const path = try saveSlotPath(ctx.projectRoot, slot);
        defer allocator.free(path);

        const dir_path = try std.fs.path.join(allocator, &.{ ctx.projectRoot, "saves" });
        defer allocator.free(dir_path);
        try makeDirIfMissing(dir_path);

        const io = std.Io.Threaded.global_single_threaded.io();
        var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var writer = file.writer(io, &buffer);
        const w = &writer.interface;

        try w.writeAll("{\n  \"version\": 1,\n");
        try w.print("  \"scene\": \"{f}\",\n", .{std.json.fmt(ctx.sceneManager.currentScene().name, .{})});
        try w.print("  \"scene_index\": {d},\n", .{ctx.sceneManager.currentIndex});
        try w.print("  \"play_time\": {d},\n", .{ctx.storyState.playTime});
        try w.writeAll("  \"flags\": {\n");
        for (ctx.storyState.flags[0..ctx.storyState.flagCount], 0..) |flag, i| {
            try w.print("    \"{f}\": {}", .{ std.json.fmt(flag.getName(), .{}), flag.value });
            try w.writeAll(if (i + 1 < ctx.storyState.flagCount) ",\n" else "\n");
        }
        try w.writeAll("  },\n  \"vars\": {\n");
        for (ctx.storyState.vars[0..ctx.storyState.varCount], 0..) |variable, i| {
            try w.print("    \"{f}\": ", .{std.json.fmt(variable.getName(), .{})});
            switch (variable.value) {
                .int => |value| try w.print("{{\"type\":\"int\",\"value\":{d}}}", .{value}),
                .float => |value| try w.print("{{\"type\":\"float\",\"value\":{d}}}", .{value}),
                .string => |value| try w.print("{{\"type\":\"string\",\"value\":\"{f}\"}}", .{std.json.fmt(value.data[0..value.len], .{})}),
            }
            try w.writeAll(if (i + 1 < ctx.storyState.varCount) ",\n" else "\n");
        }
        try w.writeAll("  }\n}\n");
        try w.flush();
        return true;
    }

    fn loadSaveSlot(ctx: *context.ScriptingContext, slot: []const u8) !bool {
        const allocator = std.heap.page_allocator;
        const path = try saveSlotPath(ctx.projectRoot, slot);
        defer allocator.free(path);

        const bytes = resources.readFileAlloc(allocator, path) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer allocator.free(bytes);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
        defer parsed.deinit();
        const root = parsed.value.object;
        const version = jsonInt(root.get("version") orelse return false) orelse return false;
        if (version != 1) return false;

        ctx.storyState.reset();
        if (root.get("play_time")) |value| {
            ctx.storyState.playTime = jsonFloat(value) orelse 0.0;
        }

        if (root.get("flags")) |flags_value| {
            if (flags_value == .object) {
                var it = flags_value.object.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == .bool) {
                        ctx.storyState.setFlagInternal(entry.key_ptr.*, entry.value_ptr.bool);
                    }
                }
            }
        }

        if (root.get("vars")) |vars_value| {
            if (vars_value == .object) {
                var it = vars_value.object.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* != .object) continue;
                    const var_obj = entry.value_ptr.object;
                    const type_name = jsonString(var_obj.get("type") orelse continue) orelse continue;
                    const value = var_obj.get("value") orelse continue;
                    if (std.mem.eql(u8, type_name, "int")) {
                        if (jsonInt(value)) |n| ctx.storyState.setInt(entry.key_ptr.*, @intCast(n));
                    } else if (std.mem.eql(u8, type_name, "float")) {
                        if (jsonFloat(value)) |n| ctx.storyState.setFloat(entry.key_ptr.*, @floatCast(n));
                    } else if (std.mem.eql(u8, type_name, "string")) {
                        if (jsonString(value)) |text| ctx.storyState.setString(entry.key_ptr.*, text);
                    }
                }
            }
        }

        if (root.get("scene")) |scene_value| {
            if (jsonString(scene_value)) |scene_name| {
                ctx.sceneManager.changeSceneByName(scene_name) catch {};
            }
        } else if (root.get("scene_index")) |index_value| {
            if (jsonInt(index_value)) |scene_index| {
                if (scene_index >= 0) ctx.sceneManager.changeScene(@intCast(scene_index)) catch {};
            }
        }

        return true;
    }

    fn saveSlotPath(project_root: []const u8, slot: []const u8) ![]u8 {
        if (!isSafeSlot(slot)) return error.InvalidSaveSlot;
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}{c}saves{c}{s}.json", .{ project_root, std.fs.path.sep, std.fs.path.sep, slot });
    }

    fn makeDirIfMissing(path: []const u8) !void {
        const zpath = try std.heap.page_allocator.dupeZ(u8, path);
        defer std.heap.page_allocator.free(zpath);
        const result = c_mkdir(zpath.ptr, 0o755);
        if (result == 0) return;
        const io = std.Io.Threaded.global_single_threaded.io();
        std.Io.Dir.cwd().access(io, path, .{}) catch return error.MakeDirFailed;
    }

    fn isSafeSlot(slot: []const u8) bool {
        if (slot.len == 0 or slot.len > 32) return false;
        for (slot) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
        }
        return true;
    }

    fn jsonString(value: std.json.Value) ?[]const u8 {
        return switch (value) {
            .string => |s| s,
            else => null,
        };
    }

    fn jsonInt(value: std.json.Value) ?i64 {
        return switch (value) {
            .integer => |n| n,
            .float => |n| @intFromFloat(n),
            else => null,
        };
    }

    fn jsonFloat(value: std.json.Value) ?f64 {
        return switch (value) {
            .integer => |n| @floatFromInt(n),
            .float => |n| n,
            else => null,
        };
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

    fn dialogue_start_id(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var id_buf: [events.MAX_ID_LEN]u8 = undefined;
        const id = getSlotString(vm, 1, &id_buf);

        var ctx = getCtx(vm);
        const runner: *dialogue.Runner = ctx.activeDialogue();
        ctx.eventQueue.push(events.startDialogueById(runner, ctx.storyState, id, null)) catch {};
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

    fn entity_move(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const dx = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const dy = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        if (scene.world.findByTag(tag)) |entity| {
            if (scene.world.transforms.get(entity)) |tr| {
                tr.position.x += dx;
                tr.position.y += dy;
                wren_c.c.wrenSetSlotBool(vm, 0, true);
                return;
            }
        }
        wren_c.c.wrenSetSlotBool(vm, 0, false);
    }

    fn entity_despawn(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        if (scene.world.findByTag(tag)) |entity| {
            scene.world.despawn(entity);
            wren_c.c.wrenSetSlotBool(vm, 0, true);
            return;
        }
        wren_c.c.wrenSetSlotBool(vm, 0, false);
    }

    fn entity_spawnRect(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        var color_buf: [32]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const width = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 4)));
        const height = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 5)));
        const color_name = getSlotString(vm, 6, &color_buf);
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        var builder = scene.entity();
        _ = builder.withTag(tag).withTransform(.{ .x = x, .y = y }).withRect(width, height, parseApiColor(color_name)).withBoxCollider(width, height);
        _ = builder.build();
        wren_c.c.wrenSetSlotBool(vm, 0, true);
    }

    fn entity_spawnCircle(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        var color_buf: [32]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const radius = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 4)));
        const color_name = getSlotString(vm, 5, &color_buf);
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        var builder = scene.entity();
        _ = builder.withTag(tag).withTransform(.{ .x = x, .y = y }).withCircle(radius, parseApiColor(color_name));
        _ = builder.build();
        wren_c.c.wrenSetSlotBool(vm, 0, true);
    }

    fn entity_setAnimation(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        var name_buf: [32]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const name = getSlotString(vm, 2, &name_buf);
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        wren_c.c.wrenSetSlotBool(vm, 0, ecs.Systems.setAnimation(&scene.world, tag, name));
    }

    fn entity_tweenTo(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const x = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const y = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 3)));
        const duration = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 4)));
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        if (scene.world.findByTag(tag)) |entity| {
            scene.world.tweens.set(scene.world.allocator, entity, .{ .to = .{ .x = x, .y = y }, .duration = duration }) catch {};
            wren_c.c.wrenSetSlotBool(vm, 0, true);
            return;
        }
        wren_c.c.wrenSetSlotBool(vm, 0, false);
    }

    fn entity_emitParticles(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var tag_buf: [events.MAX_ID_LEN]u8 = undefined;
        const tag = getSlotString(vm, 1, &tag_buf);
        const count = @as(usize, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        if (scene.world.findByTag(tag)) |entity| {
            if (scene.world.particle_emitters.get(entity)) |emitter| {
                emitter.burst += count;
                wren_c.c.wrenSetSlotBool(vm, 0, true);
                return;
            }
        }
        wren_c.c.wrenSetSlotBool(vm, 0, false);
    }

    fn camera_shake(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const intensity = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 1)));
        const duration = @as(f32, @floatCast(wren_c.c.wrenGetSlotDouble(vm, 2)));
        const ctx = getCtx(vm);
        const scene = ctx.sceneManager.currentScene();
        ecs.Systems.shakeCamera(&scene.world, intensity, duration);
    }

    fn inventory_add(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var item_buf: [events.MAX_ID_LEN]u8 = undefined;
        const item = getSlotString(vm, 1, &item_buf);
        const amount = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2)));
        var key_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "inv.{s}", .{item}) catch return;
        getCtx(vm).storyState.addInt(key, amount);
    }

    fn inventory_count(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var item_buf: [events.MAX_ID_LEN]u8 = undefined;
        const item = getSlotString(vm, 1, &item_buf);
        var key_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "inv.{s}", .{item}) catch {
            wren_c.c.wrenSetSlotDouble(vm, 0, 0);
            return;
        };
        wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(getCtx(vm).storyState.getInt(key)));
    }

    fn inventory_has(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var item_buf: [events.MAX_ID_LEN]u8 = undefined;
        const item = getSlotString(vm, 1, &item_buf);
        const amount = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2)));
        var key_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "inv.{s}", .{item}) catch {
            wren_c.c.wrenSetSlotBool(vm, 0, false);
            return;
        };
        wren_c.c.wrenSetSlotBool(vm, 0, getCtx(vm).storyState.getInt(key) >= amount);
    }

    fn quest_start(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        setQuestState(vm, "active");
    }

    fn quest_complete(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        setQuestState(vm, "complete");
    }

    fn quest_isActive(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        wren_c.c.wrenSetSlotBool(vm, 0, questStateEquals(vm, "active"));
    }

    fn quest_isComplete(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        wren_c.c.wrenSetSlotBool(vm, 0, questStateEquals(vm, "complete"));
    }

    fn combat_setHp(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var actor_buf: [events.MAX_ID_LEN]u8 = undefined;
        const actor = getSlotString(vm, 1, &actor_buf);
        const hp = @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2)));
        getCtx(vm).combatState.setHp(actor, hp);
    }

    fn combat_damage(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        modifyCombatHp(vm, -@as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2))));
    }

    fn combat_heal(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        modifyCombatHp(vm, @as(i32, @intFromFloat(wren_c.c.wrenGetSlotDouble(vm, 2))));
    }

    fn combat_hp(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var actor_buf: [events.MAX_ID_LEN]u8 = undefined;
        const actor = getSlotString(vm, 1, &actor_buf);
        wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(getCtx(vm).combatState.hp(actor)));
    }

    fn combat_mp(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var actor_buf: [events.MAX_ID_LEN]u8 = undefined;
        const actor = getSlotString(vm, 1, &actor_buf);
        const state = getCtx(vm).combatState;
        for (state.battlers[0..state.battler_count]) |b| {
            if (std.mem.eql(u8, b.actor.id, actor)) {
                wren_c.c.wrenSetSlotDouble(vm, 0, @floatFromInt(b.mp));
                return;
            }
        }
        wren_c.c.wrenSetSlotDouble(vm, 0, 0);
    }

    fn combat_start(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        var id_buf: [events.MAX_ID_LEN]u8 = undefined;
        const id = getSlotString(vm, 1, &id_buf);
        wren_c.c.wrenSetSlotBool(vm, 0, getCtx(vm).combatState.start(id));
    }

    fn combat_isActive(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        wren_c.c.wrenSetSlotBool(vm, 0, getCtx(vm).combatState.active);
    }

    fn combat_state(vm_opt: ?*wren_c.c.WrenVM) callconv(.c) void {
        const vm = vm_opt.?;
        const state = getCtx(vm).combatState.phase;
        const text = switch (state) {
            .idle => "idle",
            .player_turn => "player_turn",
            .enemy_turn => "enemy_turn",
            .resolving => "resolving",
            .won => "won",
            .lost => "lost",
        };
        wren_c.c.wrenSetSlotBytes(vm, 0, text.ptr, text.len);
    }

    fn setQuestState(vm: *wren_c.c.WrenVM, value: []const u8) void {
        var quest_buf: [events.MAX_ID_LEN]u8 = undefined;
        const quest = getSlotString(vm, 1, &quest_buf);
        var key_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "quest.{s}", .{quest}) catch return;
        getCtx(vm).storyState.setString(key, value);
    }

    fn questStateEquals(vm: *wren_c.c.WrenVM, value: []const u8) bool {
        var quest_buf: [events.MAX_ID_LEN]u8 = undefined;
        const quest = getSlotString(vm, 1, &quest_buf);
        var key_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "quest.{s}", .{quest}) catch return false;
        return std.mem.eql(u8, getCtx(vm).storyState.getString(key), value);
    }

    fn modifyCombatHp(vm: *wren_c.c.WrenVM, delta: i32) void {
        var actor_buf: [events.MAX_ID_LEN]u8 = undefined;
        const actor = getSlotString(vm, 1, &actor_buf);
        getCtx(vm).combatState.modifyHp(actor, delta);
    }

    fn parseApiColor(value: []const u8) rl.Color {
        if (std.ascii.eqlIgnoreCase(value, "red")) return rl.Color.red;
        if (std.ascii.eqlIgnoreCase(value, "green")) return rl.Color.green;
        if (std.ascii.eqlIgnoreCase(value, "blue")) return rl.Color.blue;
        if (std.ascii.eqlIgnoreCase(value, "black")) return rl.Color.black;
        if (std.ascii.eqlIgnoreCase(value, "white")) return rl.Color.white;
        if (value.len == 7 and value[0] == '#') {
            const r = std.fmt.parseInt(u8, value[1..3], 16) catch return rl.Color.white;
            const g = std.fmt.parseInt(u8, value[3..5], 16) catch return rl.Color.white;
            const b = std.fmt.parseInt(u8, value[5..7], 16) catch return rl.Color.white;
            return .{ .r = r, .g = g, .b = b, .a = 255 };
        }
        return rl.Color.white;
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
