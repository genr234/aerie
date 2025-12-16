const rl = @import("raylib");
const root = @import("../root.zig");
const std = @import("std");

pub const NodeType = enum {
    text,      // simple text display with typing effect
    choice,    // multiple choice selection
    input,     // text input from user
    branch,    // conditional branching
    end,       // end of dialogue
};

pub const Choice = struct {
    text: []const u8,
    next_node_id: []const u8,
    condition: ?*const fn (ctx: *anyopaque) bool = null,
};

pub const ConditionFn = *const fn (ctx: *anyopaque) bool;

pub const CallbackFn = *const fn (ctx: *anyopaque) void;

pub const DialogueNode = struct {
    id: []const u8,
    node_type: NodeType,

    character_name: []const u8 = "Unknown",
    text: []const u8 = "",
    next_node_id: ?[]const u8 = null,

    choices: []const Choice = &[_]Choice{},

    condition: ?ConditionFn = null,
    branch_true: ?[]const u8 = null,
    branch_false: ?[]const u8 = null,

    input_prompt: []const u8 = "",
    input_max_length: usize = 64,
    input_validator: ?*const fn (input: []const u8, ctx: *anyopaque) bool = null,

    on_enter: ?CallbackFn = null,
    on_complete: ?CallbackFn = null,
};

pub const DialogueConfig = struct {
    typing_speed: f64 = 0.05,
    allow_skip: bool = true,
    auto_advance_delay: f64 = 0.0,

    box_color: rl.Color = .{ .r = 15, .g = 15, .b = 25, .a = 240 },
    border_color: rl.Color = .{ .r = 255, .g = 200, .b = 87, .a = 255 },
    text_color: rl.Color = .{ .r = 230, .g = 230, .b = 230, .a = 255 },
    name_color: rl.Color = .{ .r = 200, .g = 180, .b = 100, .a = 200 },
    choice_color: rl.Color = .{ .r = 180, .g = 180, .b = 180, .a = 255 },
    choice_selected_color: rl.Color = .{ .r = 255, .g = 200, .b = 87, .a = 255 },
};

