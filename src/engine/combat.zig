const std = @import("std");
const rl = @import("raylib");

const story = @import("story.zig");

pub const MAX_ID_LEN = 64;
pub const MAX_NAME_LEN = 64;
pub const MAX_PARTY = 4;
pub const MAX_ENEMIES = 6;
pub const MAX_BATTLERS = MAX_PARTY + MAX_ENEMIES;

pub const CombatError = error{
    InvalidJson,
    InvalidType,
    MissingField,
    InvalidValue,
    UnknownEncounter,
};

pub const Side = enum {
    party,
    enemy,
};

pub const SkillKind = enum {
    damage,
    heal,
};

pub const TargetKind = enum {
    enemy,
    ally,
    self,
};

pub const ActorDef = struct {
    id: []const u8,
    name: []const u8,
    side: Side = .enemy,
    level: i32 = 1,
    hp: i32 = 10,
    mp: i32 = 0,
    attack: i32 = 3,
    defense: i32 = 1,
    speed: i32 = 5,
    xp: i32 = 0,
    skills: []const []const u8 = &.{},
};

pub const SkillDef = struct {
    id: []const u8,
    name: []const u8,
    kind: SkillKind = .damage,
    power: i32 = 0,
    mp_cost: i32 = 0,
    target: TargetKind = .enemy,
    message: []const u8 = "",
};

pub const Reward = struct {
    xp: i32 = 0,
    gold: i32 = 0,
};

pub const EncounterDef = struct {
    id: []const u8,
    party: []const []const u8 = &.{},
    enemies: []const []const u8 = &.{},
    rewards: Reward = .{},
    on_win_scene: ?[]const u8 = null,
    on_lose_scene: ?[]const u8 = null,
};

pub const Database = struct {
    actors: []const ActorDef = &.{},
    skills: []const SkillDef = &.{},
    encounters: []const EncounterDef = &.{},

    pub fn empty() Database {
        return .{};
    }

    pub fn findActor(self: *const Database, id: []const u8) ?*const ActorDef {
        for (self.actors) |*actor| {
            if (std.mem.eql(u8, actor.id, id)) return actor;
        }
        return null;
    }

    pub fn findSkill(self: *const Database, id: []const u8) ?*const SkillDef {
        for (self.skills) |*skill| {
            if (std.mem.eql(u8, skill.id, id)) return skill;
        }
        return null;
    }

    pub fn findEncounter(self: *const Database, id: []const u8) ?*const EncounterDef {
        for (self.encounters) |*encounter| {
            if (std.mem.eql(u8, encounter.id, id)) return encounter;
        }
        return null;
    }
};

pub const BattlePhase = enum {
    idle,
    player_turn,
    enemy_turn,
    resolving,
    won,
    lost,
};

pub const Battler = struct {
    actor: *const ActorDef,
    side: Side,
    hp: i32,
    mp: i32,
    alive: bool = true,

    pub fn name(self: *const Battler) []const u8 {
        return self.actor.name;
    }
};

