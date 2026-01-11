const std = @import("std");
const rl = @import("raylib");
const dialogue = @import("dialogue.zig");
const story = @import("story.zig");
const events = @import("events.zig");
const audio = @import("audio.zig");

pub const MAX_CHARACTERS = 8;
pub const MAX_NAME_LEN = 32;

pub const Position = enum {
    left,
    center,
    right,
    far_left,
    far_right,
    off_left,
    off_right,

    pub fn toX(self: Position, screen_width: f32, sprite_width: f32) f32 {
        return switch (self) {
            .off_left => -sprite_width,
            .far_left => screen_width * 0.1,
            .left => screen_width * 0.25 - sprite_width / 2,
            .center => screen_width * 0.5 - sprite_width / 2,
            .right => screen_width * 0.75 - sprite_width / 2,
            .far_right => screen_width * 0.9 - sprite_width / 2,
            .off_right => screen_width,
        };
    }
};

pub const TransitionType = enum {
    none,
    fade,
    dissolve,
    slide_left,
    slide_right,
    slide_up,
    slide_down,
};

pub const Transition = struct {
    type: TransitionType = .none,
    duration: f32 = 0.5,
    elapsed: f32 = 0.0,

    pub fn progress(self: *const Transition) f32 {
        if (self.duration <= 0) return 1.0;
        return std.math.clamp(self.elapsed / self.duration, 0.0, 1.0);
    }

    pub fn isComplete(self: *const Transition) bool {
        return self.elapsed >= self.duration;
    }

    pub fn update(self: *Transition, dt: f32) void {
        self.elapsed += dt;
    }

    pub fn reset(self: *Transition) void {
        self.elapsed = 0.0;
    }
};

pub const CharacterSprite = struct {
    name: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN,
    nameLen: usize = 0,

    texture: ?rl.Texture2D = null,
    position: Position = .center,
    customX: ?f32 = null,
    yOffset: f32 = 0,

    visible: bool = true,
    alpha: f32 = 1.0,
    scale: f32 = 1.0,
    tint: rl.Color = rl.Color.white,

    targetAlpha: f32 = 1.0,
    targetX: f32 = 0,
    currentX: f32 = 0,
    transition: Transition = .{},

    speaking: bool = false,
    dimWhenNotSpeaking: bool = true,

    pub fn init(name: []const u8) CharacterSprite {
        var char = CharacterSprite{};
        const len = @min(name.len, MAX_NAME_LEN - 1);
        @memcpy(char.name[0..len], name[0..len]);
        char.name[len] = 0;
        char.nameLen = len;
        return char;
    }

    pub fn getName(self: *const CharacterSprite) []const u8 {
        return self.name[0..self.nameLen];
    }

    pub fn matches(self: *const CharacterSprite, name: []const u8) bool {
        if (self.nameLen != name.len) return false;
        return std.mem.eql(u8, self.name[0..self.nameLen], name);
    }

    pub fn setTexture(self: *CharacterSprite, tex: rl.Texture2D) void {
        self.texture = tex;
    }

    pub fn show(self: *CharacterSprite, pos: Position, transition_type: TransitionType, duration: f32) void {
        self.visible = true;
        self.position = pos;
        self.targetAlpha = 1.0;
        self.transition = .{ .type = transition_type, .duration = duration };

        if (transition_type == .fade or transition_type == .dissolve) {
            self.alpha = 0.0;
        }
    }

    pub fn hide(self: *CharacterSprite, transition_type: TransitionType, duration: f32) void {
        self.targetAlpha = 0.0;
        self.transition = .{ .type = transition_type, .duration = duration };
    }

    pub fn moveTo(self: *CharacterSprite, pos: Position, duration: f32) void {
        self.position = pos;
        self.transition = .{ .type = .slide_left, .duration = duration }; // direction determined by target
    }

    pub fn update(self: *CharacterSprite, dt: f32, screen_width: f32) void {
        if (!self.visible and self.alpha <= 0) return;

        self.transition.update(dt);
        const progress = self.transition.progress();

        if (self.alpha != self.targetAlpha) {
            self.alpha = lerp(self.alpha, self.targetAlpha, progress);
            if (self.transition.isComplete()) {
                self.alpha = self.targetAlpha;
                if (self.alpha <= 0) {
                    self.visible = false;
                }
            }
        }

        const sprite_w: f32 = if (self.texture) |t| @floatFromInt(t.width) else 100;
        self.targetX = if (self.customX) |x| x else self.position.toX(screen_width, sprite_w * self.scale);

        if (@abs(self.currentX - self.targetX) > 1) {
            self.currentX = lerp(self.currentX, self.targetX, progress);
        } else {
            self.currentX = self.targetX;
        }
    }

    pub fn draw(self: *const CharacterSprite, screen_height: f32) void {
        if (!self.visible or self.alpha <= 0) return;
        const tex = self.texture orelse return;

        const sprite_h: f32 = @floatFromInt(tex.height);
        const y = screen_height - sprite_h * self.scale - self.yOffset;

        var final_alpha = self.alpha;
        if (self.dimWhenNotSpeaking and !self.speaking) {
            final_alpha *= 0.7;
        }

        const tint_with_alpha = rl.Color{
            .r = self.tint.r,
            .g = self.tint.g,
            .b = self.tint.b,
            .a = @intFromFloat(final_alpha * 255.0),
        };

        const src = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(tex.width),
            .height = @floatFromInt(tex.height),
        };

        const dest = rl.Rectangle{
            .x = self.currentX,
            .y = y,
            .width = @as(f32, @floatFromInt(tex.width)) * self.scale,
            .height = sprite_h * self.scale,
        };

        rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0, tint_with_alpha);
    }
};

