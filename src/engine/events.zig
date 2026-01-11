const std = @import("std");
const rl = @import("raylib");
const dialogue = @import("dialogue.zig");
const scenes = @import("scenes.zig");
const story = @import("story.zig");
const audio = @import("audio.zig");

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


/// Callback for custom event handling (return true if consumed)
pub const CustomEventHandler = *const fn (id: u32, data: ?*anyopaque) bool;

/// Game systems binding for automatic event routing
pub const GameSystems = struct {
    sceneManager: ?*scenes.SceneManager = null,
    storyState: ?*story.StoryState = null,
    audioManager: ?*audio.AudioManager = null,
    customHandler: ?CustomEventHandler = null,
    onQuit: ?*const fn () void = null,
};

pub const EventQueue = struct {
    events: [128]Event = undefined,
    count: usize = 0,

    systems: GameSystems = .{},

    const Self = @This();
    const CAPACITY: usize = 128;

    /// Initialize an empty event queue
    pub fn init() Self {
        return .{};
    }

    /// Initialize with game systems already bound
    pub fn initWithSystems(sys: GameSystems) Self {
        return .{ .systems = sys };
    }

    pub fn deinit(self: *Self) void {
        self.count = 0;
        self.systems = .{};
    }

    /// Bind game systems for automatic event routing.
    /// This replaces the need for manual event handlers.
    pub fn bindSystems(self: *Self, sys: GameSystems) void {
        self.systems = sys;
    }

    /// Bind individual systems (convenience methods)
    pub fn bindSceneManager(self: *Self, mgr: *scenes.SceneManager) void {
        self.systems.sceneManager = mgr;
    }

    pub fn bindStoryState(self: *Self, state: *story.StoryState) void {
        self.systems.storyState = state;
    }

    pub fn bindAudioManager(self: *Self, mgr: *audio.AudioManager) void {
        self.systems.audioManager = mgr;
    }

    pub fn setCustomHandler(self: *Self, handler: CustomEventHandler) void {
        self.systems.customHandler = handler;
    }

    pub fn setOnQuit(self: *Self, handler: *const fn () void) void {
        self.systems.onQuit = handler;
    }


    pub fn push(self: *Self, event: Event) !void {
        if (self.count >= CAPACITY) {
            return error.QueueFull;
        }
        self.events[self.count] = event;
        self.count += 1;
    }

    pub fn pop(self: *Self) ?Event {
        if (self.count == 0) return null;
        self.count -= 1;
        return self.events[self.count];
    }

    pub fn peek(self: *const Self, index: usize) ?*const Event {
        if (index >= self.count) return null;
        return &self.events[index];
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.count == 0;
    }

    pub fn clear(self: *Self) void {
        self.count = 0;
    }

    pub fn len(self: *const Self) usize {
        return self.count;
    }

    /// Process all pending events, routing them to bound systems.
    /// Events like ShowMessage persist until their duration expires.
    pub fn process(self: *Self, dt: f32) void {
        var i: usize = 0;
        while (i < self.count) {
            const consumed = self.dispatchEvent(&self.events[i], dt);

            if (consumed) {
                // Remove by swapping with last
                if (i < self.count - 1) {
                    self.events[i] = self.events[self.count - 1];
                }
                self.count -= 1;
            } else {
                i += 1;
            }
        }
    }

    /// Dispatch a single event to the appropriate system
    fn dispatchEvent(self: *Self, event: *Event, dt: f32) bool {
        switch (event.*) {
            .ShowMessage => |*msg| {
                msg.elapsed += dt;
                if (msg.elapsed < msg.duration) {
                    const text = msg.getText();
                    rl.drawText(text, 10, 10, 20, rl.Color.red);
                    return false; // Keep until duration expires
                }
                return true;
            },

            .StartDialogue => |*dlg| {
                if (dlg.getLabel()) |label| {
                    if (dlg.runner.script.findLabel(label)) |idx| {
                        dlg.runner.index = idx;
                    }
                }
                dlg.runner.start(dlg.context);
                return true;
            },

            .ChangeScene => |cs| {
                if (self.systems.sceneManager) |mgr| {
                    if (cs.useIndex) {
                        mgr.changeScene(cs.sceneIndex) catch {};
                    } else if (cs.getSceneName()) |name| {
                        mgr.changeSceneByName(name) catch {};
                    }
                }
                return true;
            },

            .SetFlag => |sf| {
                if (self.systems.storyState) |state| {
                    state.setFlag(sf.getFlagName(), sf.value);
                }
                return true;
            },

            .PlaySound => |ps| {
                if (self.systems.audioManager) |mgr| {
                    if (ps.loop) {
                        mgr.playSoundLooped(ps.getSoundId(), ps.volume);
                    } else {
                        mgr.playSound(ps.getSoundId(), ps.volume);
                    }
                }
                return true;
            },

            .SetEntityActive => |sea| {
                if (self.systems.sceneManager) |mgr| {
                    const scene = mgr.currentScene();
                    if (scene.world.findByTag(sea.getEntityTag())) |entity| {
                        scene.world.setActive(entity, sea.active);
                    }
                }
                return true;
            },

            .PauseGame => |pg| {
                if (self.systems.sceneManager) |mgr| {
                    mgr.inputBlocked = pg.paused;
                }
                return true;
            },

            .QuitGame => {
                if (self.systems.onQuit) |handler| {
                    handler();
                } else {
                    rl.closeWindow();
                }
                return true;
            },

            .Custom => |c| {
                if (self.systems.customHandler) |handler| {
                    return handler(c.id, c.data);
                }
                return true;
            },
        }
    }

    pub fn hasEventOfType(self: *const Self, comptime event_type: std.meta.Tag(Event)) bool {
        for (self.events[0..self.count]) |evt| {
            if (std.meta.activeTag(evt) == event_type) return true;
        }
        return false;
    }

    pub fn countEventsOfType(self: *const Self, comptime event_type: std.meta.Tag(Event)) usize {
        var c: usize = 0;
        for (self.events[0..self.count]) |evt| {
            if (std.meta.activeTag(evt) == event_type) c += 1;
        }
        return c;
    }

    /// Iterator for read-only access to pending events
    pub fn iterator(self: *Self) Iterator {
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
};