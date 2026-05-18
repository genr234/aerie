const std = @import("std");
const builtin = @import("builtin");
const assets = @import("../utils/assets.zig");
const project = @import("../project.zig");
const resources = @import("../resources.zig");
const wren_c = @import("wren_c.zig");

pub const Loader = struct {
    allocator: std.mem.Allocator,
    project_root: []const u8,
    modules: []const project.ScriptModule = &.{},
    resources: ?resources.ResourceProvider = null,

    pub fn init(
        allocator: std.mem.Allocator,
        project_root: []const u8,
        modules: []const project.ScriptModule,
        resource_provider: ?resources.ResourceProvider,
    ) Loader {
        return .{ .allocator = allocator, .project_root = project_root, .modules = modules, .resources = resource_provider };
    }

    pub fn deinit(self: *Loader) void {
        _ = self;
    }

    fn moduleNameToAssetPath(self: *Loader, raw_name: [*:0]const u8) ![:0]u8 {
        const name = std.mem.span(raw_name);

        // Wren module names are passed without extension.
        // We map "main" -> "assets/scripts/main.wren".
        const rel = try std.fmt.allocPrint(self.allocator, "scripts/{s}.wren", .{name});
        defer self.allocator.free(rel);
        return assets.parseAssetPath(self.allocator, self.project_root, rel, builtin.os.tag);
    }

    pub fn findModuleSource(self: *const Loader, name: []const u8) ?[]const u8 {
        for (self.modules) |module| {
            if (std.mem.eql(u8, module.name, name)) return module.source;
        }
        return null;
    }

    pub fn loadOwnedModuleSource(self: *Loader, name: []const u8) ![]const u8 {
        if (self.findModuleSource(name)) |source| {
            return self.allocator.dupe(u8, source);
        }

        const rel = try std.fmt.allocPrint(self.allocator, "scripts/{s}.wren", .{name});
        defer self.allocator.free(rel);

        if (self.resources) |provider| {
            const path = try std.fmt.allocPrint(self.allocator, "assets/{s}", .{rel});
            defer self.allocator.free(path);
            return provider.readText(self.allocator, path);
        }

        const asset_path = try assets.resolveAssetPath(self.allocator, self.project_root, rel, builtin.os.tag);
        defer self.allocator.free(asset_path);

        const io = std.Io.Threaded.global_single_threaded.io();
        var file = std.Io.Dir.cwd().openFile(io, asset_path, .{}) catch |err| {
            std.debug.print("[wren] failed to open {s}: {any}\n", .{ asset_path, err });
            return error.WrenLoadFailed;
        };
        defer file.close(io);

        var reader = file.reader(io, &.{});
        return reader.interface.allocRemaining(self.allocator, .limited(1 << 20)) catch |err| switch (err) {
            error.ReadFailed => return reader.err.?,
            else => |e| return e,
        };
    }

    pub fn loadModule(
        self: *Loader,
        vm: ?*wren_c.c.WrenVM,
        name: [*:0]const u8,
    ) callconv(.c) wren_c.c.WrenLoadModuleResult {
        _ = vm;

        const mod_name = std.mem.span(name);

        if (std.mem.eql(u8, mod_name, "engine/api")) {
            return loadEngineApiModule();
        }

        if (self.findModuleSource(mod_name)) |source| {
            return copySourceForWren(source);
        }

        if (self.resources) |provider| {
            const path = std.fmt.allocPrint(self.allocator, "assets/scripts/{s}.wren", .{mod_name}) catch {
                return .{ .source = null, .onComplete = null, .userData = null };
            };
            defer self.allocator.free(path);

            const source = provider.readText(self.allocator, path) catch {
                return .{ .source = null, .onComplete = null, .userData = null };
            };
            defer self.allocator.free(source);

            return copySourceForWren(source);
        }

        const asset_path = self.moduleNameToAssetPath(name) catch {
            return .{ .source = null, .onComplete = null, .userData = null };
        };

        const io = std.Io.Threaded.global_single_threaded.io();
        var file = std.Io.Dir.cwd().openFile(io, asset_path, .{}) catch {
            self.allocator.free(asset_path);
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        defer file.close(io);

        // Allocate module source using the C allocator so `onComplete` can free
        // it reliably (Wren doesn't pass a Loader instance back).
        // Wren expects a null-terminated C string whose lifetime extends until
        // `onComplete` is called.
        var reader = file.reader(io, &.{});
        const src = reader.interface.allocRemaining(std.heap.c_allocator, .limited(1 << 20)) catch {
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

    fn copySourceForWren(source: []const u8) wren_c.c.WrenLoadModuleResult {
        const zsrc = std.heap.c_allocator.allocSentinel(u8, source.len, 0) catch {
            return .{ .source = null, .onComplete = null, .userData = null };
        };
        @memcpy(zsrc[0..source.len], source);

        return .{
            .source = @ptrCast(zsrc.ptr),
            .onComplete = &onModuleSourceFree,
            .userData = zsrc.ptr,
        };
    }

    fn loadEngineApiModule() wren_c.c.WrenLoadModuleResult {
        // The module source is embedded (static storage); no onComplete needed.
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
        \\  foreign static playSound(id, volume, loop)
        \\  foreign static pause(paused)
        \\  foreign static quit()
        \\
        \\  foreign static setFlag(name, value)
        \\  foreign static getFlag(name)
        \\  foreign static toggleFlag(name)
        \\  foreign static hasFlag(name)
        \\
        \\  foreign static setInt(name, value)
        \\  foreign static getInt(name)
        \\  foreign static addInt(name, delta)
        \\
        \\  foreign static setFloat(name, value)
        \\  foreign static getFloat(name)
        \\
        \\  foreign static setString(name, value)
        \\  foreign static getString(name)
        \\
        \\  foreign static setRelationship(name, value)
        \\  foreign static getRelationship(name)
        \\  foreign static modifyRelationship(name, delta)
        \\
        \\  foreign static setChapter(chapter)
        \\  foreign static getChapter()
        \\  foreign static setRoute(route)
        \\  foreign static getRoute()
        \\  foreign static getPlayTimeMinutes()
        \\
        \\  foreign static change(index)
        \\  foreign static changeByName(name)
        \\  foreign static currentIndex()
        \\  foreign static findIndex(name)
        \\  foreign static sceneCount()
        \\
        \\  foreign static start()
        \\  foreign static startAt(label)
        \\  foreign static stopDialogue()
        \\  foreign static dialogueIsActive()
        \\  foreign static dialogueSkip()
        \\  foreign static dialogueAdvance()
        \\
        \\  foreign static entityExists(tag)
        \\  foreign static entitySetActive(tag, active)
        \\  foreign static entityGetPosition(tag)
        \\  foreign static entitySetPosition(tag, x, y)
        \\  foreign static onKeyPressed(key, callback)
        \\  foreign static onKeyReleased(key, callback)
        \\  foreign static onAnyKey(callback)
        \\  foreign static onMousePressed(button, callback)
        \\  foreign static onMouseMove(callback)
        \\  foreign static onTick(callback)
        \\}
        \\
        \\foreign class UI {
        \\  foreign static button(x, y, w, h, label)
        \\  foreign static text(x, y, content)
        \\  foreign static panel(x, y, w, h)
        \\  foreign static bar(x, y, w, h, value, maxValue)
        \\  foreign static inputField(x, y, w, h, id)
        \\  foreign static getInputText()
        \\  foreign static setInputText(text)
        \\  foreign static clearInput()
        \\}
        \\
        \\class Events {
        \\  static message(text, duration) { Engine.showMessage(text, duration) }
        \\  static playSound(id, volume, loop) { Engine.playSound(id, volume, loop) }
        \\  static pause(paused) { Engine.pause(paused) }
        \\  static quit() { Engine.quit() }
        \\}
        \\
        \\class State {
        \\  static set(name, value) {
        \\    if (value is Bool) return Engine.setFlag(name, value)
        \\    if (value is Num) return Engine.setFloat(name, value)
        \\    if (value is String) return Engine.setString(name, value)
        \\  }
        \\
        \\  static get(name) {
        \\    if (Engine.hasFlag(name)) return Engine.getFlag(name)
        \\    var text = Engine.getString(name)
        \\    if (text != "") return text
        \\    return Engine.getFloat(name)
        \\  }
        \\
        \\  static update(name, callback) { State.set(name, callback.call(State.get(name))) }
        \\
        \\  static setFlag(name, value) { Engine.setFlag(name, value) }
        \\  static getFlag(name) { Engine.getFlag(name) }
        \\  static toggleFlag(name) { Engine.toggleFlag(name) }
        \\  static hasFlag(name) { Engine.hasFlag(name) }
        \\
        \\  static setInt(name, value) { Engine.setInt(name, value) }
        \\  static getInt(name) { Engine.getInt(name) }
        \\  static addInt(name, delta) { Engine.addInt(name, delta) }
        \\
        \\  static setFloat(name, value) { Engine.setFloat(name, value) }
        \\  static getFloat(name) { Engine.getFloat(name) }
        \\
        \\  static setString(name, value) { Engine.setString(name, value) }
        \\  static getString(name) { Engine.getString(name) }
        \\
        \\  static setRelationship(name, value) { Engine.setRelationship(name, value) }
        \\  static getRelationship(name) { Engine.getRelationship(name) }
        \\  static modifyRelationship(name, delta) { Engine.modifyRelationship(name, delta) }
        \\
        \\  static setChapter(chapter) { Engine.setChapter(chapter) }
        \\  static getChapter() { Engine.getChapter() }
        \\  static setRoute(route) { Engine.setRoute(route) }
        \\  static getRoute() { Engine.getRoute() }
        \\  static getPlayTimeMinutes() { Engine.getPlayTimeMinutes() }
        \\}
        \\
        \\class Scene {
        \\  static change(index) { Engine.change(index) }
        \\  static go(name) { Engine.changeByName(name) }
        \\  static currentIndex() { Engine.currentIndex() }
        \\  static findIndex(name) { Engine.findIndex(name) }
        \\  static count() { Engine.sceneCount() }
        \\}
        \\
        \\class Dialogue {
        \\  static start() { Engine.start() }
        \\  static startAt(label) { Engine.startAt(label) }
        \\  static stop() { Engine.stopDialogue() }
        \\  static isActive() { Engine.dialogueIsActive() }
        \\  static skip() { Engine.dialogueSkip() }
        \\  static advance() { Engine.dialogueAdvance() }
        \\}
        \\
        \\class Entity {
        \\  static exists(tag) { Engine.entityExists(tag) }
        \\  static setActive(tag, active) { Engine.entitySetActive(tag, active) }
        \\  static getPosition(tag) { Engine.entityGetPosition(tag) }
        \\  static setPosition(tag, x, y) { Engine.entitySetPosition(tag, x, y) }
        \\}
        \\
        \\class Input {
        \\  static onKeyPressed(key, callback) { Engine.onKeyPressed(key, callback) }
        \\  static onKeyReleased(key, callback) { Engine.onKeyReleased(key, callback) }
        \\  static onAnyKey(callback) { Engine.onAnyKey(callback) }
        \\  static onMousePressed(button, callback) { Engine.onMousePressed(button, callback) }
        \\  static onMouseMove(callback) { Engine.onMouseMove(callback) }
        \\  static onTick(callback) { Engine.onTick(callback) }
        \\}
        \\    
    ;
};
