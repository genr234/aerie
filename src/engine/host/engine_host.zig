const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

const mem = @import("../memory.zig");
const project = @import("../project.zig");
const scripting_runtime = @import("../scripting/runtime.zig");
const scripting_context = @import("../scripting/context.zig");

pub const EngineHost = struct {
    initialized: bool = false,
    project_root: []const u8 = ".",

    script_ctx: scripting_context.ScriptingContext = undefined,
    wren_runtime: ?scripting_runtime.Runtime = null,

    clear_color: rl.Color = rl.Color{ .r = 20, .g = 20, .b = 24, .a = 255 },

    const Self = @This();

    pub fn init(self: *Self, project_root: []const u8) !void {
        mem.init();
        self.project_root = project_root;

        const project_cfg = project.loadProjectConfig(mem.permanent(), project_root) catch project.ProjectConfig{
            .id = "game",
            .title = "Game",
        };

        const ztitle = try std.fmt.allocPrint(mem.frame(), "{s}", .{project_cfg.window_title});
        ztitle.ptr[ztitle.len] = 0;
        rl.initWindow(project_cfg.window_width, project_cfg.window_height, @ptrCast(ztitle.ptr[0..ztitle.len :0]));
        rl.setTargetFPS(60);

        self.wren_runtime = scripting_runtime.Runtime.init(
            mem.permanent(),
            &self.script_ctx,
            project_root,
            project_cfg.entry_module,
            project_cfg.entry_class,
        ) catch |err| blk: {
            std.debug.print("[wren] runtime init failed: {any}\n", .{err});
            break :blk null;
        };

        self.initialized = true;
    }

    pub fn deinit(self: *Self) void {
        if (!self.initialized) return;

        if (self.wren_runtime) |*rt| {
            rt.deinit();
            self.wren_runtime = null;
        }

        rl.closeWindow();
        mem.deinit();
        self.initialized = false;
    }

    pub fn tick(self: *Self) void {
        if (!self.initialized) return;

        mem.resetFrame();
        const dt = rl.getFrameTime();

        if (self.wren_runtime) |*rt| {
            if (builtin.os.tag != .emscripten) {
                rt.reloadIfChanged();
            }
            rt.dispatchInput(dt);
            _ = rt.callOnUpdate(dt);
        }
    }

    pub fn draw(self: *Self) void {
        if (!self.initialized) return;

        rl.beginDrawing();
        rl.clearBackground(self.clear_color);

        if (self.wren_runtime) |*rt| {
            _ = rt.callOnDraw();
        }

        rl.endDrawing();
    }
};
