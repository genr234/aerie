const std = @import("std");
const events = @import("events.zig");

pub const MAX_FLAGS = 128;
pub const MAX_VARS = 64;
pub const MAX_NAME_LEN = 32;
pub const MAX_STRING_VAR_LEN = 64;

pub const FlagEntry = struct {
    name: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN,
    nameLen: usize = 0,
    value: bool = false,

    pub fn init(name: []const u8, value: bool) FlagEntry {
        var entry = FlagEntry{ .value = value };
        const len = @min(name.len, MAX_NAME_LEN - 1);
        @memcpy(entry.name[0..len], name[0..len]);
        entry.name[len] = 0;
        entry.nameLen = len;
        return entry;
    }

    pub fn getName(self: *const FlagEntry) []const u8 {
        return self.name[0..self.nameLen];
    }

    pub fn matches(self: *const FlagEntry, name: []const u8) bool {
        if (self.nameLen != name.len) return false;
        return std.mem.eql(u8, self.name[0..self.nameLen], name);
    }
};

pub const VarValue = union(enum) {
    int: i32,
    float: f32,
    string: struct {
        data: [MAX_STRING_VAR_LEN]u8,
        len: usize,
    },

    pub fn fromInt(value: i32) VarValue {
        return .{ .int = value };
    }

    pub fn fromFloat(value: f32) VarValue {
        return .{ .float = value };
    }

    pub fn fromString(value: []const u8) VarValue {
        var result: VarValue = .{ .string = .{ .data = undefined, .len = 0 } };
        const len = @min(value.len, MAX_STRING_VAR_LEN - 1);
        @memcpy(result.string.data[0..len], value[0..len]);
        result.string.data[len] = 0;
        result.string.len = len;
        return result;
    }

    pub fn getInt(self: VarValue) ?i32 {
        return switch (self) {
            .int => |v| v,
            .float => |v| @intFromFloat(v),
            .string => null,
        };
    }

    pub fn getFloat(self: VarValue) ?f32 {
        return switch (self) {
            .int => |v| @floatFromInt(v),
            .float => |v| v,
            .string => null,
        };
    }

    pub fn getString(self: *const VarValue) ?[]const u8 {
        return switch (self.*) {
            .string => |*s| s.data[0..s.len],
            else => null,
        };
    }
};

pub const VarEntry = struct {
    name: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN,
    nameLen: usize = 0,
    value: VarValue = .{ .int = 0 },

    pub fn init(name: []const u8, value: VarValue) VarEntry {
        var entry = VarEntry{ .value = value };
        const len = @min(name.len, MAX_NAME_LEN - 1);
        @memcpy(entry.name[0..len], name[0..len]);
        entry.name[len] = 0;
        entry.nameLen = len;
        return entry;
    }

    pub fn getName(self: *const VarEntry) []const u8 {
        return self.name[0..self.nameLen];
    }

    pub fn matches(self: *const VarEntry, name: []const u8) bool {
        if (self.nameLen != name.len) return false;
        return std.mem.eql(u8, self.name[0..self.nameLen], name);
    }
};

// ============================================================================
// Relationship Entry - Character affinity/relationship tracking
// ============================================================================

pub const RelationshipEntry = struct {
    characterName: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN,
    nameLen: usize = 0,
    affinity: i32 = 0, // Can be negative (dislike) or positive (like)
    maxAffinity: i32 = 100,
    minAffinity: i32 = -100,

    pub fn init(name: []const u8, initial: i32) RelationshipEntry {
        var entry = RelationshipEntry{ .affinity = initial };
        const len = @min(name.len, MAX_NAME_LEN - 1);
        @memcpy(entry.characterName[0..len], name[0..len]);
        entry.characterName[len] = 0;
        entry.nameLen = len;
        return entry;
    }

    pub fn getName(self: *const RelationshipEntry) []const u8 {
        return self.characterName[0..self.nameLen];
    }

    pub fn matches(self: *const RelationshipEntry, name: []const u8) bool {
        if (self.nameLen != name.len) return false;
        return std.mem.eql(u8, self.characterName[0..self.nameLen], name);
    }

    pub fn modify(self: *RelationshipEntry, delta: i32) void {
        self.affinity = std.math.clamp(self.affinity + delta, self.minAffinity, self.maxAffinity);
    }

    pub fn set(self: *RelationshipEntry, value: i32) void {
        self.affinity = std.math.clamp(value, self.minAffinity, self.maxAffinity);
    }
};

