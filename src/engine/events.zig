const std = @import("std");
const rl = @import("raylib");

pub const MAX_MESSAGE_LEN = 256;

pub const ShowMessage = struct {
    message: [MAX_MESSAGE_LEN]u8 = undefined,
    duration: f32 = 2.0,
    elapsed: f32 = 0.0,
    len: usize = 0,
};

pub const Event = union(enum) {
    ShowMessage: ShowMessage,
};

pub fn showMessage(text: []const u8, duration: f32) Event {
    const len = @min(text.len, MAX_MESSAGE_LEN - 1);
    var msg: ShowMessage = .{ .len = len, .duration = duration, .elapsed = 0.0 };
    @memcpy(msg.message[0..len], text[0..len]);
    msg.message[len] = 0;
    return .{ .ShowMessage = msg };
}

pub const EventQueue = struct {
    events: [128]Event = undefined,
    capacity: usize = 128,
    count: usize = 0,

    pub fn init() EventQueue {
        return EventQueue{ .events = undefined, .capacity = 128, .count = 0 };
    }

    pub fn deinit(self: *EventQueue) void {
        self.count = 0;
        self.capacity = 0;
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

    pub fn isEmpty(self: *EventQueue) bool {
        return self.count == 0;
    }

    pub fn handleEvents(self: *EventQueue, dt: f32) void {
        var i: usize = 0;
        while (i < self.count) {
            switch (self.events[i]) {
                .ShowMessage => |*msg| {
                    msg.elapsed += dt;
                    if (msg.elapsed < msg.duration) {
                        const text = msg.message[0..msg.len :0];
                        rl.drawText(text, 10, 10, 20, .red);
                        i += 1;
                    } else {
                        if (i < self.count - 1) {
                            self.events[i] = self.events[self.count - 1];
                        }
                        self.count -= 1;
                    }
                },
            }
        }
    }
};