pub const DialogueSystem = struct {
    allocator: std.mem.Allocator,
    nodes: std.StringHashMap(DialogueNode),
    current_node_id: ?[]const u8 = null,
    active: bool = false,

    line_start_time: f64 = 0.0,
    chars_displayed: usize = 0,
    typing_complete: bool = false,

    selected_choice: usize = 0,

    input_buffer: [256]u8 = undefined,
    input_length: usize = 0,

    context: ?*anyopaque = null,
    config: DialogueConfig,

    history: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator, config: DialogueConfig) !DialogueSystem {
        return DialogueSystem{
            .allocator = allocator,
            .nodes = std.StringHashMap(DialogueNode).init(allocator),
            .config = config,
            .history = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *DialogueSystem) void {
        self.nodes.deinit();
        self.history.deinit();
    }

    pub fn addNode(self: *DialogueSystem, node: DialogueNode) !void {
        try self.nodes.put(node.id, node);
    }

    /// Simple convenience method to add a text node
    pub fn text(self: *DialogueSystem, id: []const u8, speaker: []const u8, content: []const u8, next: ?[]const u8) !void {
        try self.addNode(.{
            .id = id,
            .node_type = .text,
            .character_name = speaker,
            .text = content,
            .next_node_id = next,
        });
    }

    /// Add a choice node with multiple options
    pub fn choice(self: *DialogueSystem, id: []const u8, speaker: []const u8, prompt: []const u8, options: []const Choice) !void {
        try self.addNode(.{
            .id = id,
            .node_type = .choice,
            .character_name = speaker,
            .text = prompt,
            .choices = options,
        });
    }

    /// Add an input node for user text input
    pub fn input(self: *DialogueSystem, id: []const u8, speaker: []const u8, prompt: []const u8, max_len: usize, next: ?[]const u8) !void {
        try self.addNode(.{
            .id = id,
            .node_type = .input,
            .character_name = speaker,
            .input_prompt = prompt,
            .input_max_length = max_len,
            .next_node_id = next,
        });
    }

    /// Add a branch node for conditional logic
    pub fn branch(self: *DialogueSystem, id: []const u8, condition: ConditionFn, true_path: []const u8, false_path: []const u8) !void {
        try self.addNode(.{
            .id = id,
            .node_type = .branch,
            .condition = condition,
            .branch_true = true_path,
            .branch_false = false_path,
        });
    }

    /// Add an end node
    pub fn end(self: *DialogueSystem, id: []const u8) !void {
        try self.addNode(.{
            .id = id,
            .node_type = .end,
        });
    }

    pub fn start(self: *DialogueSystem, starting_node_id: []const u8, context: ?*anyopaque) !void {
        if (!self.nodes.contains(starting_node_id)) {
            return error.NodeNotFound;
        }

        self.active = true;
        self.current_node_id = starting_node_id;
        self.context = context;
        self.selected_choice = 0;
        self.input_length = 0;
        self.history.clearRetainingCapacity();

        try self.enterCurrentNode();
    }

    pub fn stop(self: *DialogueSystem) void {
        self.active = false;
        self.current_node_id = null;
    }

    pub fn getCurrentNode(self: *const DialogueSystem) ?DialogueNode {
        if (self.current_node_id) |id| {
            return self.nodes.get(id);
        }
        return null;
    }


fn enterCurrentNode(self: *DialogueSystem) anyerror!void {
    if (self.getCurrentNode()) |node| {
        self.line_start_time = rl.getTime();
        self.chars_displayed = 0;
        self.typing_complete = false;
        self.selected_choice = 0;

        try self.history.append(node.id);

        if (node.on_enter) |callback| {
            if (self.context) |ctx| {
                callback(ctx);
            }
        }

        if (node.node_type == .branch) {
            try self.handleBranch();
        }
    }
}

fn handleBranch(self: *DialogueSystem) anyerror!void {
    if (self.getCurrentNode()) |node| {
        if (node.condition) |cond| {
            const result = if (self.context) |ctx| cond(ctx) else false;

            const next_id = if (result) node.branch_true else node.branch_false;

            if (next_id) |id| {
                self.current_node_id = id;
                try self.enterCurrentNode();
            } else {
                self.stop();
            }
        } else {
            self.stop();
        }
    }
}

    /// Update typing effect
    pub fn update(self: *DialogueSystem) !void {
        if (!self.active) return;

        if (self.getCurrentNode()) |node| {
            if (node.node_type == .text or node.node_type == .choice) {
                const elapsed = rl.getTime() - self.line_start_time;
                self.chars_displayed = @intFromFloat(elapsed / self.config.typing_speed);

                const text_len = if (node.node_type == .text) node.text.len else node.text.len;
                if (self.chars_displayed >= text_len) {
                    self.chars_displayed = text_len;
                    self.typing_complete = true;
                }
            }
        }
    }

    pub fn isTypingComplete(self: *const DialogueSystem) bool {
        return self.typing_complete;
    }

    pub fn skipTyping(self: *DialogueSystem) void {
        if (!self.config.allow_skip) return;

        if (self.getCurrentNode()) |node| {
            if (node.node_type == .text or node.node_type == .choice) {
                self.chars_displayed = if (node.node_type == .text) node.text.len else node.text.len;
                self.typing_complete = true;
            }
        }
    }

    pub fn advance(self: *DialogueSystem) !void {
        if (!self.active) return;

        if (self.getCurrentNode()) |node| {
            // Call on_complete callback
            if (node.on_complete) |callback| {
                if (self.context) |ctx| {
                    callback(ctx);
                }
            }

            switch (node.node_type) {
                .text => {
                    if (node.next_node_id) |next_id| {
                        self.current_node_id = next_id;
                        try self.enterCurrentNode();
                    } else {
                        self.stop();
                    }
                },
                .choice => {
                    // Get available choices (filter by condition)
                    const available = try self.getAvailableChoices();
                    defer self.allocator.free(available);

                    if (self.selected_choice < available.len) {
                        const selected_option = available[self.selected_choice];
                        self.current_node_id = selected_option.next_node_id;
                        try self.enterCurrentNode();
                    }
                },
                .input => {
                    // Validate input if validator exists
                    if (node.input_validator) |validator| {
                        if (self.context) |ctx| {
                            if (!validator(self.getInput(), ctx)) {
                                return; // Invalid input, don't advance
                            }
                        }
                    }

                    if (node.next_node_id) |next_id| {
                        self.current_node_id = next_id;
                        try self.enterCurrentNode();
                    } else {
                        self.stop();
                    }
                },
                .end => {
                    self.stop();
                },
                .branch => {
                    // Already handled in enterCurrentNode
                },
            }
        }
    }

    fn getAvailableChoices(self: *const DialogueSystem) ![]Choice {
        if (self.getCurrentNode()) |node| {
            if (node.node_type == .choice) {
                var available = std.array_list.Managed(Choice).init(self.allocator);

                for (node.choices) |choice_opt| {
                    if (choice_opt.condition) |cond| {
                        if (self.context) |ctx| {
                            if (cond(ctx)) {
                                try available.append(choice_opt);
                            }
                        }
                    } else {
                        try available.append(choice_opt);
                    }
                }

                return available.toOwnedSlice();
            }
        }
        return &[_]Choice{};
    }

    pub fn selectPreviousChoice(self: *DialogueSystem) !void {
        if (self.getCurrentNode()) |node| {
            if (node.node_type == .choice) {
                const available = try self.getAvailableChoices();
                defer self.allocator.free(available);

                if (available.len > 0) {
                    if (self.selected_choice == 0) {
                        self.selected_choice = available.len - 1;
                    } else {
                        self.selected_choice -= 1;
                    }
                }
            }
        }
    }

    pub fn selectNextChoice(self: *DialogueSystem) !void {
        if (self.getCurrentNode()) |node| {
            if (node.node_type == .choice) {
                const available = try self.getAvailableChoices();
                defer self.allocator.free(available);

                if (available.len > 0) {
                    self.selected_choice = (self.selected_choice + 1) % available.len;
                }
            }
        }
    }

    pub fn addInputChar(self: *DialogueSystem, char: u8) void {
        if (self.getCurrentNode()) |node| {
            if (node.node_type == .input) {
                if (self.input_length < node.input_max_length and self.input_length < self.input_buffer.len) {
                    self.input_buffer[self.input_length] = char;
                    self.input_length += 1;
                }
            }
        }
    }

    pub fn removeInputChar(self: *DialogueSystem) void {
        if (self.input_length > 0) {
            self.input_length -= 1;
        }
    }

    pub fn getInput(self: *const DialogueSystem) []const u8 {
        return self.input_buffer[0..self.input_length];
    }

    pub fn clearInput(self: *DialogueSystem) void {
        self.input_length = 0;
    }

    pub fn draw(self: *DialogueSystem, x: i32, y: i32, width: i32, height: i32) !void {
        if (!self.active) return;

        const border_width: i32 = 3;
        const padding: i32 = 12;

        rl.drawRectangle(x, y, width, height, self.config.box_color);

        rl.drawRectangleLinesEx(
            .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(width), .height = @floatFromInt(height) },
            border_width,
            self.config.border_color
        );

        if (self.getCurrentNode()) |node| {
            var name_buf: [64:0]u8 = undefined;
            const name_len = @min(node.character_name.len, 63);
            @memcpy(name_buf[0..name_len], node.character_name[0..name_len]);
            name_buf[name_len] = 0;
            rl.drawText(name_buf[0..name_len :0], x + padding, y + padding, 13, self.config.name_color);

            switch (node.node_type) {
                .text => try self.drawTextNode(node, x, y, width, height, padding),
                .choice => try self.drawChoiceNode(node, x, y, padding),
                .input => try self.drawInputNode(node, x, y, width, height, padding),
                .end => {},
                .branch => {},
            }
        }
    }

    fn drawTextNode(self: *const DialogueSystem, node: DialogueNode, x: i32, y: i32, width: i32, height: i32, padding: i32) !void {
        const display_len = @min(self.chars_displayed, node.text.len);

        var buf: [512:0]u8 = undefined;
        const safe_len = @min(display_len, 511);
        @memcpy(buf[0..safe_len], node.text[0..safe_len]);
        buf[safe_len] = 0;

        rl.drawText(buf[0..safe_len :0], x + padding, y + padding + 22, 16, self.config.text_color);

        if (self.typing_complete) {
            const frame = @mod(root.I32(@divTrunc(rl.getTime() * 1000, 500)), 2);
            if (frame == 0) {
                rl.drawText("▼", x + width - 25, y + height - 25, 16, self.config.border_color);
            }
        }
    }

    fn drawChoiceNode(self: *DialogueSystem, node: DialogueNode, x: i32, y: i32, padding: i32) !void {
        const display_len = @min(self.chars_displayed, node.text.len);
        var text_buf: [512:0]u8 = undefined;
        const safe_len = @min(display_len, 511);
        @memcpy(text_buf[0..safe_len], node.text[0..safe_len]);
        text_buf[safe_len] = 0;
        rl.drawText(text_buf[0..safe_len :0], x + padding, y + padding + 22, 16, self.config.text_color);

        if (self.typing_complete) {
            const available = try self.getAvailableChoices();
            defer self.allocator.free(available);

            var choice_y: i32 = y + padding + 50;
            for (available, 0..) |choice_opt, i| {
                const is_selected = i == self.selected_choice;
                const color = if (is_selected) self.config.choice_selected_color else self.config.choice_color;

                var choice_buf: [256:0]u8 = undefined;
                const prefix = if (is_selected) "> " else "  ";
                @memcpy(choice_buf[0..prefix.len], prefix);
                const choice_len = @min(choice_opt.text.len, 250);
                @memcpy(choice_buf[prefix.len..prefix.len + choice_len], choice_opt.text[0..choice_len]);
                choice_buf[prefix.len + choice_len] = 0;

                rl.drawText(choice_buf[0..prefix.len + choice_len :0], x + padding + 10, choice_y, 14, color);
                choice_y += 25;
            }
        }
    }

    fn drawInputNode(self: *const DialogueSystem, node: DialogueNode, x: i32, y: i32, width: i32, _: i32, padding: i32) !void {
        // Draw prompt
        var prompt_buf: [512:0]u8 = undefined;
        const prompt_len = @min(node.input_prompt.len, 511);
        @memcpy(prompt_buf[0..prompt_len], node.input_prompt[0..prompt_len]);
        prompt_buf[prompt_len] = 0;
        rl.drawText(prompt_buf[0..prompt_len :0], x + padding, y + padding + 22, 16, self.config.text_color);

        const input_y = y + padding + 50;
        const input_height: i32 = 30;
        rl.drawRectangle(x + padding, input_y, width - padding * 2, input_height, .{ .r = 30, .g = 30, .b = 40, .a = 255 });
        rl.drawRectangleLinesEx(
            .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(input_y), .width = @floatFromInt(width - padding * 2), .height = @floatFromInt(input_height) },
            1.0,
            self.config.border_color
        );

        var input_buf: [256:0]u8 = undefined;
        const input_len = @min(self.input_length, 255);
        @memcpy(input_buf[0..input_len], self.input_buffer[0..input_len]);
        input_buf[input_len] = 0;
        rl.drawText(input_buf[0..input_len :0], x + padding + 5, input_y + 7, 14, .{ .r = 255, .g = 255, .b = 255, .a = 255 });

        const frame = @mod(root.I32(@divTrunc(rl.getTime() * 1000, 500)), 2);
        if (frame == 0) {
            const cursor_x = x + padding + 5 + @as(i32, @intCast(input_len)) * 8;
            rl.drawText("_", cursor_x, input_y + 7, 14, self.config.border_color);
        }
    }
};

