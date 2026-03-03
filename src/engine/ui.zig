const std = @import("std");
const rl = @import("raylib");

/// Simple immediate-mode UI for Bitsy/Pico-8 style games.
/// No layout engine, just coordinate-based positioning.
/// Call these functions every frame in your draw callback.
/// Global input state - persists across frames
pub const InputState = struct {
    text_buffer: [256]u8 = [_]u8{0} ** 256,
    text_len: usize = 0,
    focused_id: u32 = 0,
    cursor_visible: bool = true,
    cursor_timer: f32 = 0,
};

/// Global input state instance
pub var input_state: InputState = .{};

pub const UI = struct {
    /// Screen anchors for easy positioning
    pub const Anchor = enum {
        top_left,
        top_right,
        top_center,
        center,
        bottom_left,
        bottom_right,
        bottom_center,
    };

    /// Get screen position for an anchor
    pub fn anchorPos(a: Anchor) rl.Vector2 {
        const w: f32 = @floatFromInt(rl.getScreenWidth());
        const h: f32 = @floatFromInt(rl.getScreenHeight());
        return switch (a) {
            .top_left => .{ .x = 0, .y = 0 },
            .top_right => .{ .x = w, .y = 0 },
            .top_center => .{ .x = w / 2, .y = 0 },
            .center => .{ .x = w / 2, .y = h / 2 },
            .bottom_left => .{ .x = 0, .y = h },
            .bottom_right => .{ .x = w, .y = h },
            .bottom_center => .{ .x = w / 2, .y = h },
        };
    }

    /// Reset input state (call when starting a new input session)
    pub fn resetInput() void {
        input_state.text_len = 0;
        input_state.text_buffer[0] = 0;
        input_state.focused_id = 0;
    }

    /// Clear the current input text
    pub fn clearInput() void {
        input_state.text_len = 0;
        input_state.text_buffer[0] = 0;
    }

    /// Get the current input text
    pub fn getInputText() [:0]const u8 {
        return input_state.text_buffer[0..input_state.text_len :0];
    }

    /// Set the current input text
    pub fn setInputText(new_text: []const u8) void {
        const len = @min(new_text.len, input_state.text_buffer.len - 1);
        @memcpy(input_state.text_buffer[0..len], new_text[0..len]);
        input_state.text_len = len;
        input_state.text_buffer[len] = 0;
    }

    /// Draw a button, returns true if clicked this frame
    pub fn button(x: f32, y: f32, w: f32, h: f32, label: [:0]const u8) bool {
        return buttonStyled(x, y, w, h, label, .{});
    }

    /// Button with custom style
    pub fn buttonStyled(x: f32, y: f32, w: f32, h: f32, label: [:0]const u8, style: ButtonStyle) bool {
        const rect = rl.Rectangle{ .x = x, .y = y, .width = w, .height = h };
        const mouse = rl.getMousePosition();
        const hovered = rl.checkCollisionPointRec(mouse, rect);
        const pressed = rl.isMouseButtonPressed(.left);

        // Draw button
        const default_color = rl.Color{ .r = 60, .g = 60, .b = 80, .a = 255 };
        const default_hover = rl.Color{ .r = 80, .g = 80, .b = 100, .a = 255 };
        const bg = if (hovered) style.hover_color orelse default_hover else style.color orelse default_color;
        rl.drawRectangleRec(rect, bg);

        if (style.border_color) |border| {
            rl.drawRectangleLinesEx(rect, 2, border);
        }

        // Draw label centered
        if (label.len > 0) {
            const font_size = style.font_size orelse 16;
            const text_w = rl.measureText(label, font_size);
            const text_x: i32 = @intFromFloat(x + (w - @as(f32, @floatFromInt(text_w))) / 2);
            const text_y: i32 = @intFromFloat(y + (h - @as(f32, @floatFromInt(font_size))) / 2);
            rl.drawText(label, text_x, text_y, font_size, style.text_color orelse rl.Color.white);
        }

        return hovered and pressed;
    }

    /// Draw simple text
    pub fn text(x: f32, y: f32, content: [:0]const u8) void {
        textStyled(x, y, content, .{});
    }

    /// Text with style
    pub fn textStyled(x: f32, y: f32, content: [:0]const u8, style: TextStyle) void {
        const color = style.color orelse rl.Color.white;
        const font_size = style.font_size orelse 16;
        rl.drawText(content, @intFromFloat(x), @intFromFloat(y), font_size, color);
    }

    /// Draw a panel/background rectangle
    pub fn panel(x: f32, y: f32, w: f32, h: f32) void {
        panelStyled(x, y, w, h, .{});
    }

    /// Panel with style
    pub fn panelStyled(x: f32, y: f32, w: f32, h: f32, style: PanelStyle) void {
        const rect = rl.Rectangle{ .x = x, .y = y, .width = w, .height = h };
        rl.drawRectangleRec(rect, style.color orelse rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 });

        if (style.border_color) |border| {
            rl.drawRectangleLinesEx(rect, style.border_width orelse 1, border);
        }
    }

    /// Draw a progress/health bar
    pub fn bar(x: f32, y: f32, w: f32, h: f32, value: f32, max_value: f32) void {
        barStyled(x, y, w, h, value, max_value, .{});
    }

    /// Progress bar with style
    pub fn barStyled(x: f32, y: f32, w: f32, h: f32, value: f32, max_value: f32, style: BarStyle) void {
        const rect = rl.Rectangle{ .x = x, .y = y, .width = w, .height = h };

        // Background
        rl.drawRectangleRec(rect, style.background_color orelse rl.Color{ .r = 50, .g = 50, .b = 50, .a = 255 });

        // Fill
        const fill_ratio = std.math.clamp(value / @max(max_value, 0.001), 0, 1);
        const fill_w = w * fill_ratio;
        const fill_rect = rl.Rectangle{ .x = x, .y = y, .width = fill_w, .height = h };
        rl.drawRectangleRec(fill_rect, style.fill_color orelse rl.Color.green);

        // Border
        if (style.border_color) |border| {
            rl.drawRectangleLinesEx(rect, 1, border);
        }
    }

    /// Text input field - returns true if Enter was pressed (text submitted)
    /// Use `getInputText()` to retrieve the entered text after submission
    /// field_id: unique ID for this field (used to track focus when multiple fields exist)
    pub fn inputField(x: f32, y: f32, w: f32, h: f32, field_id: u32) bool {
        return inputFieldStyled(x, y, w, h, field_id, .{});
    }

    /// Text input field with custom style
    pub fn inputFieldStyled(x: f32, y: f32, w: f32, h: f32, field_id: u32, style: InputFieldStyle) bool {
        const rect = rl.Rectangle{ .x = x, .y = y, .width = w, .height = h };
        const mouse = rl.getMousePosition();
        const hovered = rl.checkCollisionPointRec(mouse, rect);
        const clicked = rl.isMouseButtonPressed(.left);

        // Handle focus
        if (clicked) {
            if (hovered) {
                input_state.focused_id = field_id;
            } else if (input_state.focused_id == field_id) {
                input_state.focused_id = 0; // Lose focus when clicking elsewhere
            }
        }

        const is_focused = input_state.focused_id == field_id;
        var submitted = false;

        // Handle keyboard input when focused
        if (is_focused) {
            // Update cursor blink
            input_state.cursor_timer += rl.getFrameTime();
            if (input_state.cursor_timer >= 0.5) {
                input_state.cursor_timer = 0;
                input_state.cursor_visible = !input_state.cursor_visible;
            }

            // Handle key presses
            const key = rl.getCharPressed();
            if (key != 0 and input_state.text_len < input_state.text_buffer.len - 1) {
                // Only accept printable ASCII characters
                if (key >= 32 and key <= 126) {
                    input_state.text_buffer[input_state.text_len] = @intCast(key);
                    input_state.text_len += 1;
                    input_state.text_buffer[input_state.text_len] = 0;
                }
            }

            // Handle backspace
            if (rl.isKeyPressed(.backspace) and input_state.text_len > 0) {
                input_state.text_len -= 1;
                input_state.text_buffer[input_state.text_len] = 0;
            }

            // Handle Enter (submit)
            if (rl.isKeyPressed(.enter)) {
                submitted = true;
            }
        }

        // Draw background
        const bg_color = style.background_color orelse rl.Color{ .r = 30, .g = 30, .b = 40, .a = 255 };
        rl.drawRectangleRec(rect, bg_color);

        // Draw border (highlighted when focused)
        const border_color = if (is_focused)
            style.focus_border_color orelse rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 }
        else
            style.border_color orelse rl.Color{ .r = 80, .g = 80, .b = 100, .a = 255 };
        rl.drawRectangleLinesEx(rect, 2, border_color);

        // Draw text
        const font_size = style.font_size orelse 16;
        const text_color = style.text_color orelse rl.Color.white;
        const padding = style.padding orelse 8;

        // Get display text
        const display_text = input_state.text_buffer[0..input_state.text_len :0];

        // Draw text with cursor
        if (is_focused) {
            // Draw existing text
            if (input_state.text_len > 0) {
                rl.drawText(display_text, @intFromFloat(x + padding), @intFromFloat(y + (h - @as(f32, @floatFromInt(font_size))) / 2), font_size, text_color);
            }

            // Draw cursor
            if (input_state.cursor_visible) {
                const text_width = rl.measureText(display_text, font_size);
                const cursor_x = x + padding + @as(f32, @floatFromInt(text_width)) + 2;
                rl.drawLineEx(
                    .{ .x = cursor_x, .y = y + 4 },
                    .{ .x = cursor_x, .y = y + h - 4 },
                    2,
                    text_color,
                );
            }
        } else {
            // Not focused - just show text
            if (input_state.text_len > 0) {
                rl.drawText(display_text, @intFromFloat(x + padding), @intFromFloat(y + (h - @as(f32, @floatFromInt(font_size))) / 2), font_size, text_color);
            } else {
                // Show placeholder
                if (style.placeholder) |placeholder| {
                    const placeholder_color = style.placeholder_color orelse rl.Color{ .r = 100, .g = 100, .b = 100, .a = 255 };
                    rl.drawText(placeholder, @intFromFloat(x + padding), @intFromFloat(y + (h - @as(f32, @floatFromInt(font_size))) / 2), font_size, placeholder_color);
                }
            }
        }

        return submitted;
    }

    /// Draw a simple toast/notification message (fades out near end)
    pub fn toast(message: [:0]const u8, y: f32, duration: f32, elapsed: f32, style: ToastStyle) void {
        if (elapsed >= duration) return;

        const alpha: u8 = if (elapsed > duration - 0.5)
            @intFromFloat(255 * (duration - elapsed) / 0.5)
        else
            255;

        const font_size = style.font_size orelse 16;
        const text_w = rl.measureText(message, font_size);
        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const x: i32 = @intFromFloat((screen_w - @as(f32, @floatFromInt(text_w))) / 2);

        const color = rl.Color{
            .r = style.color.r,
            .g = style.color.g,
            .b = style.color.b,
            .a = alpha,
        };

        rl.drawText(message, x, @intFromFloat(y), font_size, color);
    }

    /// Show a simple vertical menu and return selected index (-1 if nothing selected)
    pub fn menu(x: f32, y: f32, options: []const [:0]const u8, style: MenuStyle) i32 {
        var selected: i32 = -1;
        const btn_h = style.button_height orelse 30;
        const gap = style.gap orelse 4;

        for (options, 0..) |opt, i| {
            const btn_y = y + @as(f32, @floatFromInt(i)) * (btn_h + gap);
            if (button(x, btn_y, style.button_width orelse 150, btn_h, opt)) {
                selected = @intCast(i);
            }
        }

        return selected;
    }

    /// Draw a simple dialogue box with text
    pub fn dialogueBox(x: f32, y: f32, w: f32, h: f32, text_content: [:0]const u8, style: DialogueBoxStyle) void {
        // Background panel
        panelStyled(x, y, w, h, .{
            .color = style.background_color orelse rl.Color{ .r = 0, .g = 0, .b = 0, .a = 200 },
            .border_color = style.border_color orelse rl.Color.white,
            .border_width = 2,
        });

        // Text with padding
        const padding = style.padding orelse 10;
        textStyled(x + padding, y + padding, text_content, .{
            .color = style.text_color orelse rl.Color.white,
            .font_size = style.font_size orelse 16,
        });
    }

    /// Center a rectangle at an anchor point
    pub fn centeredAt(w: f32, h: f32, a: Anchor, offset_x: f32, offset_y: f32) rl.Vector2 {
        const pos = anchorPos(a);
        return .{
            .x = pos.x - w / 2 + offset_x,
            .y = pos.y - h / 2 + offset_y,
        };
    }
};

