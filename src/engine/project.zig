const std = @import("std");
const resources = @import("resources.zig");

pub const ProjectError = error{
    InvalidJson,
    MissingField,
    InvalidType,
    EmptyScenes,
    DuplicateSceneName,
    MissingStartScene,
};

pub const ProjectConfig = struct {
    id: []const u8,
    title: []const u8,
    version: []const u8 = "0.1.0",

    entry_module: []const u8 = "main",
    entry_class: []const u8 = "Game",

    start_scene: []const u8 = "assets/scenes/start.json",
    scenes: []SceneDecl = &.{},

    window_width: i32 = 800,
    window_height: i32 = 450,
    window_title: []const u8 = "Game",
};

pub const SceneDecl = struct {
    name: []const u8,
    path: []const u8,
};

pub const SceneSource = struct {
    name: []const u8,
    json: []const u8,
};

pub const ScriptModule = struct {
    name: []const u8,
    source: []const u8,
};

pub const ProjectBundle = struct {
    config: ProjectConfig,
    scenes: []SceneSource,
    scripts: []ScriptModule,
    resources: ?resources.ResourceProvider = null,
    asset_root: []const u8 = ".",

    pub fn findScene(self: *const ProjectBundle, name: []const u8) ?SceneSource {
        for (self.scenes) |scene| {
            if (std.mem.eql(u8, scene.name, name)) return scene;
        }
        return null;
    }

    pub fn startScene(self: *const ProjectBundle) ?SceneSource {
        if (self.findScene(self.config.start_scene)) |scene| return scene;
        for (self.config.scenes) |decl| {
            if (std.mem.eql(u8, decl.path, self.config.start_scene)) {
                if (self.findScene(decl.name)) |scene| return scene;
            }
        }
        return null;
    }

    pub fn findScript(self: *const ProjectBundle, name: []const u8) ?ScriptModule {
        for (self.scripts) |script| {
            if (std.mem.eql(u8, script.name, name)) return script;
        }
        return null;
    }
};

pub fn loadProjectConfig(allocator: std.mem.Allocator, project_root: []const u8) !ProjectConfig {
    var fs_provider = resources.FsResourceProvider{ .root = project_root };
    const text = fs_provider.provider().readText(allocator, "game.json") catch return ProjectError.MissingField;
    defer allocator.free(text);

    return parseProjectConfigJson(allocator, text);
}

pub fn parseProjectConfigJson(allocator: std.mem.Allocator, text: []const u8) !ProjectConfig {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return ProjectError.InvalidJson;
    defer parsed.deinit();

    return parseProjectConfig(allocator, parsed.value);
}

pub fn loadProjectBundleFromFs(allocator: std.mem.Allocator, project_root: []const u8) !ProjectBundle {
    const fs_provider = try allocator.create(resources.FsResourceProvider);
    fs_provider.* = .{ .root = try dupString(allocator, project_root) };
    const provider = fs_provider.provider();

    const config_text = provider.readText(allocator, "game.json") catch return ProjectError.MissingField;
    defer allocator.free(config_text);
    const cfg = try parseProjectConfigJson(allocator, config_text);

    const scenes = if (cfg.scenes.len > 0)
        try loadDeclaredScenes(allocator, provider, cfg.scenes)
    else blk: {
        const scene_json = try provider.readText(allocator, cfg.start_scene);
        const scene_name = try dupString(allocator, cfg.start_scene);
        const out = try allocator.alloc(SceneSource, 1);
        out[0] = .{ .name = scene_name, .json = scene_json };
        break :blk out;
    };

    const scripts = try loadScriptModulesFromFs(allocator, project_root);

    return .{
        .config = cfg,
        .scenes = scenes,
        .scripts = scripts,
        .resources = provider,
        .asset_root = try dupString(allocator, project_root),
    };
}

fn loadScriptModulesFromFs(allocator: std.mem.Allocator, project_root: []const u8) ![]ScriptModule {
    const scripts_root = try std.fs.path.join(allocator, &.{ project_root, "assets", "scripts" });
    defer allocator.free(scripts_root);

    var modules = std.ArrayList(ScriptModule).empty;
    errdefer modules.deinit(allocator);

    try loadScriptModulesInDir(allocator, scripts_root, "", &modules);
    return modules.toOwnedSlice(allocator);
}