pub const DialogueBuilder = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(DialogueNode),

    pub fn init(allocator: std.mem.Allocator) DialogueBuilder {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(DialogueNode).init(allocator),
        };
    }

    pub fn deinit(self: *DialogueBuilder) void {
        self.nodes.deinit();
    }

    pub fn addText(self: *DialogueBuilder, id: []const u8, character: []const u8, text: []const u8, next: ?[]const u8) !*DialogueBuilder {
        try self.nodes.append(.{
            .id = id,
            .node_type = .text,
            .character_name = character,
            .text = text,
            .next_node_id = next,
        });
        return self;
    }

    pub fn addChoice(self: *DialogueBuilder, id: []const u8, character: []const u8, prompt: []const u8, choices: []const Choice) !*DialogueBuilder {
        try self.nodes.append(.{
            .id = id,
            .node_type = .choice,
            .character_name = character,
            .text = prompt,
            .choices = choices,
        });
        return self;
    }

    pub fn addInput(self: *DialogueBuilder, id: []const u8, character: []const u8, prompt: []const u8, max_len: usize, next: ?[]const u8) !*DialogueBuilder {
        try self.nodes.append(.{
            .id = id,
            .node_type = .input,
            .character_name = character,
            .input_prompt = prompt,
            .input_max_length = max_len,
            .next_node_id = next,
        });
        return self;
    }

    pub fn addBranch(self: *DialogueBuilder, id: []const u8, condition: ConditionFn, branch_true: []const u8, branch_false: []const u8) !*DialogueBuilder {
        try self.nodes.append(.{
            .id = id,
            .node_type = .branch,
            .condition = condition,
            .branch_true = branch_true,
            .branch_false = branch_false,
        });
        return self;
    }

    pub fn addEnd(self: *DialogueBuilder, id: []const u8) !*DialogueBuilder {
        try self.nodes.append(.{
            .id = id,
            .node_type = .end,
        });
        return self;
    }

    pub fn build(self: *DialogueBuilder, system: *DialogueSystem) !void {
        for (self.nodes.items) |node| {
            try system.addNode(node);
        }
    }
};
