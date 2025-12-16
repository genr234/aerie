const rl = @import("raylib");
const std = @import("std");

pub const ConditionFn = *const fn (ctx: ?*anyopaque) bool;
pub const ActionFn = *const fn (ctx: ?*anyopaque) void;

pub const Option = struct {
    text: []const u8,
    goto: ?[]const u8 = null,
    condition: ?ConditionFn = null,
};

pub const Node = struct {
    tag: Tag,
    speaker: []const u8 = "",
    text: []const u8 = "",
    options: []const Option = &.{},
    goto: ?[]const u8 = null,
    condition: ?ConditionFn = null,
    else_goto: ?[]const u8 = null,
    action: ?ActionFn = null,
    label: ?[]const u8 = null,
    on_enter: ?ActionFn = null,
    on_exit: ?ActionFn = null,
    max_input: usize = 64,

    pub const Tag = enum { say, ask, input, branch, run, done };
};

pub const Script = struct {
    nodes: []const Node,
    labels: std.StringHashMapUnmanaged(usize),
    allocator: std.mem.Allocator,

    pub fn nodeAt(self: Script, idx: usize) ?Node {
        return if (idx < self.nodes.len) self.nodes[idx] else null;
    }

    pub fn findLabel(self: Script, name: []const u8) ?usize {
        return self.labels.get(name);
    }

    pub fn deinit(self: *Script) void {
        self.allocator.free(self.nodes);
        self.labels.deinit(self.allocator);
    }
};

pub const Builder = struct {
    nodes: std.array_list.Managed(Node),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .nodes = std.array_list.Managed(Node).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Builder) void {
        self.nodes.deinit();
    }

    pub fn say(self: *Builder, speaker: []const u8, text: []const u8) *Builder {
        self.nodes.append(.{ .tag = .say, .speaker = speaker, .text = text }) catch {};
        return self;
    }

    pub fn ask(self: *Builder, speaker: []const u8, prompt: []const u8, options: []const Option) *Builder {
        self.nodes.append(.{ .tag = .ask, .speaker = speaker, .text = prompt, .options = options }) catch {};
        return self;
    }

    pub fn input(self: *Builder, speaker: []const u8, prompt: []const u8, max_len: usize) *Builder {
        self.nodes.append(.{ .tag = .input, .speaker = speaker, .text = prompt, .max_input = max_len }) catch {};
        return self;
    }

    pub fn branch(self: *Builder, condition: ConditionFn, then_goto: []const u8, else_goto: []const u8) *Builder {
        self.nodes.append(.{ .tag = .branch, .condition = condition, .goto = then_goto, .else_goto = else_goto }) catch {};
        return self;
    }

    pub fn run(self: *Builder, action: ActionFn) *Builder {
        self.nodes.append(.{ .tag = .run, .action = action }) catch {};
        return self;
    }

    pub fn label(self: *Builder, name: []const u8) *Builder {
        self.nodes.append(.{ .tag = .say, .text = "", .label = name }) catch {};
        return self;
    }

    pub fn goto(self: *Builder, target: []const u8) *Builder {
        if (self.nodes.items.len > 0) {
            self.nodes.items[self.nodes.items.len - 1].goto = target;
        }
        return self;
    }

    pub fn onEnter(self: *Builder, cb: ActionFn) *Builder {
        if (self.nodes.items.len > 0) {
            self.nodes.items[self.nodes.items.len - 1].on_enter = cb;
        }
        return self;
    }

    pub fn onExit(self: *Builder, cb: ActionFn) *Builder {
        if (self.nodes.items.len > 0) {
            self.nodes.items[self.nodes.items.len - 1].on_exit = cb;
        }
        return self;
    }

    pub fn done(self: *Builder) *Builder {
        self.nodes.append(.{ .tag = .done }) catch {};
        return self;
    }

    pub fn build(self: *Builder) !Script {
        var labels = std.StringHashMapUnmanaged(usize){};
        for (self.nodes.items, 0..) |node, i| {
            if (node.label) |lbl| {
                try labels.put(self.allocator, lbl, i);
            }
        }
        return .{
            .nodes = try self.allocator.dupe(Node, self.nodes.items),
            .labels = labels,
            .allocator = self.allocator,
        };
    }
};