fn loadScriptModulesInDir(
    allocator: std.mem.Allocator,
    fs_dir_path: []const u8,
    module_prefix: []const u8,
    modules: *std.ArrayList(ScriptModule),
) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    var dir = try std.Io.Dir.cwd().openDir(io, fs_dir_path, .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".wren")) continue;

                const file_path = try std.fs.path.join(allocator, &.{ fs_dir_path, entry.name });
                defer allocator.free(file_path);

                const source = try resources.readFileAlloc(allocator, file_path);
                const base_name = entry.name[0 .. entry.name.len - ".wren".len];
                const module_name = if (module_prefix.len == 0)
                    try dupString(allocator, base_name)
                else
                    try std.fmt.allocPrint(allocator, "{s}/{s}", .{ module_prefix, base_name });

                try modules.append(allocator, .{ .name = module_name, .source = source });
            },
            .directory => {
                const child_path = try std.fs.path.join(allocator, &.{ fs_dir_path, entry.name });
                defer allocator.free(child_path);

                const child_prefix = if (module_prefix.len == 0)
                    try dupString(allocator, entry.name)
                else
                    try std.fmt.allocPrint(allocator, "{s}/{s}", .{ module_prefix, entry.name });
                defer allocator.free(child_prefix);

                try loadScriptModulesInDir(allocator, child_path, child_prefix, modules);
            },
            else => {},
        }
    }
}

fn parseProjectConfig(allocator: std.mem.Allocator, root: std.json.Value) !ProjectConfig {
    if (root != .object) return ProjectError.InvalidType;
    const obj = root.object;

    const id = try dupString(allocator, try getString(obj, "id"));
    const title = try dupString(allocator, try getString(obj, "title"));

    var cfg: ProjectConfig = .{
        .id = id,
        .title = title,
        .window_title = title,
    };

    if (obj.get("version")) |v| cfg.version = try dupString(allocator, try asString(v));

    if (obj.get("entry")) |e| {
        if (e != .object) return ProjectError.InvalidType;
        if (e.object.get("module")) |m| cfg.entry_module = try dupString(allocator, try asString(m));
        if (e.object.get("class")) |c| cfg.entry_class = try dupString(allocator, try asString(c));
    }

    if (obj.get("start_scene")) |s| cfg.start_scene = try dupString(allocator, try asString(s));
    if (obj.get("scenes")) |s| {
        cfg.scenes = try parseSceneDecls(allocator, s);
        if (!sceneDeclsContainStart(cfg.scenes, cfg.start_scene)) return ProjectError.MissingStartScene;
    }

    if (obj.get("window")) |w| {
        if (w != .object) return ProjectError.InvalidType;
        if (w.object.get("width")) |vv| cfg.window_width = @intCast(try asInt(vv));
        if (w.object.get("height")) |vv| cfg.window_height = @intCast(try asInt(vv));
        if (w.object.get("title")) |vv| cfg.window_title = try dupString(allocator, try asString(vv));
    }

    return cfg;
}

fn loadDeclaredScenes(allocator: std.mem.Allocator, provider: resources.ResourceProvider, decls: []const SceneDecl) ![]SceneSource {
    const scenes = try allocator.alloc(SceneSource, decls.len);
    errdefer allocator.free(scenes);

    for (decls, 0..) |decl, i| {
        scenes[i] = .{
            .name = try dupString(allocator, decl.name),
            .json = try provider.readText(allocator, decl.path),
        };
    }

    return scenes;
}

fn parseSceneDecls(allocator: std.mem.Allocator, v: std.json.Value) ![]SceneDecl {
    if (v != .array) return ProjectError.InvalidType;
    if (v.array.items.len == 0) return ProjectError.EmptyScenes;

    const out = try allocator.alloc(SceneDecl, v.array.items.len);
    errdefer allocator.free(out);

    for (v.array.items, 0..) |item, i| {
        if (item != .object) return ProjectError.InvalidType;
        const decl = SceneDecl{
            .name = try dupString(allocator, try getString(item.object, "name")),
            .path = try dupString(allocator, try getString(item.object, "path")),
        };
        for (out[0..i]) |existing| {
            if (std.mem.eql(u8, existing.name, decl.name)) return ProjectError.DuplicateSceneName;
        }
        out[i] = decl;
    }

    return out;
}