pub const Background = struct {
    texture: ?rl.Texture2D = null,
    color: rl.Color = rl.Color.black,
    alpha: f32 = 1.0,

    nextTexture: ?rl.Texture2D = null,
    transition: Transition = .{},
    transitioning: bool = false,

    pub fn set(self: *Background, tex: rl.Texture2D, transition_type: TransitionType, duration: f32) void {
        if (duration <= 0 or transition_type == .none) {
            self.texture = tex;
            self.transitioning = false;
        } else {
            self.nextTexture = tex;
            self.transition = .{ .type = transition_type, .duration = duration };
            self.transitioning = true;
        }
    }

    pub fn setColor(self: *Background, col: rl.Color) void {
        self.texture = null;
        self.color = col;
        self.transitioning = false;
    }

    pub fn update(self: *Background, dt: f32) void {
        if (!self.transitioning) return;

        self.transition.update(dt);

        if (self.transition.isComplete()) {
            self.texture = self.nextTexture;
            self.nextTexture = null;
            self.transitioning = false;
        }
    }

    pub fn draw(self: *const Background, width: i32, height: i32) void {
        const w: f32 = @floatFromInt(width);
        const h: f32 = @floatFromInt(height);

        if (self.transitioning) {
            const progress = self.transition.progress();

            if (self.texture) |tex| {
                const old_alpha: u8 = @intFromFloat((1.0 - progress) * 255.0 * self.alpha);
                drawBackgroundTexture(tex, w, h, old_alpha);
            } else {
                var col = self.color;
                col.a = @intFromFloat((1.0 - progress) * 255.0 * self.alpha);
                rl.drawRectangle(0, 0, width, height, col);
            }

            if (self.nextTexture) |tex| {
                const new_alpha: u8 = @intFromFloat(progress * 255.0 * self.alpha);
                drawBackgroundTexture(tex, w, h, new_alpha);
            }
        } else {
            if (self.texture) |tex| {
                const a: u8 = @intFromFloat(self.alpha * 255.0);
                drawBackgroundTexture(tex, w, h, a);
            } else {
                var col = self.color;
                col.a = @intFromFloat(self.alpha * 255.0);
                rl.drawRectangle(0, 0, width, height, col);
            }
        }
    }
};

fn drawBackgroundTexture(tex: rl.Texture2D, width: f32, height: f32, alpha: u8) void {
    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(tex.width),
        .height = @floatFromInt(tex.height),
    };

    const dest = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = width,
        .height = height,
    };

    const tint = rl.Color{ .r = 255, .g = 255, .b = 255, .a = alpha };
    rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0, tint);
}

