const std = @import("std");
const rl = @import("raylib");
const dialogue = @import("dialogue.zig");

pub const MAX_MESSAGE_LEN = 256;
pub const MAX_ID_LEN = 64;

pub const ShowMessage = struct {
    message: [MAX_MESSAGE_LEN]u8 = undefined,
    duration: f32 = 2.0,
    elapsed: f32 = 0.0,
    len: usize = 0,

    pub fn getText(self: *const ShowMessage) [:0]const u8 {
        return self.message[0..self.len :0];
    }
};

pub const StartDialogue = struct {
    runner: *dialogue.Runner,
    context: ?*anyopaque = null,
    labelId: [MAX_ID_LEN]u8 = undefined,
    labelLen: usize = 0,

    pub fn getLabel(self: *const StartDialogue) ?[]const u8 {
        if (self.labelLen == 0) return null;
        return self.labelId[0..self.labelLen];
    }
};

pub const ChangeScene = struct {
    sceneIndex: usize = 0,
    sceneName: [MAX_ID_LEN]u8 = undefined,
    nameLen: usize = 0,
    useIndex: bool = true,

    pub fn getSceneName(self: *const ChangeScene) ?[]const u8 {
        if (self.nameLen == 0) return null;
        return self.sceneName[0..self.nameLen];
    }
};

pub const SetFlag = struct {
    name: [MAX_ID_LEN]u8 = undefined,
    nameLen: usize = 0,
    value: bool = true,

    pub fn getFlagName(self: *const SetFlag) []const u8 {
        return self.name[0..self.nameLen];
    }
};

pub const PlaySound = struct {
    soundId: [MAX_ID_LEN]u8 = undefined,
    soundIdLen: usize = 0,
    volume: f32 = 1.0,
    loop: bool = false,

    pub fn getSoundId(self: *const PlaySound) []const u8 {
        return self.soundId[0..self.soundIdLen];
    }
};

pub const SetEntityActive = struct {
    entityTag: [MAX_ID_LEN]u8 = undefined,
    tagLen: usize = 0,
    active: bool = true,

    pub fn getEntityTag(self: *const SetEntityActive) []const u8 {
        return self.entityTag[0..self.tagLen];
    }
};


pub const Event = union(enum) {
    ShowMessage: ShowMessage,
    StartDialogue: StartDialogue,
    ChangeScene: ChangeScene,
    SetFlag: SetFlag,
    PlaySound: PlaySound,
    SetEntityActive: SetEntityActive,
    PauseGame: struct { paused: bool = true },
    QuitGame: void,
    Custom: struct {
        id: u32,
        data: ?*anyopaque = null,
    },
};


pub fn showMessage(text: []const u8, duration: f32) Event {
    const len = @min(text.len, MAX_MESSAGE_LEN - 1);
    var msg: ShowMessage = .{ .len = len, .duration = duration, .elapsed = 0.0 };
    @memcpy(msg.message[0..len], text[0..len]);
    msg.message[len] = 0;
    return .{ .ShowMessage = msg };
}

pub fn startDialogue(runner: *dialogue.Runner, context: ?*anyopaque) Event {
    return .{ .StartDialogue = .{
        .runner = runner,
        .context = context,
    } };
}

pub fn startDialogueAt(runner: *dialogue.Runner, context: ?*anyopaque, label: []const u8) Event {
    const len = @min(label.len, MAX_ID_LEN - 1);
    var ev: StartDialogue = .{ .runner = runner, .context = context, .labelLen = len };
    @memcpy(ev.labelId[0..len], label[0..len]);
    ev.labelId[len] = 0;
    return .{ .StartDialogue = ev };
}

pub fn changeSceneByIndex(index: usize) Event {
    return .{ .ChangeScene = .{ .sceneIndex = index, .useIndex = true } };
}

pub fn changeSceneByName(name: []const u8) Event {
    const len = @min(name.len, MAX_ID_LEN - 1);
    var ev: ChangeScene = .{ .useIndex = false, .nameLen = len };
    @memcpy(ev.sceneName[0..len], name[0..len]);
    ev.sceneName[len] = 0;
    return .{ .ChangeScene = ev };
}

pub fn setFlag(name: []const u8, value: bool) Event {
    const len = @min(name.len, MAX_ID_LEN - 1);
    var ev: SetFlag = .{ .nameLen = len, .value = value };
    @memcpy(ev.name[0..len], name[0..len]);
    ev.name[len] = 0;
    return .{ .SetFlag = ev };
}

pub fn playSound(soundId: []const u8, volume: f32, loop: bool) Event {
    const len = @min(soundId.len, MAX_ID_LEN - 1);
    var ev: PlaySound = .{ .soundIdLen = len, .volume = volume, .loop = loop };
    @memcpy(ev.soundId[0..len], soundId[0..len]);
    ev.soundId[len] = 0;
    return .{ .PlaySound = ev };
}

pub fn setEntityActive(tag: []const u8, active: bool) Event {
    const len = @min(tag.len, MAX_ID_LEN - 1);
    var ev: SetEntityActive = .{ .tagLen = len, .active = active };
    @memcpy(ev.entityTag[0..len], tag[0..len]);
    ev.entityTag[len] = 0;
    return .{ .SetEntityActive = ev };
}

pub fn pauseGame(paused: bool) Event {
    return .{ .PauseGame = .{ .paused = paused } };
}

pub fn quitGame() Event {
    return .{ .QuitGame = {} };
}

pub fn customEvent(id: u32, data: ?*anyopaque) Event {
    return .{ .Custom = .{ .id = id, .data = data } };
}