// ============================================================================
// Style structs
// ============================================================================

pub const ButtonStyle = struct {
    color: ?rl.Color = rl.Color{ .r = 60, .g = 60, .b = 80, .a = 255 },
    hover_color: ?rl.Color = rl.Color{ .r = 80, .g = 80, .b = 100, .a = 255 },
    border_color: ?rl.Color = rl.Color{ .r = 100, .g = 100, .b = 120, .a = 255 },
    text_color: ?rl.Color = rl.Color.white,
    font_size: ?i32 = 16,
};

pub const TextStyle = struct {
    color: ?rl.Color = rl.Color.white,
    font_size: ?i32 = 16,
};

pub const PanelStyle = struct {
    color: ?rl.Color = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 },
    border_color: ?rl.Color = null,
    border_width: ?f32 = 1,
};

pub const BarStyle = struct {
    fill_color: ?rl.Color = rl.Color.green,
    background_color: ?rl.Color = rl.Color{ .r = 50, .g = 50, .b = 50, .a = 255 },
    border_color: ?rl.Color = rl.Color.white,
};

pub const ToastStyle = struct {
    font_size: ?i32 = 20,
    color: rl.Color = rl.Color.white,
};

pub const MenuStyle = struct {
    button_width: ?f32 = 150,
    button_height: ?f32 = 30,
    gap: ?f32 = 4,
};

pub const DialogueBoxStyle = struct {
    background_color: ?rl.Color = null,
    border_color: ?rl.Color = null,
    text_color: ?rl.Color = null,
    font_size: ?i32 = null,
    padding: ?f32 = null,
};

pub const InputFieldStyle = struct {
    background_color: ?rl.Color = null,
    border_color: ?rl.Color = null,
    focus_border_color: ?rl.Color = null,
    text_color: ?rl.Color = null,
    placeholder_color: ?rl.Color = null,
    placeholder: ?[:0]const u8 = null,
    font_size: ?i32 = null,
    padding: ?f32 = null,
};
