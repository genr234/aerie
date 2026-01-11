const std = @import("std");
const rl = @import("raylib");
const mem = @import("memory.zig");

pub const MAX_ID_LEN = 64;
pub const MAX_LOOPING_SOUNDS = 8;

/// Sound entry with id and loaded sound
pub const SoundEntry = struct {
    id: [MAX_ID_LEN]u8 = [_]u8{0} ** MAX_ID_LEN,
    idLen: usize = 0,
    sound: rl.Sound = undefined,
    loaded: bool = false,

    pub fn getId(self: *const SoundEntry) []const u8 {
        return self.id[0..self.idLen];
    }

    pub fn matches(self: *const SoundEntry, name: []const u8) bool {
        if (self.idLen != name.len) return false;
        return std.mem.eql(u8, self.id[0..self.idLen], name);
    }
};

/// Music entry for background music
pub const MusicEntry = struct {
    id: [MAX_ID_LEN]u8 = [_]u8{0} ** MAX_ID_LEN,
    idLen: usize = 0,
    music: rl.Music = undefined,
    loaded: bool = false,

    pub fn getId(self: *const MusicEntry) []const u8 {
        return self.id[0..self.idLen];
    }

    pub fn matches(self: *const MusicEntry, name: []const u8) bool {
        if (self.idLen != name.len) return false;
        return std.mem.eql(u8, self.id[0..self.idLen], name);
    }
};

/// Looping sound entry (uses music stream for seamless looping)
pub const LoopingSoundEntry = struct {
    id: [MAX_ID_LEN]u8 = [_]u8{0} ** MAX_ID_LEN,
    idLen: usize = 0,
    music: rl.Music = undefined,
    active: bool = false,
    volume: f32 = 1.0,

    pub fn matches(self: *const LoopingSoundEntry, name: []const u8) bool {
        if (self.idLen != name.len) return false;
        return std.mem.eql(u8, self.id[0..self.idLen], name);
    }
};

/// Volume fade state
pub const VolumeFade = struct {
    active: bool = false,
    startVolume: f32 = 0.0,
    targetVolume: f32 = 1.0,
    duration: f32 = 1.0,
    elapsed: f32 = 0.0,

    pub fn progress(self: *const VolumeFade) f32 {
        if (self.duration <= 0) return 1.0;
        return std.math.clamp(self.elapsed / self.duration, 0.0, 1.0);
    }

    pub fn currentVolume(self: *const VolumeFade) f32 {
        const t = self.progress();
        return self.startVolume + (self.targetVolume - self.startVolume) * t;
    }

    pub fn update(self: *VolumeFade, dt: f32) void {
        if (!self.active) return;
        self.elapsed += dt;
        if (self.elapsed >= self.duration) {
            self.active = false;
        }
    }
};