// ============================================================================
// Event Queue
// ============================================================================

/// Handler function type for external event processing.
/// Return true if the event was consumed and should be removed, false to keep it.
pub const EventHandler = *const fn (event: *Event, ctx: ?*anyopaque) bool;

/// Entry for storing handler with context
pub const HandlerEntry = struct {
    handler: EventHandler,
    ctx: ?*anyopaque,
};

pub const EventQueue = struct {
    events: [128]Event = undefined,
    capacity: usize = 128,
    count: usize = 0,

    /// External handlers for events that need special processing (e.g., SceneManager for ChangeScene)
    handlers: [8]?HandlerEntry = [_]?HandlerEntry{null} ** 8,
    handlerCount: usize = 0,

    pub fn init() EventQueue {
        return EventQueue{ .events = undefined, .capacity = 128, .count = 0 };
    }

    pub fn deinit(self: *EventQueue) void {
        self.count = 0;
        self.handlerCount = 0;
    }

    /// Register an event handler that will be called for each event during processing
    pub fn addHandler(self: *EventQueue, handler: EventHandler, ctx: ?*anyopaque) void {
        if (self.handlerCount < self.handlers.len) {
            self.handlers[self.handlerCount] = .{ .handler = handler, .ctx = ctx };
            self.handlerCount += 1;
        }
    }

    /// Remove an event handler
    pub fn removeHandler(self: *EventQueue, handler: EventHandler) void {
        var i: usize = 0;
        while (i < self.handlerCount) {
            if (self.handlers[i]) |h| {
                if (h.handler == handler) {
                    // Shift remaining handlers
                    var j = i;
                    while (j + 1 < self.handlerCount) : (j += 1) {
                        self.handlers[j] = self.handlers[j + 1];
                    }
                    self.handlers[self.handlerCount - 1] = null;
                    self.handlerCount -= 1;
                    continue;
                }
            }
            i += 1;
        }
    }

    pub fn push(self: *EventQueue, event: Event) !void {
        if (self.count >= self.capacity) {
            return error.QueueFull;
        }
        self.events[self.count] = event;
        self.count += 1;
    }

    pub fn pop(self: *EventQueue) ?Event {
        if (self.count == 0) {
            return null;
        }
        self.count -= 1;
        return self.events[self.count];
    }

    pub fn peek(self: *const EventQueue, index: usize) ?*const Event {
        if (index >= self.count) return null;
        return &self.events[index];
    }

    pub fn isEmpty(self: *const EventQueue) bool {
        return self.count == 0;
    }

    pub fn clear(self: *EventQueue) void {
        self.count = 0;
    }

    /// Process all events. Some events like ShowMessage persist until their duration expires.
    pub fn handleEvents(self: *EventQueue, dt: f32) void {
        var i: usize = 0;
        while (i < self.count) {
            var consumed = false;

            for (self.handlers[0..self.handlerCount]) |maybeHandler| {
                if (maybeHandler) |h| {
                    if (h.handler(&self.events[i], h.ctx)) {
                        consumed = true;
                        break;
                    }
                }
            }

            // If not consumed by external handler, handle built-in events
            if (!consumed) {
                consumed = self.handleBuiltinEvent(&self.events[i], dt);
            }

            if (consumed) {
                // Remove the event by swapping with last
                if (i < self.count - 1) {
                    self.events[i] = self.events[self.count - 1];
                }
                self.count -= 1;
            } else {
                i += 1;
            }
        }
    }

    fn handleBuiltinEvent(self: *EventQueue, event: *Event, dt: f32) bool {
        _ = self;
        switch (event.*) {
            .ShowMessage => |*msg| {
                msg.elapsed += dt;
                if (msg.elapsed < msg.duration) {
                    const text = msg.getText();
                    rl.drawText(text, 10, 10, 20, .red);
                    return false; // Keep the event
                } else {
                    return true; // Remove the event
                }
            },
            .StartDialogue => |*dlg| {
                // Start the dialogue runner
                if (dlg.getLabel()) |label| {
                    // Jump to label then start
                    if (dlg.runner.script.findLabel(label)) |idx| {
                        dlg.runner.index = idx;
                    }
                }
                dlg.runner.start(dlg.context);
                return true;
            },
            // Events that need external handling (SceneManager, StoryState, etc.)
            .ChangeScene, .SetFlag, .PlaySound, .SetEntityActive, .PauseGame, .QuitGame, .Custom => {
                return true;
            },
        }
    }

    pub fn iterator(self: *EventQueue) Iterator {
        return .{ .queue = self, .index = 0 };
    }

    pub const Iterator = struct {
        queue: *EventQueue,
        index: usize,

        pub fn next(self: *Iterator) ?*Event {
            if (self.index >= self.queue.count) return null;
            const event = &self.queue.events[self.index];
            self.index += 1;
            return event;
        }
    };

    pub fn hasEventOfType(self: *const EventQueue, comptime event_type: std.meta.Tag(Event)) bool {
        for (self.events[0..self.count]) |evt| {
            if (std.meta.activeTag(evt) == event_type) return true;
        }
        return false;
    }

    pub fn countEventsOfType(self: *const EventQueue, comptime event_type: std.meta.Tag(Event)) usize {
        var count: usize = 0;
        for (self.events[0..self.count]) |evt| {
            if (std.meta.activeTag(evt) == event_type) count += 1;
        }
        return count;
    }

    pub fn len(self: *const EventQueue) usize {
        return self.count;
    }
};