pub const BattleState = struct {
    db: Database = .{},
    story_state: ?*story.StoryState = null,
    active: bool = false,
    phase: BattlePhase = .idle,
    encounter: ?*const EncounterDef = null,
    battlers: [MAX_BATTLERS]Battler = undefined,
    battler_count: usize = 0,
    turn_order: [MAX_BATTLERS]usize = undefined,
    turn_count: usize = 0,
    turn_pos: usize = 0,
    selected_action: usize = 0,
    selected_target: usize = 0,
    message: [160]u8 = [_]u8{0} ** 160,
    message_len: usize = 0,
    message_timer: f32 = 0,
    exit_requested: bool = false,
    exit_scene: [MAX_ID_LEN]u8 = [_]u8{0} ** MAX_ID_LEN,
    exit_scene_len: usize = 0,
    rewards_granted: bool = false,

    pub fn init(db: Database, story_state: *story.StoryState) BattleState {
        return .{ .db = db, .story_state = story_state };
    }

    pub fn start(self: *BattleState, encounter_id: []const u8) bool {
        if (self.active) return false;
        const encounter = self.db.findEncounter(encounter_id) orelse return false;
        self.encounter = encounter;
        self.battler_count = 0;
        self.turn_count = 0;
        self.turn_pos = 0;
        self.selected_action = 0;
        self.selected_target = 0;
        self.exit_requested = false;
        self.exit_scene_len = 0;
        self.rewards_granted = false;

        var party_added: usize = 0;
        var enemies_added: usize = 0;
        for (encounter.party) |id| {
            if (self.addBattler(id, .party)) party_added += 1;
        }
        for (encounter.enemies) |id| {
            if (self.addBattler(id, .enemy)) enemies_added += 1;
        }

        if (party_added == 0 or enemies_added == 0 or !self.anyAlive(.party) or !self.anyAlive(.enemy)) {
            self.stop();
            self.setMessage("Invalid encounter.");
            return false;
        }

        self.rebuildTurnOrder();
        self.active = self.turn_count > 0;
        self.phase = .resolving;
        self.setMessage("Battle started!");
        self.advanceToNextLivingTurn();
        return self.active;
    }

    pub fn stop(self: *BattleState) void {
        self.active = false;
        self.phase = .idle;
        self.encounter = null;
        self.battler_count = 0;
        self.turn_count = 0;
        self.exit_requested = false;
        self.rewards_granted = false;
    }

    pub fn update(self: *BattleState, dt: f32) void {
        if (!self.active) return;
        if (self.message_timer > 0) {
            self.message_timer = @max(0, self.message_timer - dt);
            return;
        }
        if (self.phase == .enemy_turn) {
            self.enemyAct();
        }
    }

    pub fn handleInput(self: *BattleState) void {
        if (!self.active or self.phase != .player_turn or self.message_timer > 0) return;
        const actor_idx = self.currentBattlerIndex() orelse return;
        const actor = &self.battlers[actor_idx];
        const action_count = self.actionCount(actor);
        if (rl.isKeyPressed(.down)) {
            self.selected_action = (self.selected_action + 1) % action_count;
            self.selected_target = self.firstTargetForAction(actor_idx, self.selected_action);
        }
        if (rl.isKeyPressed(.up)) {
            self.selected_action = if (self.selected_action == 0) action_count - 1 else self.selected_action - 1;
            self.selected_target = self.firstTargetForAction(actor_idx, self.selected_action);
        }
        if (rl.isKeyPressed(.right)) self.selected_target = self.nextTargetForAction(actor_idx, self.selected_action, self.selected_target, 1);
        if (rl.isKeyPressed(.left)) self.selected_target = self.nextTargetForAction(actor_idx, self.selected_action, self.selected_target, -1);
        if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
            self.playerAct(actor_idx);
        }
    }

    pub fn draw(self: *const BattleState, width: i32, height: i32) void {
        rl.clearBackground(rl.Color{ .r = 20, .g = 24, .b = 32, .a = 255 });
        rl.drawText("Battle", 24, 18, 28, rl.Color.white);

        const mid = @divFloor(width, 2);
        rl.drawText("Party", 40, 64, 20, rl.Color.sky_blue);
        rl.drawText("Enemies", mid + 40, 64, 20, rl.Color.red);

        var py: i32 = 100;
        var ey: i32 = 100;
        for (self.battlers[0..self.battler_count], 0..) |b, i| {
            const marker = if (self.currentBattlerIndex()) |idx| if (idx == i) ">" else " " else " ";
            const color = if (b.alive) rl.Color.white else rl.Color.gray;
            var buf: [160]u8 = undefined;
            const line = std.fmt.bufPrintZ(&buf, "{s} {s}  HP {d}/{d} MP {d}/{d}", .{ marker, b.name(), b.hp, b.actor.hp, b.mp, b.actor.mp }) catch continue;
            if (b.side == .party) {
                rl.drawText(line, 40, py, 18, color);
                py += 30;
            } else {
                rl.drawText(line, mid + 40, ey, 18, color);
                ey += 30;
            }
        }

        const panel_y = height - 130;
        rl.drawRectangle(0, panel_y, width, 130, rl.Color{ .r = 8, .g = 10, .b = 16, .a = 230 });
        if (self.message_len > 0) {
            rl.drawText(self.message[0..self.message_len :0], 24, panel_y + 16, 20, rl.Color.white);
        }

        if (self.phase == .player_turn) {
            if (self.currentBattlerIndex()) |idx| {
                const actor = &self.battlers[idx];
                rl.drawText("Choose action", 24, panel_y + 50, 18, rl.Color.light_gray);
                self.drawActions(actor, 24, panel_y + 78);
                if (self.selected_target < self.battler_count) {
                    var target_buf: [96]u8 = undefined;
                    const target = std.fmt.bufPrintZ(&target_buf, "Target: {s}", .{self.battlers[self.selected_target].name()}) catch "";
                    rl.drawText(target, mid + 24, panel_y + 78, 18, rl.Color.white);
                }
            }
        } else if (self.phase == .won) {
            rl.drawText("Victory! Press Enter.", 24, panel_y + 76, 20, rl.Color.green);
        } else if (self.phase == .lost) {
            rl.drawText("Defeat. Press Enter.", 24, panel_y + 76, 20, rl.Color.red);
        }
    }

    pub fn confirmExit(self: *BattleState) void {
        if (!self.active) return;
        if ((self.phase == .won or self.phase == .lost) and (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space))) {
            if (self.encounter) |encounter| {
                const scene = if (self.phase == .won) encounter.on_win_scene else encounter.on_lose_scene;
                if (scene) |name| {
                    const len = @min(name.len, self.exit_scene.len - 1);
                    @memcpy(self.exit_scene[0..len], name[0..len]);
                    self.exit_scene[len] = 0;
                    self.exit_scene_len = len;
                }
            }
            self.exit_requested = true;
            self.stop();
        }
    }

    pub fn hp(self: *const BattleState, actor_id: []const u8) i32 {
        for (self.battlers[0..self.battler_count]) |b| {
            if (std.mem.eql(u8, b.actor.id, actor_id)) return b.hp;
        }
        if (self.story_state) |state| {
            var key_buf: [96]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "combat.{s}.hp", .{actor_id}) catch return 0;
            return state.getInt(key);
        }
        return 0;
    }

    pub fn setHp(self: *BattleState, actor_id: []const u8, value: i32) void {
        for (self.battlers[0..self.battler_count]) |*b| {
            if (std.mem.eql(u8, b.actor.id, actor_id)) {
                b.hp = std.math.clamp(value, 0, b.actor.hp);
                b.alive = b.hp > 0;
                return;
            }
        }
        if (self.story_state) |state| {
            var key_buf: [96]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "combat.{s}.hp", .{actor_id}) catch return;
            state.setInt(key, value);
        }
    }

    pub fn modifyHp(self: *BattleState, actor_id: []const u8, delta: i32) void {
        self.setHp(actor_id, self.hp(actor_id) + delta);
    }

    fn addBattler(self: *BattleState, id: []const u8, side: Side) bool {
        if (self.battler_count >= MAX_BATTLERS) return false;
        const actor = self.db.findActor(id) orelse return false;
        self.battlers[self.battler_count] = .{
            .actor = actor,
            .side = side,
            .hp = actor.hp,
            .mp = actor.mp,
            .alive = actor.hp > 0,
        };
        self.battler_count += 1;
        return true;
    }

    fn rebuildTurnOrder(self: *BattleState) void {
        self.turn_count = self.battler_count;
        for (0..self.turn_count) |i| self.turn_order[i] = i;
        var i: usize = 1;
        while (i < self.turn_count) : (i += 1) {
            const key = self.turn_order[i];
            var j = i;
            while (j > 0 and self.battlers[self.turn_order[j - 1]].actor.speed < self.battlers[key].actor.speed) : (j -= 1) {
                self.turn_order[j] = self.turn_order[j - 1];
            }
            self.turn_order[j] = key;
        }
    }

    fn advanceToNextLivingTurn(self: *BattleState) void {
        if (self.checkOutcome()) return;
        for (0..self.turn_count) |_| {
            const idx = self.turn_order[self.turn_pos];
            self.turn_pos = (self.turn_pos + 1) % self.turn_count;
            if (!self.battlers[idx].alive) continue;
            self.selected_action = 0;
            self.selected_target = self.firstTargetForAction(idx, 0);
            self.phase = if (self.battlers[idx].side == .party) .player_turn else .enemy_turn;
            return;
        }
    }

    fn currentBattlerIndex(self: *const BattleState) ?usize {
        if (self.turn_count == 0) return null;
        const pos = if (self.turn_pos == 0) self.turn_count - 1 else self.turn_pos - 1;
        const idx = self.turn_order[pos];
        if (idx >= self.battler_count or !self.battlers[idx].alive) return null;
        return idx;
    }

    fn actionCount(self: *const BattleState, actor: *const Battler) usize {
        _ = self;
        return 1 + actor.actor.skills.len;
    }

    fn skillForAction(self: *const BattleState, actor: *const Battler, action: usize) ?*const SkillDef {
        if (action == 0) return null;
        const skill_id = actor.actor.skills[action - 1];
        return self.db.findSkill(skill_id);
    }

    fn playerAct(self: *BattleState, actor_idx: usize) void {
        const actor = &self.battlers[actor_idx];
        const skill = self.skillForAction(actor, self.selected_action);
        if (skill) |s| {
            if (actor.mp < s.mp_cost) {
                self.setMessage("Not enough MP.");
                return;
            }
            actor.mp -= s.mp_cost;
        }
        self.resolveAction(actor_idx, self.selected_target, skill);
        self.advanceToNextLivingTurn();
    }

    fn enemyAct(self: *BattleState) void {
        const actor_idx = self.currentBattlerIndex() orelse return;
        const actor = &self.battlers[actor_idx];
        var skill: ?*const SkillDef = null;
        for (actor.actor.skills) |skill_id| {
            const s = self.db.findSkill(skill_id) orelse continue;
            if (actor.mp >= s.mp_cost) {
                skill = s;
                actor.mp -= s.mp_cost;
                break;
            }
        }
        const target = self.firstTargetForSkill(actor_idx, skill);
        self.resolveAction(actor_idx, target, skill);
        self.advanceToNextLivingTurn();
    }

    fn resolveAction(self: *BattleState, actor_idx: usize, target_idx: usize, skill: ?*const SkillDef) void {
        if (actor_idx >= self.battler_count or target_idx >= self.battler_count) return;
        const actor = &self.battlers[actor_idx];
        const target = &self.battlers[target_idx];
        if (!target.alive) return;

        if (skill) |s| {
            switch (s.kind) {
                .damage => {
                    const amount = @max(1, actor.actor.attack + s.power - target.actor.defense);
                    target.hp = @max(0, target.hp - amount);
                    target.alive = target.hp > 0;
                    self.setMessageFmt("{s} uses {s} for {d}.", .{ actor.name(), s.name, amount });
                },
                .heal => {
                    const amount = @max(1, s.power + actor.actor.attack);
                    target.hp = @min(target.actor.hp, target.hp + amount);
                    target.alive = target.hp > 0;
                    self.setMessageFmt("{s} uses {s}.", .{ actor.name(), s.name });
                },
            }
        } else {
            const amount = @max(1, actor.actor.attack - target.actor.defense);
            target.hp = @max(0, target.hp - amount);
            target.alive = target.hp > 0;
            self.setMessageFmt("{s} attacks for {d}.", .{ actor.name(), amount });
        }
    }

    fn checkOutcome(self: *BattleState) bool {
        const party_alive = self.anyAlive(.party);
        const enemy_alive = self.anyAlive(.enemy);
        if (!enemy_alive) {
            self.phase = .won;
            if (!self.rewards_granted) {
                self.grantRewards();
                self.rewards_granted = true;
            }
            self.setMessage("Victory!");
            return true;
        }
        if (!party_alive) {
            self.phase = .lost;
            self.setMessage("Defeat.");
            return true;
        }
        return false;
    }

    fn grantRewards(self: *BattleState) void {
        const state = self.story_state orelse return;
        const encounter = self.encounter orelse return;
        if (encounter.rewards.xp != 0) state.addInt("party.xp", encounter.rewards.xp);
        if (encounter.rewards.gold != 0) state.addInt("inv.gold", encounter.rewards.gold);
        for (self.battlers[0..self.battler_count]) |b| {
            if (b.side != .party) continue;
            var key_buf: [96]u8 = undefined;
            var level_key_buf: [96]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "actor.{s}.xp", .{b.actor.id}) catch continue;
            state.addInt(key, encounter.rewards.xp);
            const level_key = std.fmt.bufPrint(&level_key_buf, "actor.{s}.level", .{b.actor.id}) catch continue;
            const xp = state.getInt(key);
            const next_level = b.actor.level + @divFloor(xp, 100);
            state.setInt(level_key, next_level);
        }
    }

    fn anyAlive(self: *const BattleState, side: Side) bool {
        for (self.battlers[0..self.battler_count]) |b| {
            if (b.side == side and b.alive) return true;
        }
        return false;
    }

    fn firstTarget(self: *const BattleState, actor_side: Side) usize {
        const desired: Side = if (actor_side == .party) .enemy else .party;
        for (self.battlers[0..self.battler_count], 0..) |b, i| {
            if (b.side == desired and b.alive) return i;
        }
        return 0;
    }

    fn firstTargetForAction(self: *const BattleState, actor_idx: usize, action: usize) usize {
        if (actor_idx >= self.battler_count) return 0;
        const actor = &self.battlers[actor_idx];
        return self.firstTargetForSkill(actor_idx, self.skillForAction(actor, action));
    }

    fn firstTargetForSkill(self: *const BattleState, actor_idx: usize, skill: ?*const SkillDef) usize {
        if (actor_idx >= self.battler_count) return 0;
        const actor = &self.battlers[actor_idx];
        if (skill) |s| {
            if (s.target == .self) return actor_idx;
            const desired: Side = switch (s.target) {
                .enemy => if (actor.side == .party) .enemy else .party,
                .ally => actor.side,
                .self => actor.side,
            };
            for (self.battlers[0..self.battler_count], 0..) |b, i| {
                if (b.side == desired and b.alive) return i;
            }
            return actor_idx;
        }
        return self.firstTarget(actor.side);
    }

    fn nextTarget(self: *const BattleState, actor_side: Side, current: usize, dir: i32) usize {
        if (self.battler_count == 0) return 0;
        const desired: Side = if (actor_side == .party) .enemy else .party;
        var idx: i32 = @intCast(current);
        for (0..self.battler_count) |_| {
            idx += dir;
            if (idx < 0) idx = @intCast(self.battler_count - 1);
            if (@as(usize, @intCast(idx)) >= self.battler_count) idx = 0;
            const b = self.battlers[@intCast(idx)];
            if (b.side == desired and b.alive) return @intCast(idx);
        }
        return current;
    }

    fn nextTargetForAction(self: *const BattleState, actor_idx: usize, action: usize, current: usize, dir: i32) usize {
        if (actor_idx >= self.battler_count) return current;
        const actor = &self.battlers[actor_idx];
        const skill = self.skillForAction(actor, action);
        if (skill) |s| {
            if (s.target == .self) return actor_idx;
            const desired: Side = switch (s.target) {
                .enemy => if (actor.side == .party) .enemy else .party,
                .ally => actor.side,
                .self => actor.side,
            };
            var idx: i32 = @intCast(current);
            for (0..self.battler_count) |_| {
                idx += dir;
                if (idx < 0) idx = @intCast(self.battler_count - 1);
                if (@as(usize, @intCast(idx)) >= self.battler_count) idx = 0;
                const b = self.battlers[@intCast(idx)];
                if (b.side == desired and b.alive) return @intCast(idx);
            }
            return current;
        }
        return self.nextTarget(actor.side, current, dir);
    }

    fn drawActions(self: *const BattleState, actor: *const Battler, x: i32, y: i32) void {
        rl.drawText(if (self.selected_action == 0) "> Attack" else "  Attack", x, y, 18, rl.Color.white);
        var yy = y + 24;
        for (actor.actor.skills, 0..) |skill_id, i| {
            const skill = self.db.findSkill(skill_id) orelse continue;
            var buf: [96]u8 = undefined;
            const prefix = if (self.selected_action == i + 1) ">" else " ";
            const label = std.fmt.bufPrintZ(&buf, "{s} {s} ({d} MP)", .{ prefix, skill.name, skill.mp_cost }) catch continue;
            rl.drawText(label, x, yy, 18, if (actor.mp >= skill.mp_cost) rl.Color.white else rl.Color.gray);
            yy += 24;
        }
    }

    fn setMessage(self: *BattleState, text: []const u8) void {
        const len = @min(text.len, self.message.len - 1);
        @memcpy(self.message[0..len], text[0..len]);
        self.message[len] = 0;
        self.message_len = len;
        self.message_timer = 0.55;
    }

    fn setMessageFmt(self: *BattleState, comptime fmt: []const u8, args: anytype) void {
        var buf: [160]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.setMessage(msg);
    }
};