/// Audio manager with dynamic capacity for sound effects and music
pub const AudioManager = struct {
    sounds: std.ArrayList(SoundEntry),
    music: std.ArrayList(MusicEntry),

    /// Active looping sounds (limited for performance)
    loopingSounds: [MAX_LOOPING_SOUNDS]LoopingSoundEntry = [_]LoopingSoundEntry{.{}} ** MAX_LOOPING_SOUNDS,
    loopingCount: usize = 0,

    currentMusic: ?*MusicEntry = null,
    masterVolume: f32 = 1.0,
    sfxVolume: f32 = 1.0,
    musicVolume: f32 = 0.7,

    /// Music fade state
    musicFade: VolumeFade = .{},

    initialized: bool = false,

    const Self = @This();

    /// Initialize with permanent allocator (lives for engine lifetime)
    pub fn init() Self {
        return initWithAllocator(mem.permanent());
    }

    /// Initialize with custom allocator
    pub fn initWithAllocator(allocator: std.mem.Allocator) Self {
        rl.initAudioDevice();
        return .{
            .sounds = std.ArrayList(SoundEntry).init(allocator),
            .music = std.ArrayList(MusicEntry).init(allocator),
            .initialized = true,
        };
    }

    pub fn deinit(self: *Self) void {
        // Stop and unload looping sounds
        for (&self.loopingSounds) |*entry| {
            if (entry.active) {
                rl.stopMusicStream(entry.music);
                rl.unloadMusicStream(entry.music);
                entry.active = false;
            }
        }

        // Unload all sounds
        for (self.sounds.items) |*entry| {
            if (entry.loaded) {
                rl.unloadSound(entry.sound);
                entry.loaded = false;
            }
        }
        self.sounds.deinit();

        // Unload all music
        for (self.music.items) |*entry| {
            if (entry.loaded) {
                rl.unloadMusicStream(entry.music);
                entry.loaded = false;
            }
        }
        self.music.deinit();

        if (self.initialized) {
            rl.closeAudioDevice();
            self.initialized = false;
        }
    }

    /// Register a sound effect with an id
    pub fn registerSound(self: *Self, id: []const u8, path: [:0]const u8) !void {
        var entry = SoundEntry{};
        const len = @min(id.len, MAX_ID_LEN - 1);
        @memcpy(entry.id[0..len], id[0..len]);
        entry.id[len] = 0;
        entry.idLen = len;
        entry.sound = rl.loadSound(path);
        entry.loaded = true;

        try self.sounds.append(entry);
    }

    /// Register background music with an id
    pub fn registerMusic(self: *Self, id: []const u8, path: [:0]const u8) !void {
        var entry = MusicEntry{};
        const len = @min(id.len, MAX_ID_LEN - 1);
        @memcpy(entry.id[0..len], id[0..len]);
        entry.id[len] = 0;
        entry.idLen = len;
        entry.music = rl.loadMusicStream(path);
        entry.loaded = true;

        try self.music.append(entry);
    }

    /// Find a sound by id
    pub fn findSound(self: *Self, id: []const u8) ?*SoundEntry {
        for (self.sounds.items) |*entry| {
            if (entry.matches(id)) return entry;
        }
        return null;
    }

    /// Find music by id
    pub fn findMusic(self: *Self, id: []const u8) ?*MusicEntry {
        for (self.music.items) |*entry| {
            if (entry.matches(id)) return entry;
        }
        return null;
    }

    /// Check if a sound is registered
    pub fn hasSound(self: *Self, id: []const u8) bool {
        return self.findSound(id) != null;
    }

    /// Check if music is registered
    pub fn hasMusic(self: *Self, id: []const u8) bool {
        return self.findMusic(id) != null;
    }

    /// Play a sound effect by id (one-shot)
    pub fn playSound(self: *Self, id: []const u8, volume: f32) void {
        if (self.findSound(id)) |entry| {
            rl.setSoundVolume(entry.sound, volume * self.sfxVolume * self.masterVolume);
            rl.playSound(entry.sound);
        }
    }

    /// Play a sound effect with default volume
    pub fn playSoundDefault(self: *Self, id: []const u8) void {
        self.playSound(id, 1.0);
    }

    /// Stop a specific sound
    pub fn stopSound(self: *Self, id: []const u8) void {
        if (self.findSound(id)) |entry| {
            rl.stopSound(entry.sound);
        }
        self.stopLoopedSound(id);
    }

    /// Stop all sounds (one-shot and looping)
    pub fn stopAllSounds(self: *Self) void {
        for (self.sounds.items) |*entry| {
            if (entry.loaded) {
                rl.stopSound(entry.sound);
            }
        }
        self.stopAllLoopedSounds();
    }

    /// Play a sound effect with looping
    pub fn playSoundLooped(self: *Self, id: []const u8, volume: f32) void {
        // Check if already playing
        for (&self.loopingSounds) |*entry| {
            if (entry.active and entry.matches(id)) {
                // Already playing, just update volume
                entry.volume = volume;
                rl.setMusicVolume(entry.music, volume * self.sfxVolume * self.masterVolume);
                return;
            }
        }

        // Find empty slot
        for (&self.loopingSounds) |*entry| {
            if (!entry.active) {
                const len = @min(id.len, MAX_ID_LEN - 1);
                @memcpy(entry.id[0..len], id[0..len]);
                entry.id[len] = 0;
                entry.idLen = len;
                entry.volume = volume;
                entry.active = true;
                self.loopingCount += 1;
                return;
            }
        }
    }

    /// Stop a looping sound
    pub fn stopLoopedSound(self: *Self, id: []const u8) void {
        for (&self.loopingSounds) |*entry| {
            if (entry.active and entry.matches(id)) {
                rl.stopMusicStream(entry.music);
                entry.active = false;
                if (self.loopingCount > 0) self.loopingCount -= 1;
                return;
            }
        }
    }

    /// Stop all looping sounds
    pub fn stopAllLoopedSounds(self: *Self) void {
        for (&self.loopingSounds) |*entry| {
            if (entry.active) {
                rl.stopMusicStream(entry.music);
                entry.active = false;
            }
        }
        self.loopingCount = 0;
    }

    /// Play background music by id
    pub fn playMusic(self: *Self, id: []const u8) void {
        // Stop current music if playing
        if (self.currentMusic) |current| {
            rl.stopMusicStream(current.music);
        }
        self.musicFade.active = false;

        if (self.findMusic(id)) |entry| {
            rl.setMusicVolume(entry.music, self.musicVolume * self.masterVolume);
            rl.playMusicStream(entry.music);
            self.currentMusic = entry;
        }
    }

    /// Play music with fade-in
    pub fn playMusicFadeIn(self: *Self, id: []const u8, fade_duration: f32) void {
        if (self.currentMusic) |current| {
            rl.stopMusicStream(current.music);
        }

        if (self.findMusic(id)) |entry| {
            rl.setMusicVolume(entry.music, 0.0);
            rl.playMusicStream(entry.music);
            self.currentMusic = entry;

            self.musicFade = .{
                .active = true,
                .startVolume = 0.0,
                .targetVolume = self.musicVolume,
                .duration = fade_duration,
                .elapsed = 0.0,
            };
        }
    }

    /// Fade out current music
    pub fn fadeOutMusic(self: *Self, fade_duration: f32) void {
        if (self.currentMusic == null) return;

        const current_vol = if (self.musicFade.active)
            self.musicFade.currentVolume()
        else
            self.musicVolume;

        self.musicFade = .{
            .active = true,
            .startVolume = current_vol,
            .targetVolume = 0.0,
            .duration = fade_duration,
            .elapsed = 0.0,
        };
    }

    /// Stop current music immediately
    pub fn stopMusic(self: *Self) void {
        if (self.currentMusic) |current| {
            rl.stopMusicStream(current.music);
            self.currentMusic = null;
        }
        self.musicFade.active = false;
    }

    /// Pause current music
    pub fn pauseMusic(self: *Self) void {
        if (self.currentMusic) |current| {
            rl.pauseMusicStream(current.music);
        }
    }

    /// Resume current music
    pub fn resumeMusic(self: *Self) void {
        if (self.currentMusic) |current| {
            rl.resumeMusicStream(current.music);
        }
    }

    /// Check if music is currently playing
    pub fn isMusicPlaying(self: *Self) bool {
        if (self.currentMusic) |current| {
            return rl.isMusicStreamPlaying(current.music);
        }
        return false;
    }

    /// Get current music playback time in seconds
    pub fn getMusicTimePlayed(self: *Self) f32 {
        if (self.currentMusic) |current| {
            return rl.getMusicTimePlayed(current.music);
        }
        return 0.0;
    }

    /// Get current music total length in seconds
    pub fn getMusicTimeLength(self: *Self) f32 {
        if (self.currentMusic) |current| {
            return rl.getMusicTimeLength(current.music);
        }
        return 0.0;
    }

    pub fn update(self: *Self, dt: f32) void {
        // Update music fade
        if (self.musicFade.active) {
            self.musicFade.update(dt);
            const vol = self.musicFade.currentVolume() * self.masterVolume;

            if (self.currentMusic) |current| {
                rl.setMusicVolume(current.music, vol);

                // Stop music if faded out completely
                if (!self.musicFade.active and self.musicFade.targetVolume <= 0.0) {
                    rl.stopMusicStream(current.music);
                    self.currentMusic = null;
                }
            }
        }

        // Update main music stream
        if (self.currentMusic) |current| {
            rl.updateMusicStream(current.music);
        }

        // Update looping sounds
        for (&self.loopingSounds) |*entry| {
            if (entry.active) {
                rl.updateMusicStream(entry.music);
            }
        }
    }

    /// Set master volume (affects all audio)
    pub fn setMasterVolume(self: *Self, volume: f32) void {
        self.masterVolume = std.math.clamp(volume, 0.0, 1.0);
        self.applyMusicVolume();
        self.applyLoopingVolumes();
    }

    /// Set SFX volume
    pub fn setSfxVolume(self: *Self, volume: f32) void {
        self.sfxVolume = std.math.clamp(volume, 0.0, 1.0);
        self.applyLoopingVolumes();
    }

    /// Set music volume
    pub fn setMusicVolume(self: *Self, volume: f32) void {
        self.musicVolume = std.math.clamp(volume, 0.0, 1.0);
        self.applyMusicVolume();
    }

    fn applyMusicVolume(self: *Self) void {
        if (self.currentMusic) |current| {
            const vol = if (self.musicFade.active)
                self.musicFade.currentVolume() * self.masterVolume
            else
                self.musicVolume * self.masterVolume;
            rl.setMusicVolume(current.music, vol);
        }
    }

    fn applyLoopingVolumes(self: *Self) void {
        for (&self.loopingSounds) |*entry| {
            if (entry.active) {
                rl.setMusicVolume(entry.music, entry.volume * self.sfxVolume * self.masterVolume);
            }
        }
    }

    /// Get number of registered sounds
    pub fn soundCount(self: *const Self) usize {
        return self.sounds.items.len;
    }

    /// Get number of registered music tracks
    pub fn musicCount(self: *const Self) usize {
        return self.music.items.len;
    }

    /// Get number of active looping sounds
    pub fn activeLoopCount(self: *const Self) usize {
        return self.loopingCount;
    }
};
