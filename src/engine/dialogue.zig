const rl = @import("raylib");

pub const Dialogue = struct {
    lines: [][]const u8,
    index: usize = 0,
    active: bool = false,

    pub fn init(lines: [][]const u8) Dialogue {
        return Dialogue{
            .lines = lines,
            .index = 0,
            .active = false,
        };
    }

    pub fn start(self: *Dialogue) void {
        self.active = true;
        self.index = 0;
    }

    pub fn advance(self: *Dialogue) void {
        if (self.active) {
            self.index += 1;
            if (self.index >= self.lines.len) {
                self.active = false;
            }
        }
    }

    pub fn current(self: *const Dialogue) ?[]const u8 {
        if (self.active and self.index < self.lines.len) {
            return self.lines[self.index];
        }
        return null;
    }

    pub fn draw(self: *const Dialogue, x: i32, y: i32, width: i32, height: i32) void {
        if (!self.active) return;

        rl.drawRectangle(x, y, width, height, .{ .r = 20, .g = 20, .b = 20, .a = 220 });

        rl.drawRectangleLinesEx(.{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(width), .height = @floatFromInt(height) }, 2, .gold);

        if (self.current()) |text| {
            var buf: [512:0]u8 = undefined;
            @memcpy(buf[0..text.len], text);
            buf[text.len] = 0;

            rl.drawText(buf[0..text.len :0], x + 10, y + 10, 18, .white);
        }
    }
};