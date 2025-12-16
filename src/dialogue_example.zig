const std = @import("std");
const rl = @import("raylib");
const dialogue = @import("engine/dialogue.zig");

// ============================================================================
// Example of using the Dialogue Framework
// ============================================================================

// Example game context
const GameContext = struct {
    player_name: []u8,
    has_key: bool = false,
    reputation: i32 = 0,

    pub fn init(allocator: std.mem.Allocator) !GameContext {
        return .{
            .player_name = try allocator.alloc(u8, 64),
        };
    }
};

// Example condition functions
fn hasKey(ctx: *anyopaque) bool {
    const game_ctx: *GameContext = @ptrCast(@alignCast(ctx));
    return game_ctx.has_key;
}

fn hasGoodReputation(ctx: *anyopaque) bool {
    const game_ctx: *GameContext = @ptrCast(@alignCast(ctx));
    return game_ctx.reputation >= 10;
}

// Example callback functions
fn onPlayerNameEntered(ctx: *anyopaque) void {
    const game_ctx: *GameContext = @ptrCast(@alignCast(ctx));
    std.debug.print("Player entered name: {s}\n", .{game_ctx.player_name});
}

fn onKeyReceived(ctx: *anyopaque) void {
    const game_ctx: *GameContext = @ptrCast(@alignCast(ctx));
    game_ctx.has_key = true;
    std.debug.print("Player received the key!\n", .{});
}

fn onReputationIncreased(ctx: *anyopaque) void {
    const game_ctx: *GameContext = @ptrCast(@alignCast(ctx));
    game_ctx.reputation += 5;
    std.debug.print("Reputation increased to {d}\n", .{game_ctx.reputation});
}

/// Example: Simple linear dialogue
pub fn createSimpleDialogue(allocator: std.mem.Allocator) !dialogue.DialogueSystem {
    var system = try dialogue.DialogueSystem.init(allocator, .{});
    var builder = dialogue.DialogueBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.addText("start", "Knight", "Greetings, traveler! Welcome to our village.", "q1");
    _ = try builder.addText("q1", "Knight", "The weather is quite pleasant today, isn't it?", "end");
    _ = try builder.addEnd("end");

    try builder.build(&system);
    return system;
}

/// Example: Dialogue with choices
pub fn createChoiceDialogue(allocator: std.mem.Allocator) !dialogue.DialogueSystem {
    var system = try dialogue.DialogueSystem.init(allocator, .{});
    var builder = dialogue.DialogueBuilder.init(allocator);
    defer builder.deinit();

    const choices = [_]dialogue.Choice{
        .{ .text = "Tell me about the quest", .next_node_id = "quest_info" },
        .{ .text = "What's your name?", .next_node_id = "name_reveal" },
        .{ .text = "Goodbye", .next_node_id = "end" },
    };

    _ = try builder.addText("start", "Merchant", "Ah, a customer! What can I help you with?", "choice1");
    _ = try builder.addChoice("choice1", "Merchant", "Choose what you'd like to know:", &choices);
    _ = try builder.addText("quest_info", "Merchant", "The quest? It's dangerous, but the reward is great!", "end");
    _ = try builder.addText("name_reveal", "Merchant", "My name is Marcus, the finest merchant in town!", "end");
    _ = try builder.addEnd("end");

    try builder.build(&system);
    return system;
}

/// Example: Dialogue with branching based on conditions
pub fn createBranchingDialogue(allocator: std.mem.Allocator) !dialogue.DialogueSystem {
    var system = try dialogue.DialogueSystem.init(allocator, .{});
    var builder = dialogue.DialogueBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.addText("start", "Guard", "Halt! Do you have the key to enter?", "check_key");
    _ = try builder.addBranch("check_key", hasKey, "has_key", "no_key");
    _ = try builder.addText("has_key", "Guard", "Excellent! You may pass.", "end");
    _ = try builder.addText("no_key", "Guard", "Sorry, you need a key to enter this area.", "end");
    _ = try builder.addEnd("end");

    try builder.build(&system);
    return system;
}

/// Example: Dialogue with player input
pub fn createInputDialogue(allocator: std.mem.Allocator) !dialogue.DialogueSystem {
    var system = try dialogue.DialogueSystem.init(allocator, .{});
    var builder = dialogue.DialogueBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.addText("start", "Wizard", "Welcome, young one. What is your name?", "name_input");
    _ = try builder.addInput("name_input", "Wizard", "Enter your name:", 32, "greeting");
    _ = try builder.addText("greeting", "Wizard", "Nice to meet you! Your destiny awaits.", "end");
    _ = try builder.addEnd("end");

    try builder.build(&system);
    return system;
}