pub const EffectType = enum {
    none,
    fade_in,
    fade_out,
    flash,
    shake,
};

pub const ScreenEffect = struct {
    type: EffectType = .none,
    duration: f32 = 0.0,
    elapsed: f32 = 0.0,
    intensity: f32 = 1.0,
    color: rl.Color = rl.Color.black,

    pub fn start(effect_type: EffectType, duration: f32, intensity: f32) ScreenEffect {
        return .{
            .type = effect_type,
            .duration = duration,
            .intensity = intensity,
        };
    }

    pub fn startWithColor(effect_type: EffectType, duration: f32, col: rl.Color) ScreenEffect {
        return .{
            .type = effect_type,
            .duration = duration,
            .color = col,
        };
    }

    pub fn update(self: *ScreenEffect, dt: f32) void {
        if (self.type == .none) return;
        self.elapsed += dt;
        if (self.elapsed >= self.duration) {
            self.type = .none;
        }
    }

    pub fn progress(self: *const ScreenEffect) f32 {
        if (self.duration <= 0) return 1.0;
        return std.math.clamp(self.elapsed / self.duration, 0.0, 1.0);
    }

    pub fn isActive(self: *const ScreenEffect) bool {
        return self.type != .none;
    }

    pub fn getShakeOffset(self: *const ScreenEffect) rl.Vector2 {
        if (self.type != .shake) return .{ .x = 0, .y = 0 };
        const remaining = 1.0 - self.progress();
        const magnitude = self.intensity * remaining * 10.0;
        // Simple pseudo-random shake
        const t = self.elapsed * 50.0;
        return .{
            .x = @sin(t) * magnitude,
            .y = @cos(t * 1.3) * magnitude,
        };
    }

    pub fn draw(self: *const ScreenEffect, width: i32, height: i32) void {
        switch (self.type) {
            .fade_in => {
                const alpha: u8 = @intFromFloat((1.0 - self.progress()) * 255.0);
                var col = self.color;
                col.a = alpha;
                rl.drawRectangle(0, 0, width, height, col);
            },
            .fade_out => {
                const alpha: u8 = @intFromFloat(self.progress() * 255.0);
                var col = self.color;
                col.a = alpha;
                rl.drawRectangle(0, 0, width, height, col);
            },
            .flash => {
                const alpha: u8 = @intFromFloat((1.0 - self.progress()) * self.intensity * 255.0);
                var col = self.color;
                col.a = alpha;
                rl.drawRectangle(0, 0, width, height, col);
            },
            else => {},
        }
    }
};

pub const VNCommandType = enum {
    show_character,
    hide_character,
    move_character,
    set_background,
    play_music,
    stop_music,
    play_sound,
    fade_in,
    fade_out,
    flash,
    shake,
    set_flag,
    wait,
};

/// Command data passed to VN action callbacks
pub const VNCommand = struct {
    cmd_type: VNCommandType,
    /// Character/asset name
    target: []const u8 = "",
    /// Position for characters
    position: Position = .center,
    /// Duration for transitions/effects
    duration: f32 = 0.5,
    /// Volume for audio
    volume: f32 = 1.0,
    /// Intensity for effects
    intensity: f32 = 1.0,
    /// Flag value for set_flag
    flag_value: bool = true,
};

/// Global VN state reference for action callbacks
var global_vn_state: ?*VNState = null;

/// Set the global VN state for action callbacks
pub fn setGlobalVNState(state: *VNState) void {
    global_vn_state = state;
}

/// Clear the global VN state
pub fn clearGlobalVNState() void {
    global_vn_state = null;
}