pub const Runner = struct {
    script: *const Script,
    allocator: std.mem.Allocator,
    context: ?*anyopaque = null,
    index: usize = 0,
    phase: Phase = .inactive,
    chars_shown: usize = 0,
    type_timer: f64 = 0,
    type_speed: f64 = 0.035,
    choice_idx: usize = 0,
    available: std.array_list.Managed(usize),
    input_buf: [256]u8 = undefined,
    input_len: usize = 0,
    event_handler: ?*const fn (Event, *Runner) void = null,

    pub const Phase = enum { inactive, typing, waiting, choosing, inputting, finished };
    pub const Event = enum { started, node_entered, typing_complete, choice_made, input_submitted, finished };

    pub fn init(allocator: std.mem.Allocator, script: *const Script) Runner {
        return .{
            .script = script,
            .allocator = allocator,
            .available = std.array_list.Managed(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Runner) void {
        self.available.deinit();
    }

    pub fn start(self: *Runner, ctx: ?*anyopaque) void {
        self.context = ctx;
        self.index = 0;
        self.phase = .inactive;
        self.enterNode();
        self.emit(.started);
    }

    pub fn stop(self: *Runner) void {
        self.phase = .finished;
        self.emit(.finished);
    }

    pub fn update(self: *Runner, dt: f64) void {
        if (self.phase != .typing) return;
        self.type_timer += dt;
        while (self.type_timer >= self.type_speed) {
            self.type_timer -= self.type_speed;
            self.chars_shown += 1;
            if (self.currentNode()) |node| {
                if (self.chars_shown >= node.text.len) {
                    self.finishTyping(node);
                    break;
                }
            }
        }
    }

    pub fn skip(self: *Runner) void {
        if (self.phase != .typing) return;
        if (self.currentNode()) |node| {
            self.chars_shown = node.text.len;
            self.finishTyping(node);
        }
    }

    pub fn advance(self: *Runner) void {
        switch (self.phase) {
            .waiting => self.advanceFrom(self.currentNode()),
            .choosing => self.confirmChoice(),
            .inputting => self.confirmInput(),
            else => {},
        }
    }

    pub fn selectUp(self: *Runner) void {
        if (self.phase == .choosing and self.choice_idx > 0) {
            self.choice_idx -= 1;
        }
    }

    pub fn selectDown(self: *Runner) void {
        if (self.phase == .choosing and self.choice_idx + 1 < self.available.items.len) {
            self.choice_idx += 1;
        }
    }

    pub fn typeChar(self: *Runner, c: u8) void {
        if (self.phase != .inputting) return;
        if (self.currentNode()) |node| {
            if (self.input_len < node.max_input and self.input_len < self.input_buf.len - 1) {
                self.input_buf[self.input_len] = c;
                self.input_len += 1;
            }
        }
    }

    pub fn backspace(self: *Runner) void {
        if (self.phase == .inputting and self.input_len > 0) {
            self.input_len -= 1;
        }
    }

    pub fn isActive(self: *const Runner) bool {
        return self.phase != .inactive and self.phase != .finished;
    }

    pub fn currentNode(self: *const Runner) ?Node {
        return self.script.nodeAt(self.index);
    }

    pub fn displayText(self: *const Runner) []const u8 {
        if (self.currentNode()) |n| {
            return n.text[0..@min(self.chars_shown, n.text.len)];
        }
        return "";
    }

    pub fn inputText(self: *const Runner) []const u8 {
        return self.input_buf[0..self.input_len];
    }

    pub fn selectedChoice(self: *const Runner) ?usize {
        if (self.available.items.len > 0) return self.available.items[self.choice_idx];
        return null;
    }

    fn enterNode(self: *Runner) void {
        const node = self.script.nodeAt(self.index) orelse {
            self.phase = .finished;
            self.emit(.finished);
            return;
        };
        if (node.on_enter) |cb| cb(self.context);
        self.emit(.node_entered);
        switch (node.tag) {
            .say => {
                if (node.text.len == 0 and node.label != null) {
                    self.index += 1;
                    self.enterNode();
                } else {
                    self.resetTyping();
                }
            },
            .ask => {
                self.resetTyping();
                self.updateChoices(node);
            },
            .input => {
                self.input_len = 0;
                self.chars_shown = node.text.len;
                self.phase = .inputting;
            },
            .branch => {
                const result = if (node.condition) |c| c(self.context) else false;
                const target = if (result) node.goto else node.else_goto;
                self.jumpTo(target);
            },
            .run => {
                if (node.action) |a| a(self.context);
                self.index += 1;
                self.enterNode();
            },
            .done => {
                self.phase = .finished;
                self.emit(.finished);
            },
        }
    }

    fn finishTyping(self: *Runner, node: Node) void {
        self.phase = if (node.tag == .ask) .choosing else .waiting;
        self.emit(.typing_complete);
    }

    fn resetTyping(self: *Runner) void {
        self.chars_shown = 0;
        self.type_timer = 0;
        self.phase = .typing;
    }

    fn updateChoices(self: *Runner, node: Node) void {
        self.available.clearRetainingCapacity();
        self.choice_idx = 0;
        for (node.options, 0..) |opt, i| {
            const ok = if (opt.condition) |c| c(self.context) else true;
            if (ok) self.available.append(i) catch {};
        }
    }

    fn advanceFrom(self: *Runner, maybe_node: ?Node) void {
        if (maybe_node) |node| {
            if (node.on_exit) |cb| cb(self.context);
            self.jumpTo(node.goto);
        }
    }

    fn confirmChoice(self: *Runner) void {
        if (self.currentNode()) |node| {
            if (node.on_exit) |cb| cb(self.context);
            if (self.choice_idx < self.available.items.len) {
                const opt = node.options[self.available.items[self.choice_idx]];
                self.emit(.choice_made);
                self.jumpTo(opt.goto);
            }
        }
    }

    fn confirmInput(self: *Runner) void {
        if (self.currentNode()) |node| {
            if (node.on_exit) |cb| cb(self.context);
            self.emit(.input_submitted);
            self.jumpTo(node.goto);
        }
    }

    fn jumpTo(self: *Runner, target: ?[]const u8) void {
        if (target) |lbl| {
            if (self.script.findLabel(lbl)) |idx| {
                self.index = idx;
                self.enterNode();
                return;
            }
        }
        self.index += 1;
        self.enterNode();
    }

    fn emit(self: *Runner, event: Event) void {
        if (self.event_handler) |h| h(event, self);
    }
};

pub const Style = struct {
    bg_color: rl.Color = .{ .r = 45, .g = 40, .b = 50, .a = 255 },
    border_color: rl.Color = .{ .r = 210, .g = 180, .b = 140, .a = 255 },
    text_color: rl.Color = .{ .r = 245, .g = 245, .b = 235, .a = 255 },
    sub_text_color: rl.Color = .{ .r = 180, .g = 180, .b = 190, .a = 255 },

    highlight_bg: rl.Color = .{ .r = 210, .g = 180, .b = 140, .a = 255 },
    highlight_text: rl.Color = .{ .r = 40, .g = 35, .b = 45, .a = 255 },

    font_size: i32 = 20,
    padding: f32 = 16.0,
    roundness: f32 = 0.15,
    segments: i32 = 6,
    border_thick: f32 = 3.0,
};

pub fn draw(runner: *const Runner, bounds: rl.Rectangle, style: Style) void {
    if (!runner.isActive()) return;
    const node = runner.currentNode() orelse return;

    var name_rect = rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const has_speaker = (node.speaker.len > 0);

    if (has_speaker) {
        const name_w = measureText(node.speaker, style.font_size);
        const h = @as(f32, @floatFromInt(style.font_size)) + style.padding;

        name_rect = rl.Rectangle{
            .x = bounds.x + 10,
            .y = bounds.y - h + style.border_thick,
            .width = @as(f32, @floatFromInt(name_w)) + style.padding * 3,
            .height = h,
        };
    }

    var choice_rect = rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const is_choosing = (node.tag == .ask and runner.phase == .choosing);
    const item_h = @as(f32, @floatFromInt(style.font_size)) + style.padding;

    if (is_choosing) {
        var max_w: i32 = 0;
        for (runner.available.items) |opt_idx| {
            const w = measureText(node.options[opt_idx].text, style.font_size);
            if (w > max_w) max_w = w;
        }

        const total_h = @as(f32, @floatFromInt(runner.available.items.len)) * item_h + style.padding;
        const panel_w = @as(f32, @floatFromInt(max_w)) + style.padding * 4;

        choice_rect = rl.Rectangle{
            .x = (bounds.x + bounds.width) - panel_w - 10,
            .y = bounds.y - total_h + style.border_thick,
            .width = panel_w,
            .height = total_h
        };
    }
    if (has_speaker) {
        drawAttachedTab(name_rect, style);
    }

    if (is_choosing) {
        drawAttachedTab(choice_rect, style);
    }

    drawMainBox(bounds, style);

    if (has_speaker) {
        drawTextEx(node.speaker, name_rect.x + style.padding * 1.5, name_rect.y + style.padding/2, style.font_size, style.border_color);
    }

    drawTextEx(runner.displayText(), bounds.x + style.padding, bounds.y + style.padding, style.font_size, style.text_color);

    if (is_choosing) {
        var current_y = choice_rect.y + style.padding/2;

        for (runner.available.items, 0..) |opt_idx, i| {
            const is_sel = (i == runner.choice_idx);

            if (is_sel) {
                const pill = rl.Rectangle{
                    .x = choice_rect.x + style.padding/2,
                    .y = current_y,
                    .width = choice_rect.width - style.padding,
                    .height = item_h
                };
                rl.drawRectangleRounded(pill, 0.3, 4, style.highlight_bg);
            }

            const col = if (is_sel) style.highlight_text else style.sub_text_color;
            drawTextEx(node.options[opt_idx].text, choice_rect.x + style.padding * 1.5, current_y + style.padding/2, style.font_size, col);

            current_y += item_h;
        }
    }

    if (node.tag == .input) {
        const field_y = bounds.y + bounds.height - style.padding * 3;
        rl.drawRectangleRounded(
            .{ .x = bounds.x + style.padding, .y = field_y, .width = bounds.width - style.padding*2, .height = style.padding * 2 },
            0.2, 4, rl.Color{ .r=0, .g=0, .b=0, .a=60 }
        );
        drawTextEx(runner.inputText(), bounds.x + style.padding * 2, field_y + style.padding/2, style.font_size, style.text_color);
        if (@mod(@as(i32, @intFromFloat(rl.getTime() * 2)), 2) == 0) {
            const txt_w = measureText(runner.inputText(), style.font_size);
            rl.drawRectangle(
                @intFromFloat(bounds.x + style.padding * 2 + @as(f32, @floatFromInt(txt_w)) + 2),
                @intFromFloat(field_y + style.padding/2),
                2, style.font_size, style.border_color
            );
        }
    }
}


fn drawMainBox(rect: rl.Rectangle, style: Style) void {
    rl.drawRectangleRounded(
        .{ .x = rect.x + 4, .y = rect.y + 4, .width = rect.width, .height = rect.height },
        style.roundness, style.segments, rl.Color{ .r=0, .g=0, .b=0, .a=100 }
    );
    rl.drawRectangleRounded(rect, style.roundness, style.segments, style.border_color);
    const inner = rl.Rectangle{
        .x = rect.x + style.border_thick, .y = rect.y + style.border_thick,
        .width = rect.width - style.border_thick*2, .height = rect.height - style.border_thick*2
    };
    rl.drawRectangleRounded(inner, style.roundness, style.segments, style.bg_color);
}

fn drawAttachedTab(rect: rl.Rectangle, style: Style) void {
    rl.drawRectangleRounded(rect, style.roundness, style.segments, style.border_color);

    const inner = rl.Rectangle{
        .x = rect.x + style.border_thick, .y = rect.y + style.border_thick,
        .width = rect.width - style.border_thick*2, .height = rect.height - style.border_thick*2
    };
    rl.drawRectangleRounded(inner, style.roundness, style.segments, style.bg_color);

    rl.drawRectangle(
        @intFromFloat(rect.x + style.border_thick),
        @intFromFloat(rect.y + rect.height - style.border_thick * 2),
        @intFromFloat(rect.width - style.border_thick * 2),
        @intFromFloat(style.border_thick * 2),
        style.bg_color
    );
}

fn drawTextEx(text: []const u8, x: f32, y: f32, size: i32, color: rl.Color) void {
    if (text.len == 0) return;
    var buf: [1024:0]u8 = undefined;
    const len = @min(text.len, 1023);
    @memcpy(buf[0..len], text[0..len]);
    buf[len] = 0;
    rl.drawText(&buf, @intFromFloat(x), @intFromFloat(y), size, color);
}

fn measureText(text: []const u8, size: i32) i32 {
    if (text.len == 0) return 0;
    var buf: [1024:0]u8 = undefined;
    const len = @min(text.len, 1023);
    @memcpy(buf[0..len], text[0..len]);
    buf[len] = 0;
    return rl.measureText(&buf, size);
}