pub fn parseDatabaseJson(allocator: std.mem.Allocator, text: []const u8) !Database {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return CombatError.InvalidJson;
    defer parsed.deinit();
    if (parsed.value != .object) return CombatError.InvalidType;
    return .{
        .actors = if (parsed.value.object.get("actors")) |v| try parseActors(allocator, v) else &.{},
        .skills = if (parsed.value.object.get("skills")) |v| try parseSkills(allocator, v) else &.{},
        .encounters = if (parsed.value.object.get("encounters")) |v| try parseEncounters(allocator, v) else &.{},
    };
}

fn parseActors(allocator: std.mem.Allocator, v: std.json.Value) ![]const ActorDef {
    if (v != .array) return CombatError.InvalidType;
    const out = try allocator.alloc(ActorDef, v.array.items.len);
    for (v.array.items, 0..) |item, i| {
        if (item != .object) return CombatError.InvalidType;
        var actor = ActorDef{
            .id = try dupString(allocator, try getString(item.object, "id")),
            .name = try dupString(allocator, try getString(item.object, "name")),
        };
        if (item.object.get("side")) |side| actor.side = try parseSide(try asString(side));
        if (item.object.get("level")) |n| actor.level = @intCast(try asInt(n));
        if (item.object.get("hp")) |n| actor.hp = @intCast(try asInt(n));
        if (item.object.get("mp")) |n| actor.mp = @intCast(try asInt(n));
        if (item.object.get("attack")) |n| actor.attack = @intCast(try asInt(n));
        if (item.object.get("defense")) |n| actor.defense = @intCast(try asInt(n));
        if (item.object.get("speed")) |n| actor.speed = @intCast(try asInt(n));
        if (item.object.get("xp")) |n| actor.xp = @intCast(try asInt(n));
        if (item.object.get("skills")) |skills| actor.skills = try parseStringArray(allocator, skills);
        out[i] = actor;
    }
    return out;
}