/// Execute a VN command on the global state
pub fn executeCommand(cmd: VNCommand) void {
    const state = global_vn_state orelse return;

    switch (cmd.cmd_type) {
        .show_character => {
            if (state.getCharacter(cmd.target)) |char| {
                char.show(cmd.position, .fade, cmd.duration);
            }
        },
        .hide_character => {
            if (state.getCharacter(cmd.target)) |char| {
                char.hide(.fade, cmd.duration);
            }
        },
        .move_character => {
            if (state.getCharacter(cmd.target)) |char| {
                char.moveTo(cmd.position, cmd.duration);
            }
        },
        .set_background => {
            // Background requires texture - this needs asset system integration
            // For now, just set color
            state.setBackgroundColor(rl.Color.dark_gray);
        },
        .play_music => {
            state.playMusic(cmd.target);
        },
        .stop_music => {
            state.stopMusic(cmd.duration);
        },
        .play_sound => {
            state.playSoundVolume(cmd.target, cmd.volume);
        },
        .fade_in => {
            state.fadeIn(cmd.duration);
        },
        .fade_out => {
            state.fadeOut(cmd.duration);
        },
        .flash => {
            state.flash(cmd.duration, rl.Color.white);
        },
        .shake => {
            state.shake(cmd.duration, cmd.intensity);
        },
        .set_flag => {
            if (state.storyState) |ss| {
                ss.setFlag(cmd.target, cmd.flag_value);
            }
        },
        .wait => {
            // Wait is handled by dialogue timing, not here
        },
    }
}

