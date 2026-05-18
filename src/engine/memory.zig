const std = @import("std");
const builtin = @import("builtin");

pub const Memory = struct {
    /// Backing allocator (page_allocator in debug for safety, c_allocator in release/wasm)
    backing: std.mem.Allocator,

    /// Keep the GPA alive for the whole engine lifetime in Debug builds.
    debug_gpa: ?std.heap.DebugAllocator(.{}) = null,

    /// Permanent arena - lives for entire engine lifetime
    permanent_arena: std.heap.ArenaAllocator,

    /// Scene arena - reset on scene transitions
    scene_arena: std.heap.ArenaAllocator,

    /// Frame arena - reset every frame
    frame_arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init() Self {
        var self: Self = undefined;

        if (builtin.os.tag == .emscripten) {
            self.debug_gpa = null;
            self.backing = std.heap.c_allocator;
        } else if (builtin.mode == .Debug) {
            self.debug_gpa = null;
            self.backing = std.heap.page_allocator;
        } else {
            self.debug_gpa = null;
            self.backing = std.heap.c_allocator;
        }

        self.permanent_arena = std.heap.ArenaAllocator.init(self.backing);
        self.scene_arena = std.heap.ArenaAllocator.init(self.backing);
        self.frame_arena = std.heap.ArenaAllocator.init(self.backing);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.frame_arena.deinit();
        self.scene_arena.deinit();
        self.permanent_arena.deinit();

        if (self.debug_gpa) |*gpa| {
            const status = gpa.deinit();
            if (status == .leak) {
                std.debug.print("[memory] warning: GeneralPurposeAllocator detected leaks\n", .{});
            }
            self.debug_gpa = null;
        }
    }

    pub fn allocator(self: *Self, lifetime: enum { permanent, scene, frame, general }) std.mem.Allocator {
        switch (lifetime) {
            .permanent => return self.permanent_arena.allocator(),
            .scene => return self.scene_arena.allocator(),
            .frame => return self.frame_arena.allocator(),
            .general => return self.backing,
        }
    }

    /// Reset the frame arena - call at the start of each frame
    pub fn resetFrame(self: *Self) void {
        _ = self.frame_arena.reset(.retain_capacity);
    }

    /// Reset the scene arena - call on scene transitions
    pub fn resetScene(self: *Self) void {
        _ = self.scene_arena.reset(.retain_capacity);
    }

    /// Get backing allocator for special cases where you need a general allocator
    pub fn getGeneral(self: *Self) std.mem.Allocator {
        return self.backing;
    }
};

var memory: ?Memory = null;

pub fn init() void {
    if (memory == null) {
        memory = Memory.init();
    }
}

pub fn isInitialized() bool {
    return memory != null;
}

pub fn deinit() void {
    if (memory) |*m| {
        m.deinit();
        memory = null;
    }
}

/// Convenience accessors for the global memory instance
pub fn permanent() std.mem.Allocator {
    return memory.?.allocator(.permanent);
}

pub fn scene() std.mem.Allocator {
    return memory.?.allocator(.scene);
}

pub fn frame() std.mem.Allocator {
    return memory.?.allocator(.frame);
}

pub fn general() std.mem.Allocator {
    return memory.?.allocator(.general);
}

pub fn resetFrame() void {
    if (memory) |*m| {
        m.resetFrame();
    }
}

pub fn resetScene() void {
    if (memory) |*m| {
        m.resetScene();
    }
}