fn parseSkills(allocator: std.mem.Allocator, v: std.json.Value) ![]const SkillDef {
    if (v != .array) return CombatError.InvalidType;
    const out = try allocator.alloc(SkillDef, v.array.items.len);
    for (v.array.items, 0..) |item, i| {
        if (item != .object) return CombatError.InvalidType;
        var skill = SkillDef{
            .id = try dupString(allocator, try getString(item.object, "id")),
            .name = try dupString(allocator, try getString(item.object, "name")),
        };
        if (item.object.get("kind")) |kind| skill.kind = try parseSkillKind(try asString(kind));
        if (item.object.get("power")) |n| skill.power = @intCast(try asInt(n));
        if (item.object.get("mpCost")) |n| skill.mp_cost = @intCast(try asInt(n));
        if (item.object.get("target")) |target| skill.target = try parseTargetKind(try asString(target));
        if (item.object.get("message")) |message| skill.message = try dupString(allocator, try asString(message));
        out[i] = skill;
    }
    return out;
}

fn parseEncounters(allocator: std.mem.Allocator, v: std.json.Value) ![]const EncounterDef {
    if (v != .array) return CombatError.InvalidType;
    const out = try allocator.alloc(EncounterDef, v.array.items.len);
    for (v.array.items, 0..) |item, i| {
        if (item != .object) return CombatError.InvalidType;
        var encounter = EncounterDef{
            .id = try dupString(allocator, try getString(item.object, "id")),
            .party = if (item.object.get("party")) |party| try parseStringArray(allocator, party) else &.{},
            .enemies = if (item.object.get("enemies")) |enemies| try parseStringArray(allocator, enemies) else &.{},
        };
        if (item.object.get("rewards")) |rewards| encounter.rewards = try parseReward(rewards);
        if (item.object.get("onWinScene")) |scene| encounter.on_win_scene = try dupString(allocator, try asString(scene));
        if (item.object.get("onLoseScene")) |scene| encounter.on_lose_scene = try dupString(allocator, try asString(scene));
        out[i] = encounter;
    }
    return out;
}

