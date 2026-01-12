const std = @import("std");
const rl = @import("raylib");
const events = @import("../events.zig");

pub const ToastStyle = struct {
    /// Top-left anchor for the first line.
    origin: rl.Vector2 = .{ .x = 10, .y = 10 },

    /// Vertical spacing between messages.
    lineHeight: i32 = 24,

    /// Font size used by raylib.drawText.
    fontSize: i32 = 20,

    /// Text color.
    color: rl.Color = rl.Color.red,

    /// Max number of messages to draw.
    maxLines: usize = 4,
};

/// Draws all active ShowMessage events as simple "toast" text lines.
/// Pure rendering (no state mutation). State is managed by EventQueue.process().
pub fn drawEventQueueToasts(queue: *const events.EventQueue, style: ToastStyle) void {
    var drawn: usize = 0;

    var i: usize = 0;
    while (i < queue.len() and drawn < style.maxLines) : (i += 1) {
        const evt_ptr = queue.peek(i) orelse break;
        switch (evt_ptr.*) {
            .ShowMessage => |msg| {
                if (msg.elapsed >= msg.duration) continue;

                const x: i32 = @as(i32, @intFromFloat(style.origin.x));
                const y0: i32 = @as(i32, @intFromFloat(style.origin.y));
                const y: i32 = y0 + @as(i32, @intCast(drawn)) * style.lineHeight;
                rl.drawText(msg.getText(), x, y, style.fontSize, style.color);
                drawn += 1;
            },
            else => {},
        }
    }
}