/// Example: Complex dialogue with multiple features
pub fn createComplexDialogue(allocator: std.mem.Allocator) !dialogue.DialogueSystem {
    var system = try dialogue.DialogueSystem.init(allocator, .{
        .typing_speed = 0.03,
        .allow_skip = true,
    });
    var builder = dialogue.DialogueBuilder.init(allocator);
    defer builder.deinit();

    const initial_choices = [_]dialogue.Choice{
        .{ .text = "I need help with a quest", .next_node_id = "quest_path" },
        .{ .text = "I'm just looking around", .next_node_id = "casual_path" },
    };

    const quest_choices = [_]dialogue.Choice{
        .{ .text = "Yes, I'll help!", .next_node_id = "accept_quest" },
        .{ .text = "Maybe later", .next_node_id = "decline_quest" },
    };

    _ = try builder.addText("start", "Elder", "Ah, a new face in our village! What brings you here?", "first_choice");
    _ = try builder.addChoice("first_choice", "Elder", "How may I assist you?", &initial_choices);

    // Quest path
    _ = try builder.addText("quest_path", "Elder", "I see. There is indeed a great danger lurking in the forest...", "quest_explain");
    _ = try builder.addText("quest_explain", "Elder", "We need someone brave to investigate. Will you help us?", "quest_choice");
    _ = try builder.addChoice("quest_choice", "Elder", "What do you say?", &quest_choices);
    _ = try builder.addText("accept_quest", "Elder", "Wonderful! Take this key, it will help you.", "give_key");

    var accept_node = dialogue.DialogueNode{
        .id = "give_key",
        .node_type = .text,
        .character_name = "Elder",
        .text = "May fortune favor you on your journey!",
        .next_node_id = "end",
        .on_complete = onKeyReceived,
    };
    try system.addNode(accept_node);

    _ = try builder.addText("decline_quest", "Elder", "I understand. Come back when you're ready.", "end");

    // Casual path
    _ = try builder.addText("casual_path", "Elder", "Feel free to explore! Our village is peaceful.", "reputation_check");
    _ = try builder.addBranch("reputation_check", hasGoodReputation, "good_rep", "normal_rep");
    _ = try builder.addText("good_rep", "Elder", "I've heard of your good deeds! You're always welcome here.", "end");
    _ = try builder.addText("normal_rep", "Elder", "Safe travels, stranger.", "end");

    _ = try builder.addEnd("end");

    try builder.build(&system);
    return system;
}

/// Main function demonstrating usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize game context
    var game_ctx = try GameContext.init(allocator);
    defer allocator.free(game_ctx.player_name);

    // Create dialogue system
    var system = try createComplexDialogue(allocator);
    defer system.deinit();

    // Initialize window
    rl.initWindow(800, 600, "Dialogue Framework Example");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Start dialogue
    try system.start("start", &game_ctx);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        try system.update();

        // Handle input
        if (system.active) {
            if (system.getCurrentNode()) |node| {
                switch (node.node_type) {
                    .text => {
                        if (rl.isKeyPressed(.key_space) or rl.isKeyPressed(.key_enter)) {
                            if (system.isTypingComplete()) {
                                try system.advance();
                            } else {
                                system.skipTyping();
                            }
                        }
                    },
                    .choice => {
                        if (rl.isKeyPressed(.key_up) or rl.isKeyPressed(.key_w)) {
                            try system.selectPreviousChoice();
                        }
                        if (rl.isKeyPressed(.key_down) or rl.isKeyPressed(.key_s)) {
                            try system.selectNextChoice();
                        }
                        if (rl.isKeyPressed(.key_enter) or rl.isKeyPressed(.key_space)) {
                            if (system.isTypingComplete()) {
                                try system.advance();
                            }
                        }
                    },
                    .input => {
                        // Handle text input
                        const key = rl.getCharPressed();
                        if (key > 0) {
                            const char: u8 = @intCast(key);
                            if (char >= 32 and char <= 126) {
                                system.addInputChar(char);
                            }
                        }

                        if (rl.isKeyPressed(.key_backspace)) {
                            system.removeInputChar();
                        }

                        if (rl.isKeyPressed(.key_enter)) {
                            // Copy input to game context
                            const input = system.getInput();
                            @memcpy(game_ctx.player_name[0..input.len], input);
                            try system.advance();
                        }
                    },
                    else => {},
                }
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.{ .r = 20, .g = 20, .b = 30, .a = 255 });

        // Draw some background elements
        rl.drawText("Dialogue Framework Demo", 20, 20, 20, .{ .r = 200, .g = 200, .b = 200, .a = 255 });

        // Draw dialogue
        try system.draw(50, 400, 700, 150);

        // Draw instructions
        if (system.active) {
            if (system.getCurrentNode()) |node| {
                const instructions = switch (node.node_type) {
                    .text => "Press SPACE or ENTER to continue",
                    .choice => "Use UP/DOWN to select, ENTER to confirm",
                    .input => "Type your answer, press ENTER to submit",
                    else => "",
                };
                rl.drawText(instructions, 60, 560, 12, .{ .r = 150, .g = 150, .b = 150, .a = 255 });
            }
        } else {
            rl.drawText("Dialogue ended. Close window to exit.", 250, 300, 16, .{ .r = 200, .g = 200, .b = 200, .a = 255 });
        }
    }
}