fn sceneDeclsContainStart(decls: []const SceneDecl, start_scene: []const u8) bool {
    for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, start_scene)) return true;
        if (std.mem.eql(u8, decl.path, start_scene)) return true;
    }
    return false;
}

fn getString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const v = obj.get(key) orelse return ProjectError.MissingField;
    return asString(v);
}

fn asString(v: std.json.Value) ![]const u8 {
    return switch (v) {
        .string => v.string,
        else => ProjectError.InvalidType,
    };
}

fn asInt(v: std.json.Value) !i64 {
    return switch (v) {
        .integer => v.integer,
        .float => @intFromFloat(v.float),
        else => ProjectError.InvalidType,
    };
}

fn dupString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    return buf;
}

test "project config parses declared scenes and start scene name" {
    const text =
        \\{
        \\  "id": "reference",
        \\  "title": "Reference",
        \\  "start_scene": "crossroads",
        \\  "scenes": [
        \\    { "name": "crossroads", "path": "assets/reference-game/crossroads.json" },
        \\    { "name": "clearing", "path": "assets/reference-game/clearing.json" }
        \\  ]
        \\}
    ;

    const cfg = try parseProjectConfigJson(std.testing.allocator, text);
    try std.testing.expectEqualStrings("crossroads", cfg.start_scene);
    try std.testing.expectEqual(@as(usize, 2), cfg.scenes.len);
    try std.testing.expectEqualStrings("clearing", cfg.scenes[1].name);
    try std.testing.expectEqualStrings("assets/reference-game/clearing.json", cfg.scenes[1].path);
}

test "project bundle resolves start scene by declared scene name" {
    const scenes = [_]SceneSource{
        .{ .name = "crossroads", .json = "{}" },
        .{ .name = "clearing", .json = "{}" },
    };
    const cfg = ProjectConfig{
        .id = "reference",
        .title = "Reference",
        .start_scene = "clearing",
    };
    const bundle = ProjectBundle{
        .config = cfg,
        .scenes = @constCast(&scenes),
        .scripts = &.{},
    };

    const start = bundle.startScene() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("clearing", start.name);
}

test "project config rejects empty declared scene list" {
    const text =
        \\{
        \\  "id": "reference",
        \\  "title": "Reference",
        \\  "start_scene": "crossroads",
        \\  "scenes": []
        \\}
    ;

    try std.testing.expectError(ProjectError.EmptyScenes, parseProjectConfigJson(std.testing.allocator, text));
}

test "project config rejects duplicate scene names" {
    const text =
        \\{
        \\  "id": "reference",
        \\  "title": "Reference",
        \\  "start_scene": "crossroads",
        \\  "scenes": [
        \\    { "name": "crossroads", "path": "assets/reference-game/crossroads.json" },
        \\    { "name": "crossroads", "path": "assets/reference-game/other.json" }
        \\  ]
        \\}
    ;

    try std.testing.expectError(ProjectError.DuplicateSceneName, parseProjectConfigJson(std.testing.allocator, text));
}

test "project config rejects missing declared start scene" {
    const text =
        \\{
        \\  "id": "reference",
        \\  "title": "Reference",
        \\  "start_scene": "missing",
        \\  "scenes": [
        \\    { "name": "crossroads", "path": "assets/reference-game/crossroads.json" }
        \\  ]
        \\}
    ;

    try std.testing.expectError(ProjectError.MissingStartScene, parseProjectConfigJson(std.testing.allocator, text));
}

test "project bundle does not fall back when start scene is unresolved" {
    const scenes = [_]SceneSource{
        .{ .name = "crossroads", .json = "{}" },
    };
    const cfg = ProjectConfig{
        .id = "reference",
        .title = "Reference",
        .start_scene = "missing",
    };
    const bundle = ProjectBundle{
        .config = cfg,
        .scenes = @constCast(&scenes),
        .scripts = &.{},
    };

    try std.testing.expect(bundle.startScene() == null);
}