pub const StoryState = struct {
    // Boolean flags
    flags: [MAX_FLAGS]FlagEntry = undefined,
    flagCount: usize = 0,

    // Variables (int/string)
    vars: [MAX_VARS]VarEntry = undefined,
    varCount: usize = 0,

    // Relationships
    relationships: [32]RelationshipEntry = undefined,
    relationshipCount: usize = 0,

    // Current chapter/route tracking
    currentChapter: usize = 0,
    currentRoute: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN,
    routeLen: usize = 0,

    // Play statistics
    playTime: f64 = 0.0, // Total play time in seconds
    choicesMade: u32 = 0,

    // Event queue reference for emitting events
    eventQueue: ?*events.EventQueue = null,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn initWithEvents(queue: *events.EventQueue) Self {
        return .{ .eventQueue = queue };
    }

    pub fn setFlag(self: *Self, name: []const u8, value: bool) void {
        self.setFlagInternal(name, value);
        self.emitFlagEvent(name, value);
    }

    /// Set flag without emitting an event (used by event handler to avoid infinite loop)
    pub fn setFlagInternal(self: *Self, name: []const u8, value: bool) void {
        // Check if flag exists
        for (self.flags[0..self.flagCount]) |*flag| {
            if (flag.matches(name)) {
                flag.value = value;
                return;
            }
        }

        // Create new flag
        if (self.flagCount < MAX_FLAGS) {
            self.flags[self.flagCount] = FlagEntry.init(name, value);
            self.flagCount += 1;
        }
    }

    pub fn getFlag(self: *const Self, name: []const u8) bool {
        for (self.flags[0..self.flagCount]) |*flag| {
            if (flag.matches(name)) {
                return flag.value;
            }
        }
        return false; // Default to false if not found
    }

    pub fn toggleFlag(self: *Self, name: []const u8) void {
        self.setFlag(name, !self.getFlag(name));
    }

    pub fn hasFlag(self: *const Self, name: []const u8) bool {
        for (self.flags[0..self.flagCount]) |*flag| {
            if (flag.matches(name)) {
                return true;
            }
        }
        return false;
    }

    fn emitFlagEvent(self: *Self, name: []const u8, value: bool) void {
        if (self.eventQueue) |queue| {
            queue.push(events.setFlag(name, value)) catch {};
        }
    }

    pub fn setInt(self: *Self, name: []const u8, value: i32) void {
        for (self.vars[0..self.varCount]) |*v| {
            if (v.matches(name)) {
                v.value = VarValue.fromInt(value);
                return;
            }
        }

        if (self.varCount < MAX_VARS) {
            self.vars[self.varCount] = VarEntry.init(name, VarValue.fromInt(value));
            self.varCount += 1;
        }
    }

    pub fn getInt(self: *const Self, name: []const u8) i32 {
        for (self.vars[0..self.varCount]) |*v| {
            if (v.matches(name)) {
                return v.value.getInt() orelse 0;
            }
        }
        return 0;
    }

    pub fn addInt(self: *Self, name: []const u8, delta: i32) void {
        self.setInt(name, self.getInt(name) + delta);
    }

    pub fn setFloat(self: *Self, name: []const u8, value: f32) void {
        for (self.vars[0..self.varCount]) |*v| {
            if (v.matches(name)) {
                v.value = VarValue.fromFloat(value);
                return;
            }
        }

        if (self.varCount < MAX_VARS) {
            self.vars[self.varCount] = VarEntry.init(name, VarValue.fromFloat(value));
            self.varCount += 1;
        }
    }

    pub fn getFloat(self: *const Self, name: []const u8) f32 {
        for (self.vars[0..self.varCount]) |*v| {
            if (v.matches(name)) {
                return v.value.getFloat() orelse 0.0;
            }
        }
        return 0.0;
    }

    pub fn setString(self: *Self, name: []const u8, value: []const u8) void {
        for (self.vars[0..self.varCount]) |*v| {
            if (v.matches(name)) {
                v.value = VarValue.fromString(value);
                return;
            }
        }

        if (self.varCount < MAX_VARS) {
            self.vars[self.varCount] = VarEntry.init(name, VarValue.fromString(value));
            self.varCount += 1;
        }
    }

    pub fn getString(self: *const Self, name: []const u8) []const u8 {
        for (self.vars[0..self.varCount]) |*v| {
            if (v.matches(name)) {
                return v.value.getString() orelse "";
            }
        }
        return "";
    }

    pub fn setRelationship(self: *Self, character: []const u8, value: i32) void {
        for (self.relationships[0..self.relationshipCount]) |*rel| {
            if (rel.matches(character)) {
                rel.set(value);
                return;
            }
        }

        if (self.relationshipCount < 32) {
            self.relationships[self.relationshipCount] = RelationshipEntry.init(character, value);
            self.relationshipCount += 1;
        }
    }

    pub fn modifyRelationship(self: *Self, character: []const u8, delta: i32) void {
        for (self.relationships[0..self.relationshipCount]) |*rel| {
            if (rel.matches(character)) {
                rel.modify(delta);
                return;
            }
        }

        if (self.relationshipCount < 32) {
            var rel = RelationshipEntry.init(character, 0);
            rel.modify(delta);
            self.relationships[self.relationshipCount] = rel;
            self.relationshipCount += 1;
        }
    }

    pub fn getRelationship(self: *const Self, character: []const u8) i32 {
        for (self.relationships[0..self.relationshipCount]) |*rel| {
            if (rel.matches(character)) {
                return rel.affinity;
            }
        }
        return 0;
    }

    pub fn setChapter(self: *Self, chapter: usize) void {
        self.currentChapter = chapter;
    }

    pub fn getChapter(self: *const Self) usize {
        return self.currentChapter;
    }

    pub fn setRoute(self: *Self, route: []const u8) void {
        const len = @min(route.len, MAX_NAME_LEN - 1);
        @memcpy(self.currentRoute[0..len], route[0..len]);
        self.currentRoute[len] = 0;
        self.routeLen = len;
    }

    pub fn getRoute(self: *const Self) []const u8 {
        return self.currentRoute[0..self.routeLen];
    }

    pub fn update(self: *Self, dt: f64) void {
        self.playTime += dt;
    }

    pub fn recordChoice(self: *Self) void {
        self.choicesMade += 1;
    }

    pub fn getPlayTimeMinutes(self: *const Self) f64 {
        return self.playTime / 60.0;
    }

    /// silly condition parser for dialogue branching
    /// pretty neat huh
    /// - "flagName" -> checks if flag is true
    /// - "!flagName" -> checks if flag is false
    /// - "varName > 5" -> checks if variable is greater than 5
    /// - "relationship:charName >= 50" -> checks relationship level
    pub fn checkCondition(self: *const Self, condition: []const u8) bool {
        if (condition.len == 0) return true;

        // Check for negation
        if (condition[0] == '!') {
            return !self.getFlag(condition[1..]);
        }

        // Check for relationship prefix
        if (std.mem.startsWith(u8, condition, "relationship:")) {
            return self.parseRelationshipCondition(condition[13..]);
        }

        // Check for comparison operators
        if (std.mem.indexOf(u8, condition, ">=")) |idx| {
            const varName = std.mem.trim(u8, condition[0..idx], " ");
            const valueStr = std.mem.trim(u8, condition[idx + 2 ..], " ");
            const value = std.fmt.parseInt(i32, valueStr, 10) catch return false;
            return self.getInt(varName) >= value;
        }

        if (std.mem.indexOf(u8, condition, "<=")) |idx| {
            const varName = std.mem.trim(u8, condition[0..idx], " ");
            const valueStr = std.mem.trim(u8, condition[idx + 2 ..], " ");
            const value = std.fmt.parseInt(i32, valueStr, 10) catch return false;
            return self.getInt(varName) <= value;
        }

        if (std.mem.indexOf(u8, condition, ">")) |idx| {
            const varName = std.mem.trim(u8, condition[0..idx], " ");
            const valueStr = std.mem.trim(u8, condition[idx + 1 ..], " ");
            const value = std.fmt.parseInt(i32, valueStr, 10) catch return false;
            return self.getInt(varName) > value;
        }

        if (std.mem.indexOf(u8, condition, "<")) |idx| {
            const varName = std.mem.trim(u8, condition[0..idx], " ");
            const valueStr = std.mem.trim(u8, condition[idx + 1 ..], " ");
            const value = std.fmt.parseInt(i32, valueStr, 10) catch return false;
            return self.getInt(varName) < value;
        }

        if (std.mem.indexOf(u8, condition, "==")) |idx| {
            const varName = std.mem.trim(u8, condition[0..idx], " ");
            const valueStr = std.mem.trim(u8, condition[idx + 2 ..], " ");
            const value = std.fmt.parseInt(i32, valueStr, 10) catch return false;
            return self.getInt(varName) == value;
        }

        // Default: treat as flag name
        return self.getFlag(condition);
    }

    fn parseRelationshipCondition(self: *const Self, condition: []const u8) bool {
        // Format: "charName >= value" or "charName > value", etc.
        if (std.mem.indexOf(u8, condition, ">=")) |idx| {
            const charName = std.mem.trim(u8, condition[0..idx], " ");
            const valueStr = std.mem.trim(u8, condition[idx + 2 ..], " ");
            const value = std.fmt.parseInt(i32, valueStr, 10) catch return false;
            return self.getRelationship(charName) >= value;
        }

        if (std.mem.indexOf(u8, condition, ">")) |idx| {
            const charName = std.mem.trim(u8, condition[0..idx], " ");
            const valueStr = std.mem.trim(u8, condition[idx + 1 ..], " ");
            const value = std.fmt.parseInt(i32, valueStr, 10) catch return false;
            return self.getRelationship(charName) > value;
        }

        return false;
    }

    pub fn reset(self: *Self) void {
        self.flagCount = 0;
        self.varCount = 0;
        self.relationshipCount = 0;
        self.currentChapter = 0;
        self.routeLen = 0;
        self.playTime = 0.0;
        self.choicesMade = 0;
    }

    pub fn clearFlags(self: *Self) void {
        self.flagCount = 0;
    }

    pub fn clearVars(self: *Self) void {
        self.varCount = 0;
    }

    pub const SaveData = struct {
        flags: []const FlagEntry,
        vars: []const VarEntry,
        relationships: []const RelationshipEntry,
        currentChapter: usize,
        currentRoute: []const u8,
        playTime: f64,
        choicesMade: u32,
    };

    pub fn toSaveData(self: *const Self) SaveData {
        return .{
            .flags = self.flags[0..self.flagCount],
            .vars = self.vars[0..self.varCount],
            .relationships = self.relationships[0..self.relationshipCount],
            .currentChapter = self.currentChapter,
            .currentRoute = self.getRoute(),
            .playTime = self.playTime,
            .choicesMade = self.choicesMade,
        };
    }

    pub fn loadFromSaveData(self: *Self, data: SaveData) void {
        self.reset();

        // Load flags
        const flagsToLoad = @min(data.flags.len, MAX_FLAGS);
        for (data.flags[0..flagsToLoad], 0..) |flag, i| {
            self.flags[i] = flag;
        }
        self.flagCount = flagsToLoad;

        // Load vars
        const varsToLoad = @min(data.vars.len, MAX_VARS);
        for (data.vars[0..varsToLoad], 0..) |v, i| {
            self.vars[i] = v;
        }
        self.varCount = varsToLoad;

        // Load relationships
        const relsToLoad = @min(data.relationships.len, 32);
        for (data.relationships[0..relsToLoad], 0..) |rel, i| {
            self.relationships[i] = rel;
        }
        self.relationshipCount = relsToLoad;

        // Load other state
        self.currentChapter = data.currentChapter;
        self.setRoute(data.currentRoute);
        self.playTime = data.playTime;
        self.choicesMade = data.choicesMade;
    }
};

pub fn makeCondition(storyState: *const StoryState, condition: []const u8) fn (?*anyopaque) bool {
    _ = storyState;
    _ = condition;
    return struct {
        fn check(_: ?*anyopaque) bool {
            return true;
        }
    }.check;
}