fn parseReward(v: std.json.Value) !Reward {
    if (v != .object) return CombatError.InvalidType;
    var reward: Reward = .{};
    if (v.object.get("xp")) |n| reward.xp = @intCast(try asInt(n));
    if (v.object.get("gold")) |n| reward.gold = @intCast(try asInt(n));
    return reward;
}

fn parseStringArray(allocator: std.mem.Allocator, v: std.json.Value) ![]const []const u8 {
    if (v != .array) return CombatError.InvalidType;
    const out = try allocator.alloc([]const u8, v.array.items.len);
    for (v.array.items, 0..) |item, i| out[i] = try dupString(allocator, try asString(item));
    return out;
}

fn parseSide(value: []const u8) !Side {
    if (std.mem.eql(u8, value, "party")) return .party;
    if (std.mem.eql(u8, value, "enemy")) return .enemy;
    return CombatError.InvalidValue;
}

fn parseSkillKind(value: []const u8) !SkillKind {
    if (std.mem.eql(u8, value, "damage")) return .damage;
    if (std.mem.eql(u8, value, "heal")) return .heal;
    return CombatError.InvalidValue;
}

fn parseTargetKind(value: []const u8) !TargetKind {
    if (std.mem.eql(u8, value, "enemy")) return .enemy;
    if (std.mem.eql(u8, value, "ally")) return .ally;
    if (std.mem.eql(u8, value, "self")) return .self;
    return CombatError.InvalidValue;
}

