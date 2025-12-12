const rl = @import("raylib");
const root = @import("../root.zig");
const std = @import("std");

pub const Dialogue = struct {
    lines: [][]const u8,
    character_name: []const u8 = "Unknown",
    index: usize = 0,
    active: bool = false,
    line_start_time: f64 = 0.0,
    typing_speed: f64 = 0.05,

    pub fn init(lines: [][]const u8, character_name: []const u8) Dialogue {
        return Dialogue{
            .lines = lines,
            .character_name = character_name,
            .index = 0,
            .active = false,
        };
    }

    pub fn initWithName(lines: [][]const u8, character_name: []const u8) Dialogue {
        return Dialogue{
            .lines = lines,
            .character_name = character_name,
            .index = 0,
            .active = false,
        };
    }

    pub fn start(self: *Dialogue) void {
        self.active = true;
        self.index = 0;
        self.line_start_time = rl.getTime();
    }

    pub fn advance(self: *Dialogue) void {
        if (self.active) {
            self.index += 1;
            if (self.index >= self.lines.len) {
                self.active = false;
            } else {
                self.line_start_time = rl.getTime();
            }
        }
    }

    pub fn current(self: *const Dialogue) ?[]const u8 {
        if (self.active and self.index < self.lines.len) {
            return self.lines[self.index];
        }
        return null;
    }

    pub fn getDisplayedText(self: *const Dialogue, allocator: std.mem.Allocator) ?[]u8 {
        if (self.current()) |text| {
            const elapsed = rl.getTime() - self.line_start_time;
            const char_count = @as(usize, @intFromFloat(elapsed / self.typing_speed));
            const display_len = @min(char_count, text.len);

            const displayed = allocator.dupe(u8, text[0..display_len]) catch return null;
            return displayed;
        }
        return null;
    }

    pub fn isLineComplete(self: *const Dialogue) bool {
        if (self.current()) |text| {
            const elapsed = rl.getTime() - self.line_start_time;
            const char_count = @as(usize, @intFromFloat(elapsed / self.typing_speed));
            return char_count >= text.len;
        }
        return true;
    }

    pub fn draw(self: *const Dialogue, x: i32, y: i32, width: i32, height: i32) void {
        if (!self.active) return;

        const border_width: i32 = 3;
        const padding: i32 = 12;

        // Draw semi-transparent dark background
        rl.drawRectangle(x, y, width, height, .{ .r = 15, .g = 15, .b = 25, .a = 240 });

        // Draw gradient-like effect with a lighter inner border
        rl.drawRectangleLinesEx(.{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(width), .height = @floatFromInt(height) }, border_width, .{ .r = 255, .g = 200, .b = 87, .a = 255 });

        var name_buf: [64:0]u8 = undefined;
        @memcpy(name_buf[0..self.character_name.len], self.character_name);
        name_buf[self.character_name.len] = 0;
        rl.drawText(name_buf[0..self.character_name.len :0], x + padding, y + padding, 13, .{ .r = 200, .g = 180, .b = 100, .a = 200 });

        // Draw dialogue text
        if (self.current()) |text| {
            const elapsed = rl.getTime() - self.line_start_time;
            const char_count = @as(usize, @intFromFloat(elapsed / self.typing_speed));
            const display_len = @min(char_count, text.len);

            var buf: [512:0]u8 = undefined;
            @memcpy(buf[0..display_len], text[0..display_len]);
            buf[display_len] = 0;

            rl.drawText(buf[0..display_len :0], x + padding, y + padding + 22, 16, .{ .r = 230, .g = 230, .b = 230, .a = 255 });
        }

        const frame = @mod(root.I32(@divTrunc(rl.getTime() * 1000, 500)), 2);
        if (frame == 0) {
            rl.drawText("▼", x + width - 25, y + height - 25, 16, .{ .r = 255, .g = 200, .b = 87, .a = 255 });
        }
    }
};