pub const VNState = struct {
    const Self = @This();

    // Display dimensions
    width: i32 = 800,
    height: i32 = 450,

    // Visual elements
    background: Background = .{},
    characters: [MAX_CHARACTERS]CharacterSprite = undefined,
    characterCount: usize = 0,

    // Dialogue system
    dialogueRunner: ?*dialogue.Runner = null,
    dialogueStyle: dialogue.Style = .{},
    textboxBounds: rl.Rectangle = undefined,

    // Game state references
    storyState: ?*story.StoryState = null,
    eventQueue: ?*events.EventQueue = null,
    audioManager: ?*audio.AudioManager = null,

    // Screen effects
    effect: ScreenEffect = .{},

    // Auto-advance mode
    autoMode: bool = false,
    autoDelay: f32 = 2.0,
    autoTimer: f32 = 0.0,

    // Skip mode
    skipMode: bool = false,
    skipDelay: f32 = 0.05,
    skipTimer: f32 = 0.0,

    // Text sound (typing beep)
    textSound: ?[]const u8 = null,
    lastCharsShown: usize = 0,

    // Waiting for input indicator
    waitingIndicatorTimer: f32 = 0.0,
    showWaitingIndicator: bool = false,

    pub fn init(width: i32, height: i32) Self {
        var state = Self{
            .width = width,
            .height = height,
        };

        const padding: f32 = 20;
        const box_height: f32 = 150;
        state.textboxBounds = .{
            .x = padding,
            .y = @as(f32, @floatFromInt(height)) - box_height - padding,
            .width = @as(f32, @floatFromInt(width)) - padding * 2,
            .height = box_height,
        };

        for (&state.characters) |*c| {
            c.* = CharacterSprite{};
        }

        return state;
    }

    pub fn setDialogueRunner(self: *Self, runner: *dialogue.Runner) void {
        self.dialogueRunner = runner;
    }

    pub fn setStoryState(self: *Self, state: *story.StoryState) void {
        self.storyState = state;
    }

    pub fn setEventQueue(self: *Self, queue: *events.EventQueue) void {
        self.eventQueue = queue;
    }

    pub fn setAudioManager(self: *Self, mgr: *audio.AudioManager) void {
        self.audioManager = mgr;
    }

    /// Set the sound to play when typing text
    pub fn setTextSound(self: *Self, soundId: []const u8) void {
        self.textSound = soundId;
    }

    pub fn setBackground(self: *Self, tex: rl.Texture2D) void {
        self.background.set(tex, .none, 0);
    }

    pub fn setBackgroundWithTransition(self: *Self, tex: rl.Texture2D, trans: TransitionType, duration: f32) void {
        self.background.set(tex, trans, duration);
    }

    pub fn setBackgroundColor(self: *Self, col: rl.Color) void {
        self.background.setColor(col);
    }

    pub fn addCharacter(self: *Self, name: []const u8) ?*CharacterSprite {
        if (self.characterCount >= MAX_CHARACTERS) return null;

        self.characters[self.characterCount] = CharacterSprite.init(name);
        const char = &self.characters[self.characterCount];
        self.characterCount += 1;
        return char;
    }

    pub fn getCharacter(self: *Self, name: []const u8) ?*CharacterSprite {
        for (self.characters[0..self.characterCount]) |*c| {
            if (c.matches(name)) return c;
        }
        return null;
    }

    pub fn showCharacter(self: *Self, name: []const u8, pos: Position) void {
        if (self.getCharacter(name)) |c| {
            c.show(pos, .fade, 0.3);
        }
    }

    pub fn hideCharacter(self: *Self, name: []const u8) void {
        if (self.getCharacter(name)) |c| {
            c.hide(.fade, 0.3);
        }
    }

    pub fn hideAllCharacters(self: *Self) void {
        for (self.characters[0..self.characterCount]) |*c| {
            c.hide(.fade, 0.3);
        }
    }

    pub fn setSpeaker(self: *Self, name: []const u8) void {
        for (self.characters[0..self.characterCount]) |*c| {
            c.speaking = c.matches(name);
        }
    }

    pub fn clearSpeaker(self: *Self) void {
        for (self.characters[0..self.characterCount]) |*c| {
            c.speaking = false;
        }
    }

    pub fn fadeIn(self: *Self, duration: f32) void {
        self.effect = ScreenEffect.start(.fade_in, duration, 1.0);
    }

    pub fn fadeOut(self: *Self, duration: f32) void {
        self.effect = ScreenEffect.start(.fade_out, duration, 1.0);
    }

    pub fn flash(self: *Self, duration: f32, col: rl.Color) void {
        self.effect = ScreenEffect.startWithColor(.flash, duration, col);
    }

    pub fn shake(self: *Self, duration: f32, intensity: f32) void {
        self.effect = ScreenEffect.start(.shake, duration, intensity);
    }

    /// Play background music
    pub fn playMusic(self: *Self, id: []const u8) void {
        if (self.audioManager) |mgr| {
            mgr.playMusic(id);
        }
    }

    /// Play music with fade-in
    pub fn playMusicFadeIn(self: *Self, id: []const u8, duration: f32) void {
        if (self.audioManager) |mgr| {
            mgr.playMusicFadeIn(id, duration);
        }
    }

    /// Stop music with optional fade-out
    pub fn stopMusic(self: *Self, fade_duration: f32) void {
        if (self.audioManager) |mgr| {
            if (fade_duration > 0) {
                mgr.fadeOutMusic(fade_duration);
            } else {
                mgr.stopMusic();
            }
        }
    }

    /// Play a sound effect
    pub fn playSound(self: *Self, id: []const u8) void {
        if (self.audioManager) |mgr| {
            mgr.playSoundDefault(id);
        }
    }

    /// Play a sound effect with volume
    pub fn playSoundVolume(self: *Self, id: []const u8, volume: f32) void {
        if (self.audioManager) |mgr| {
            mgr.playSound(id, volume);
        }
    }

    /// Play ambient/looping sound
    pub fn playAmbient(self: *Self, id: []const u8, volume: f32) void {
        if (self.audioManager) |mgr| {
            mgr.playSoundLooped(id, volume);
        }
    }

    /// Stop ambient/looping sound
    pub fn stopAmbient(self: *Self, id: []const u8) void {
        if (self.audioManager) |mgr| {
            mgr.stopLoopedSound(id);
        }
    }

    /// Stop all ambient sounds
    pub fn stopAllAmbient(self: *Self) void {
        if (self.audioManager) |mgr| {
            mgr.stopAllLoopedSounds();
        }
    }

    pub fn startDialogue(self: *Self) void {
        if (self.dialogueRunner) |runner| {
            runner.start(null);
        }
    }

    pub fn isDialogueActive(self: *const Self) bool {
        if (self.dialogueRunner) |runner| {
            return runner.isActive();
        }
        return false;
    }

    pub fn update(self: *Self, dt: f32) void {
        // Update background transition
        self.background.update(dt);

        // Update characters
        const screen_w: f32 = @floatFromInt(self.width);
        for (self.characters[0..self.characterCount]) |*c| {
            c.update(dt, screen_w);
        }

        // Update effects
        self.effect.update(dt);

        // Update waiting indicator animation
        self.waitingIndicatorTimer += dt;
        if (self.waitingIndicatorTimer >= 0.5) {
            self.waitingIndicatorTimer = 0;
            self.showWaitingIndicator = !self.showWaitingIndicator;
        }

        // Update audio manager
        if (self.audioManager) |mgr| {
            mgr.update(dt);
        }

        // Update dialogue
        if (self.dialogueRunner) |runner| {
            runner.update(@floatCast(dt));

            // Play text sound when new characters appear
            if (self.textSound) |soundId| {
                if (self.audioManager) |mgr| {
                    if (runner.chars_shown > self.lastCharsShown) {
                        // Play sound every few characters to avoid spam
                        if (runner.chars_shown % 3 == 0) {
                            mgr.playSound(soundId, 0.3);
                        }
                    }
                }
            }
            self.lastCharsShown = runner.chars_shown;

            // Update speaker highlight based on current dialogue
            if (runner.currentNode()) |node| {
                if (node.speaker.len > 0) {
                    self.setSpeaker(node.speaker);
                } else {
                    self.clearSpeaker();
                }
            }

            // Auto mode
            if (self.autoMode and runner.phase == .waiting) {
                self.autoTimer += dt;
                if (self.autoTimer >= self.autoDelay) {
                    self.autoTimer = 0;
                    runner.advance();
                }
            }

            // Skip mode
            if (self.skipMode) {
                self.skipTimer += dt;
                if (self.skipTimer >= self.skipDelay) {
                    self.skipTimer = 0;
                    runner.skip();
                    runner.advance();
                }
            }
        }
    }

    pub fn draw(self: *Self) void {
        // Apply shake offset
        const shake_offset = self.effect.getShakeOffset();
        if (self.effect.type == .shake) {
            rl.beginMode2D(.{
                .offset = shake_offset,
                .target = .{ .x = 0, .y = 0 },
                .rotation = 0,
                .zoom = 1,
            });
        }

        // Draw background
        self.background.draw(self.width, self.height);

        // Draw characters (back to front)
        for (self.characters[0..self.characterCount]) |*c| {
            c.draw(@floatFromInt(self.height));
        }

        // Draw dialogue
        if (self.dialogueRunner) |runner| {
            dialogue.draw(runner, self.textboxBounds, self.dialogueStyle);

            // Draw waiting indicator when dialogue is waiting for input
            if (runner.phase == .waiting and self.showWaitingIndicator) {
                const indicator_x: i32 = @intFromFloat(self.textboxBounds.x + self.textboxBounds.width - 30);
                const indicator_y: i32 = @intFromFloat(self.textboxBounds.y + self.textboxBounds.height - 25);
                rl.drawText("▼", indicator_x, indicator_y, 20, rl.Color.white);
            }
        }

        if (self.effect.type == .shake) {
            rl.endMode2D();
        }

        // Draw screen effects (on top)
        self.effect.draw(self.width, self.height);

        // Draw UI indicators
        self.drawModeIndicators();
    }

    fn drawModeIndicators(self: *const Self) void {
        const y: i32 = 10;
        var x: i32 = self.width - 100;

        if (self.autoMode) {
            rl.drawText("AUTO", x, y, 16, rl.Color.yellow);
            x -= 60;
        }
        if (self.skipMode) {
            rl.drawText("SKIP", x, y, 16, rl.Color.red);
        }
    }

    pub fn handleInput(self: *Self) void {
        // Toggle auto mode
        if (rl.isKeyPressed(.a)) {
            self.autoMode = !self.autoMode;
            self.autoTimer = 0;
        }

        // Toggle skip mode (hold Ctrl)
        self.skipMode = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);

        // Pass to dialogue
        if (self.dialogueRunner) |runner| {
            dialogue.handleInput(runner);
        }
    }
};

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}