fn getString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    return asString(obj.get(key) orelse return CombatError.MissingField);
}

fn asString(v: std.json.Value) ![]const u8 {
    return switch (v) {
        .string => v.string,
        else => CombatError.InvalidType,
    };
}

fn asInt(v: std.json.Value) !i64 {
    return switch (v) {
        .integer => v.integer,
        .float => @intFromFloat(v.float),
        else => CombatError.InvalidType,
    };
}

fn dupString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const out = try allocator.alloc(u8, s.len);
    @memcpy(out, s);
    return out;
}

test "combat parser accepts actors skills and encounters" {
    const text =
        \\{
        \\  "actors": [{ "id": "hero", "name": "Hero", "side": "party", "hp": 20, "skills": ["fire"] }],
        \\  "skills": [{ "id": "fire", "name": "Fire", "kind": "damage", "power": 4, "mpCost": 2 }],
        \\  "encounters": [{ "id": "slimes", "party": ["hero"], "enemies": ["slime"], "rewards": { "xp": 5 } }]
        \\}
    ;
    const db = try parseDatabaseJson(std.testing.allocator, text);
    try std.testing.expectEqual(@as(usize, 1), db.actors.len);
    try std.testing.expectEqualStrings("fire", db.skills[0].id);
    try std.testing.expectEqual(@as(i32, 5), db.encounters[0].rewards.xp);
}
