const std = @import("std");
const rl = @import("raylib");
const dialogue = @import("dialogue.zig");
const events = @import("events.zig");
const root = @import("../root.zig");
const state = @import("state.zig");

pub const Entity = struct {
    id: u32,
    generation: u16,

    pub const INVALID = Entity{ .id = std.math.maxInt(u32), .generation = 0 };

    pub fn isValid(self: Entity) bool {
        return self.id != std.math.maxInt(u32);
    }

    pub fn eql(self: Entity, other: Entity) bool {
        return self.id == other.id and self.generation == other.generation;
    }
};

pub const TagComponent = struct {
    name: [64]u8 = [_]u8{0} ** 64,
    len: usize = 0,

    pub fn init(name: []const u8) TagComponent {
        var tag = TagComponent{};
        const max_copy: usize = tag.name.len - 1;
        const copy_len: usize = @min(name.len, max_copy);
        @memcpy(tag.name[0..copy_len], name[0..copy_len]);
        tag.name[copy_len] = 0;
        tag.len = copy_len;
        return tag;
    }

    pub fn get(self: *const TagComponent) []const u8 {
        const max_len: usize = self.name.len;
        var n: usize = self.len;
        if (n > max_len) {
            n = std.mem.indexOfScalar(u8, &self.name, 0) orelse max_len;
        }
        return self.name[0..n];
    }
};

pub const Transform = struct {
    position: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
    scale: rl.Vector2 = .{ .x = 1, .y = 1 },
};

pub const SpriteRenderer = struct {
    texture: rl.Texture2D,
    flip_x: bool = false,
    tint: rl.Color = rl.Color.white,
    frame_width: f32 = 0,
    frame_height: f32 = 0,
    frames: usize = 1,
    fps: f32 = 0,
    loop: bool = true,
    start_frame: usize = 0,
    current_frame: usize = 0,
    frame_timer: f32 = 0,

    pub fn init(texture: rl.Texture2D) SpriteRenderer {
        return .{ .texture = texture };
    }
};

pub const CircleRenderer = struct {
    radius: f32,
    color: rl.Color,
};

pub const RectRenderer = struct {
    width: f32,
    height: f32,
    color: rl.Color,
};

pub const PlayerController = struct {
    speed: f32 = 100,
    paused: bool = false,
    mode: MovementMode = .smooth4,
    facing: Direction = .down,
    step_size: f32 = 16,
    step_time: f32 = 0.12,
    step_from: rl.Vector2 = .{ .x = 0, .y = 0 },
    step_to: rl.Vector2 = .{ .x = 0, .y = 0 },
    step_elapsed: f32 = 0,
    stepping: bool = false,
};

pub const Solid = struct {
    enabled: bool = true,
};

pub const MovementMode = enum {
    smooth4,
    smooth8,
    grid4,
};

pub const Direction = enum {
    down,
    up,
    left,
    right,

    pub fn vector(self: Direction) rl.Vector2 {
        return switch (self) {
            .down => .{ .x = 0, .y = 1 },
            .up => .{ .x = 0, .y = -1 },
            .left => .{ .x = -1, .y = 0 },
            .right => .{ .x = 1, .y = 0 },
        };
    }
};

pub const AnimationClip = struct {
    name: [32]u8 = [_]u8{0} ** 32,
    name_len: usize = 0,
    start: usize = 0,
    frames: usize = 1,
    fps: f32 = 8,
    loop: bool = true,

    pub fn init(name: []const u8, start: usize, frames: usize, fps: f32, loop: bool) AnimationClip {
        var out = AnimationClip{ .start = start, .frames = frames, .fps = fps, .loop = loop };
        const len = @min(name.len, out.name.len - 1);
        @memcpy(out.name[0..len], name[0..len]);
        out.name[len] = 0;
        out.name_len = len;
        return out;
    }

    pub fn matches(self: *const AnimationClip, name: []const u8) bool {
        return self.name_len == name.len and std.mem.eql(u8, self.name[0..self.name_len], name);
    }
};

pub const AnimationState = struct {
    clips: []const AnimationClip = &.{},
    current: usize = 0,
};

pub const Tilemap = struct {
    columns: usize,
    rows: usize,
    tile_width: f32 = 16,
    tile_height: f32 = 16,
    tiles: []const u8 = &.{},
    solid_tiles: []const u8 = &.{},
    palette: []const rl.Color = &.{},

    pub fn tileAt(self: *const Tilemap, col: usize, row: usize) u8 {
        if (col >= self.columns or row >= self.rows) return 0;
        const idx = row * self.columns + col;
        if (idx >= self.tiles.len) return 0;
        return self.tiles[idx];
    }

    pub fn tileIsSolid(self: *const Tilemap, tile: u8) bool {
        if (tile == 0) return false;
        for (self.solid_tiles) |solid| {
            if (solid == tile) return true;
        }
        return false;
    }
};

pub const Particle = struct {
    position: rl.Vector2 = .{ .x = 0, .y = 0 },
    velocity: rl.Vector2 = .{ .x = 0, .y = 0 },
    life: f32 = 0,
    max_life: f32 = 0,
};

pub const ParticleEmitter = struct {
    color: rl.Color = rl.Color.white,
    rate: f32 = 12,
    lifetime: f32 = 0.6,
    speed: f32 = 40,
    spread: f32 = 6.28,
    radius: f32 = 2,
    burst: usize = 0,
    timer: f32 = 0,
    seed: u32 = 1,
    particles: [64]Particle = [_]Particle{.{}} ** 64,
};

pub const Tween = struct {
    to: rl.Vector2,
    duration: f32,
    elapsed: f32 = 0,
    from: rl.Vector2 = .{ .x = 0, .y = 0 },
    started: bool = false,
    loop: bool = false,
};

pub const Camera = struct {
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },
    target: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
    zoom: f32 = 1.0,
    follow_target: Entity = Entity.INVALID,
    smoothing: f32 = 10,
    clamp_to_scene: bool = true,
    dead_zone: rl.Vector2 = .{ .x = 0, .y = 0 },
    shake_time: f32 = 0,
    shake_duration: f32 = 0,
    shake_intensity: f32 = 0,

    pub fn toRaylib(self: *const Camera) rl.Camera2D {
        return .{
            .offset = self.offset,
            .target = self.target,
            .rotation = self.rotation,
            .zoom = self.zoom,
        };
    }
};

pub const TriggerAction = union(enum) {
    show_message: struct {
        text: [128]u8,
        duration: f32 = 2.0,
    },
    start_dialogue: struct {
        runner: *dialogue.Runner,
        context: ?*anyopaque,
        id: [events.MAX_ID_LEN]u8,
        id_len: usize = 0,
        label: [events.MAX_ID_LEN]u8,
        label_len: usize = 0,
    },
    change_scene: struct {
        index: usize,
        name: [events.MAX_ID_LEN]u8 = [_]u8{0} ** events.MAX_ID_LEN,
        name_len: usize = 0,
        use_index: bool = true,
    },
    set_flag: struct {
        name: [events.MAX_ID_LEN]u8,
        name_len: usize,
        value: bool,
    },
    start_combat: struct {
        encounter: [events.MAX_ID_LEN]u8,
        encounter_len: usize = 0,
    },
    sequence: []const TriggerAction,
    run_action: dialogue.ActionFn,
};

pub fn TriggerShowMessage(text: []const u8, duration: f32) TriggerAction {
    var action = TriggerAction{ .show_message = .{ .text = [_]u8{0} ** 128, .duration = duration } };
    const copy_len: usize = @min(text.len, action.show_message.text.len - 1);
    @memcpy(action.show_message.text[0..copy_len], text[0..copy_len]);
    action.show_message.text[copy_len] = 0;
    return action;
}

pub fn TriggerDialogueStart(runner: *dialogue.Runner, context: ?*anyopaque, id: ?[]const u8, label: ?[]const u8) TriggerAction {
    var out: TriggerAction = .{ .start_dialogue = .{
        .runner = runner,
        .context = context,
        .id = [_]u8{0} ** events.MAX_ID_LEN,
        .id_len = 0,
        .label = [_]u8{0} ** events.MAX_ID_LEN,
        .label_len = 0,
    } };

    if (id) |dialogue_id| {
        const len = @min(dialogue_id.len, events.MAX_ID_LEN - 1);
        @memcpy(out.start_dialogue.id[0..len], dialogue_id[0..len]);
        out.start_dialogue.id[len] = 0;
        out.start_dialogue.id_len = len;
    }

    if (label) |lbl| {
        const len = @min(lbl.len, events.MAX_ID_LEN - 1);
        @memcpy(out.start_dialogue.label[0..len], lbl[0..len]);
        out.start_dialogue.label[len] = 0;
        out.start_dialogue.label_len = len;
    }

    return out;
}

pub fn TriggerRunAction(action: dialogue.ActionFn) TriggerAction {
    return TriggerAction{ .run_action = action };
}

pub fn TriggerStartCombat(encounter: []const u8) TriggerAction {
    var out: TriggerAction = .{ .start_combat = .{
        .encounter = [_]u8{0} ** events.MAX_ID_LEN,
        .encounter_len = 0,
    } };
    const len = @min(encounter.len, events.MAX_ID_LEN - 1);
    @memcpy(out.start_combat.encounter[0..len], encounter[0..len]);
    out.start_combat.encounter[len] = 0;
    out.start_combat.encounter_len = len;
    return out;
}

pub const Trigger = struct {
    bounds: rl.Rectangle,
    action: TriggerAction,
    was_inside: bool = false,
    one_shot: bool = false,
    triggered: bool = false,

    pub fn reset(self: *Trigger) void {
        self.was_inside = false;
        self.triggered = false;
    }
};

pub const BoxCollider = struct {
    width: f32,
    height: f32,
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },

    pub fn getRect(self: *const BoxCollider, transform: *const Transform) rl.Rectangle {
        return .{
            .x = transform.position.x + self.offset.x,
            .y = transform.position.y + self.offset.y,
            .width = self.width * @abs(transform.scale.x),
            .height = self.height * @abs(transform.scale.y),
        };
    }
};

pub const Interactable = struct {
    bounds: rl.Rectangle,
    action: TriggerAction,
    prompt: [64]u8 = [_]u8{0} ** 64,
    prompt_len: usize = 0,
    repeatable: bool = true,
    used: bool = false,

    pub fn init(bounds: rl.Rectangle, action: TriggerAction, prompt: []const u8, repeatable: bool) Interactable {
        var out = Interactable{ .bounds = bounds, .action = action, .repeatable = repeatable };
        const len = @min(prompt.len, out.prompt.len - 1);
        @memcpy(out.prompt[0..len], prompt[0..len]);
        out.prompt[len] = 0;
        out.prompt_len = len;
        return out;
    }

    pub fn promptText(self: *const Interactable) []const u8 {
        return self.prompt[0..self.prompt_len];
    }
};

pub const Portal = struct {
    bounds: rl.Rectangle,
    scene: [events.MAX_ID_LEN]u8 = [_]u8{0} ** events.MAX_ID_LEN,
    scene_len: usize = 0,
    spawn: [events.MAX_ID_LEN]u8 = [_]u8{0} ** events.MAX_ID_LEN,
    spawn_len: usize = 0,

    pub fn init(bounds: rl.Rectangle, scene_name: []const u8, spawn_name: ?[]const u8) Portal {
        var out = Portal{ .bounds = bounds };
        const scene_len = @min(scene_name.len, events.MAX_ID_LEN - 1);
        @memcpy(out.scene[0..scene_len], scene_name[0..scene_len]);
        out.scene[scene_len] = 0;
        out.scene_len = scene_len;
        if (spawn_name) |name| {
            const spawn_len = @min(name.len, events.MAX_ID_LEN - 1);
            @memcpy(out.spawn[0..spawn_len], name[0..spawn_len]);
            out.spawn[spawn_len] = 0;
            out.spawn_len = spawn_len;
        }
        return out;
    }

    pub fn sceneName(self: *const Portal) []const u8 {
        return self.scene[0..self.scene_len];
    }

    pub fn spawnName(self: *const Portal) ?[]const u8 {
        if (self.spawn_len == 0) return null;
        return self.spawn[0..self.spawn_len];
    }
};

pub const SpawnPoint = struct {
    name: [events.MAX_ID_LEN]u8 = [_]u8{0} ** events.MAX_ID_LEN,
    name_len: usize = 0,

    pub fn init(name: []const u8) SpawnPoint {
        var out = SpawnPoint{};
        const len = @min(name.len, events.MAX_ID_LEN - 1);
        @memcpy(out.name[0..len], name[0..len]);
        out.name[len] = 0;
        out.name_len = len;
        return out;
    }

    pub fn get(self: *const SpawnPoint) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const Active = struct {
    value: bool = true,
};

pub fn ComponentStorage(comptime T: type) type {
    return struct {
        const Self = @This();

        /// sparse maps entity_id -> dense index
        sparse: std.array_list.Aligned(?u32, null) = .empty,
        generations: std.array_list.Aligned(u16, null) = .empty,

        dense_entities: std.array_list.Aligned(u32, null) = .empty,
        dense_data: std.array_list.Aligned(T, null) = .empty,

        pub fn init(self: *Self, allocator: std.mem.Allocator, initial_capacity: usize) !void {
            try self.ensureEntityCapacity(allocator, initial_capacity);
            try self.dense_entities.ensureTotalCapacity(allocator, initial_capacity);
            try self.dense_data.ensureTotalCapacity(allocator, initial_capacity);
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.sparse.deinit(allocator);
            self.generations.deinit(allocator);
            self.dense_entities.deinit(allocator);
            self.dense_data.deinit(allocator);
        }

        fn ensureEntityCapacity(self: *Self, allocator: std.mem.Allocator, entity_capacity: usize) !void {
            if (self.sparse.items.len >= entity_capacity) return;

            const old_len = self.sparse.items.len;
            try self.sparse.resize(allocator, entity_capacity);
            for (old_len..entity_capacity) |i| self.sparse.items[i] = null;

            const old_glen = self.generations.items.len;
            try self.generations.resize(allocator, entity_capacity);
            for (old_glen..entity_capacity) |i| self.generations.items[i] = 0;
        }

        pub fn clear(self: *Self) void {
            // Only clear the dense sets; sparse stays allocated and is reset for used indices.
            for (self.dense_entities.items) |eid| {
                if (eid < self.sparse.items.len) self.sparse.items[eid] = null;
            }
            self.dense_entities.items.len = 0;
            self.dense_data.items.len = 0;
        }

        pub fn set(self: *Self, allocator: std.mem.Allocator, entity: Entity, component: T) !void {
            try self.ensureEntityCapacity(allocator, @as(usize, entity.id) + 1);

            if (self.sparse.items[entity.id]) |dense_idx| {
                if (self.generations.items[entity.id] <= entity.generation) {
                    self.dense_data.items[dense_idx] = component;
                    self.generations.items[entity.id] = entity.generation;
                }
                return;
            }

            const idx: u32 = @intCast(self.dense_entities.items.len);
            try self.dense_entities.append(allocator, entity.id);
            try self.dense_data.append(allocator, component);
            self.sparse.items[entity.id] = idx;
            self.generations.items[entity.id] = entity.generation;
        }

        pub fn get(self: *Self, entity: Entity) ?*T {
            if (entity.id >= self.sparse.items.len) return null;
            if (self.generations.items[entity.id] != entity.generation) return null;
            if (self.sparse.items[entity.id]) |dense_idx| {
                return &self.dense_data.items[dense_idx];
            }
            return null;
        }

        pub fn getConst(self: *const Self, entity: Entity) ?*const T {
            if (entity.id >= self.sparse.items.len) return null;
            if (self.generations.items[entity.id] != entity.generation) return null;
            if (self.sparse.items[entity.id]) |dense_idx| {
                return &self.dense_data.items[dense_idx];
            }
            return null;
        }

        pub fn has(self: *const Self, entity: Entity) bool {
            if (entity.id >= self.sparse.items.len) return false;
            return self.sparse.items[entity.id] != null;
        }

        pub fn remove(self: *Self, entity: Entity) void {
            if (entity.id >= self.sparse.items.len) return;
            const dense_idx = self.sparse.items[entity.id] orelse return;

            const last_idx: u32 = @intCast(self.dense_entities.items.len - 1);
            if (dense_idx != last_idx) {
                const last_eid = self.dense_entities.items[last_idx];
                self.dense_entities.items[dense_idx] = last_eid;
                self.dense_data.items[dense_idx] = self.dense_data.items[last_idx];
                self.sparse.items[last_eid] = dense_idx;
            }

            self.sparse.items[entity.id] = null;
            _ = self.dense_entities.pop();
            _ = self.dense_data.pop();
        }

        pub fn iterator(self: *Self) Iterator {
            return .{ .storage = self, .index = 0 };
        }

        pub const Iterator = struct {
            storage: *Self,
            index: u32,

            pub fn next(self: *Iterator) ?struct { entity_id: u32, data: *T } {
                if (self.index >= self.storage.dense_entities.items.len) return null;
                const entity_id = self.storage.dense_entities.items[self.index];
                const data = &self.storage.dense_data.items[self.index];
                self.index += 1;
                return .{ .entity_id = entity_id, .data = data };
            }
        };
    };
}

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    entity_generations: std.array_list.Aligned(u16, null) = .empty,
    entity_alive: std.array_list.Aligned(bool, null) = .empty,

    free_list: std.array_list.Aligned(u32, null) = .empty,
    entity_count: u32 = 0,

    state: *state.GameState = undefined,

    tags: ComponentStorage(TagComponent) = .{},
    transforms: ComponentStorage(Transform) = .{},
    sprite_renderers: ComponentStorage(SpriteRenderer) = .{},
    circle_renderers: ComponentStorage(CircleRenderer) = .{},
    rect_renderers: ComponentStorage(RectRenderer) = .{},
    player_controllers: ComponentStorage(PlayerController) = .{},
    solids: ComponentStorage(Solid) = .{},
    animation_states: ComponentStorage(AnimationState) = .{},
    tilemaps: ComponentStorage(Tilemap) = .{},
    particle_emitters: ComponentStorage(ParticleEmitter) = .{},
    tweens: ComponentStorage(Tween) = .{},
    cameras: ComponentStorage(Camera) = .{},
    triggers: ComponentStorage(Trigger) = .{},
    box_colliders: ComponentStorage(BoxCollider) = .{},
    interactables: ComponentStorage(Interactable) = .{},
    portals: ComponentStorage(Portal) = .{},
    spawn_points: ComponentStorage(SpawnPoint) = .{},
    actives: ComponentStorage(Active) = .{},

    bounds_width: f32 = 800,
    bounds_height: f32 = 450,

    max_entities: usize = 0,
    next_entity_id: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, max_entities: usize, game_state: *state.GameState) !Self {
        var self = Self{
            .allocator = allocator,
            .state = game_state,
            .max_entities = max_entities,
        };

        try self.entity_generations.resize(allocator, max_entities);
        @memset(self.entity_generations.items, 0);

        try self.entity_alive.resize(allocator, max_entities);
        @memset(self.entity_alive.items, false);

        try self.free_list.ensureTotalCapacity(allocator, max_entities);

        try self.tags.init(allocator, max_entities);
        try self.transforms.init(allocator, max_entities);
        try self.sprite_renderers.init(allocator, max_entities);
        try self.circle_renderers.init(allocator, max_entities);
        try self.rect_renderers.init(allocator, max_entities);
        try self.player_controllers.init(allocator, max_entities);
        try self.solids.init(allocator, max_entities);
        try self.animation_states.init(allocator, max_entities);
        try self.tilemaps.init(allocator, max_entities);
        try self.particle_emitters.init(allocator, max_entities);
        try self.tweens.init(allocator, max_entities);
        try self.cameras.init(allocator, max_entities);
        try self.triggers.init(allocator, max_entities);
        try self.box_colliders.init(allocator, max_entities);
        try self.interactables.init(allocator, max_entities);
        try self.portals.init(allocator, max_entities);
        try self.spawn_points.init(allocator, max_entities);
        try self.actives.init(allocator, max_entities);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.tags.deinit(self.allocator);
        self.transforms.deinit(self.allocator);
        self.sprite_renderers.deinit(self.allocator);
        self.circle_renderers.deinit(self.allocator);
        self.rect_renderers.deinit(self.allocator);
        self.player_controllers.deinit(self.allocator);
        self.solids.deinit(self.allocator);
        self.animation_states.deinit(self.allocator);
        self.tilemaps.deinit(self.allocator);
        self.particle_emitters.deinit(self.allocator);
        self.tweens.deinit(self.allocator);
        self.cameras.deinit(self.allocator);
        self.triggers.deinit(self.allocator);
        self.box_colliders.deinit(self.allocator);
        self.interactables.deinit(self.allocator);
        self.portals.deinit(self.allocator);
        self.spawn_points.deinit(self.allocator);
        self.actives.deinit(self.allocator);

        self.entity_generations.deinit(self.allocator);
        self.entity_alive.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
    }

    fn ensureCapacity(self: *Self, new_capacity: usize) !void {
        if (self.max_entities >= new_capacity) return;

        const old_cap = self.max_entities;
        self.max_entities = @max(new_capacity, old_cap * 2);

        try self.entity_generations.resize(self.allocator, self.max_entities);
        for (old_cap..self.max_entities) |i| self.entity_generations.items[i] = 0;

        try self.entity_alive.resize(self.allocator, self.max_entities);
        for (old_cap..self.max_entities) |i| self.entity_alive.items[i] = false;

        try self.tags.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.transforms.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.sprite_renderers.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.circle_renderers.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.rect_renderers.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.player_controllers.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.solids.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.animation_states.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.tilemaps.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.particle_emitters.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.tweens.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.cameras.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.triggers.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.box_colliders.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.interactables.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.portals.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.spawn_points.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.actives.ensureEntityCapacity(self.allocator, self.max_entities);
    }

    pub fn entityFromId(self: *const Self, entity_id: u32) Entity {
        if (entity_id >= self.max_entities) return Entity.INVALID;
        return .{ .id = entity_id, .generation = self.entity_generations.items[entity_id] };
    }

    pub fn spawn(self: *Self) Entity {
        const entity_id: u32 = if (self.free_list.items.len > 0) blk: {
            // `pop()` returns an optional in Zig; unwrap is safe because len > 0.
            break :blk (self.free_list.pop() orelse unreachable);
        } else blk: {
            const next_id = self.next_entity_id;
            if (next_id >= self.max_entities) {
                self.ensureCapacity(@as(usize, next_id) + 1) catch return Entity.INVALID;
            }
            self.next_entity_id += 1;
            // After ensureCapacity, entity_alive has been resized to max_entities.
            break :blk next_id;
        };

        if (@as(usize, entity_id) >= self.entity_alive.items.len) {
            // Defensive: keep arrays consistent even if invariants change.
            self.ensureCapacity(@as(usize, entity_id) + 1) catch return Entity.INVALID;
        }

        self.entity_alive.items[entity_id] = true;
        self.entity_count += 1;

        const entity = Entity{ .id = entity_id, .generation = self.entity_generations.items[entity_id] };
        self.actives.set(self.allocator, entity, .{ .value = true }) catch {};

        return entity;
    }

    pub fn despawn(self: *Self, entity: Entity) void {
        if (!self.isAlive(entity)) return;

        self.tags.remove(entity);
        self.transforms.remove(entity);
        self.sprite_renderers.remove(entity);
        self.circle_renderers.remove(entity);
        self.rect_renderers.remove(entity);
        self.player_controllers.remove(entity);
        self.solids.remove(entity);
        self.animation_states.remove(entity);
        self.tilemaps.remove(entity);
        self.particle_emitters.remove(entity);
        self.tweens.remove(entity);
        self.cameras.remove(entity);
        self.triggers.remove(entity);
        self.box_colliders.remove(entity);
        self.interactables.remove(entity);
        self.portals.remove(entity);
        self.spawn_points.remove(entity);
        self.actives.remove(entity);

        self.entity_alive.items[entity.id] = false;
        self.entity_generations.items[entity.id] += 1;
        self.free_list.append(self.allocator, entity.id) catch {};
        self.entity_count -= 1;
    }

    pub fn isAlive(self: *const Self, entity: Entity) bool {
        if (entity.id >= self.max_entities) return false;
        return self.entity_alive.items[entity.id] and self.entity_generations.items[entity.id] == entity.generation;
    }

    pub fn isActive(self: *Self, entity: Entity) bool {
        if (!self.isAlive(entity)) return false;
        if (self.actives.get(entity)) |active| {
            return active.value;
        }
        return true;
    }

    pub fn setActive(self: *Self, entity: Entity, active: bool) void {
        if (self.actives.get(entity)) |a| {
            a.value = active;
        }
    }

    pub fn findByTag(self: *Self, name: []const u8) ?Entity {
        var it = self.tags.iterator();
        while (it.next()) |item| {
            if (std.mem.eql(u8, item.data.get(), name)) {
                const entity = self.entityFromId(item.entity_id);
                if (self.isAlive(entity)) {
                    return entity;
                }
            }
        }
        return null;
    }

    pub fn clear(self: *Self) void {
        inline for (std.meta.fields(Self)) |field| {
            const FieldType = field.type;
            if (@hasDecl(FieldType, "clear")) {
                @field(self, field.name).clear();
            }
        }

        for (self.entity_alive.items, self.entity_generations.items) |*alive, *gen| {
            if (alive.*) gen.* +%= 1;
            alive.* = false;
        }

        self.free_list.clearRetainingCapacity();
        self.entity_count = 0;
    }
};

pub const Systems = struct {
    pub fn processEvents(world: *World, dt: f32) void {
        world.state.eventQueue.process(dt);
    }

    pub fn playerMovement(world: *World, dt: f32) void {
        var it = world.player_controllers.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            if (item.data.paused) continue;

            const transform = world.transforms.get(entity) orelse continue;
            const speed = item.data.speed;

            const input = inputVector(item.data.mode);
            if (input.x != 0 or input.y != 0) {
                item.data.facing = directionFromVector(input, item.data.facing);
                if (item.data.facing == .right) transform.scale.x = -@abs(transform.scale.x);
                if (item.data.facing == .left) transform.scale.x = @abs(transform.scale.x);
            }

            if (item.data.mode == .grid4) {
                updateGridMovement(world, entity, transform, item.data, input, dt);
            } else {
                const previous = transform.position;
                transform.position.x += input.x * speed * dt;
                clampEntityToWorld(world, entity);
                if (collidesWithSolid(world, entity)) transform.position.x = previous.x;

                const after_x = transform.position;
                transform.position.y += input.y * speed * dt;
                clampEntityToWorld(world, entity);
                if (collidesWithSolid(world, entity)) transform.position.y = after_x.y;
            }
        }
    }

    pub fn cameraFollow(world: *World) void {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const cam_entity = world.entityFromId(item.entity_id);
            if (!world.isActive(cam_entity)) continue;

            const cam = item.data;
            if (!cam.follow_target.isValid()) continue;
            if (!world.isAlive(cam.follow_target)) continue;

            if (world.transforms.get(cam.follow_target)) |target_transform| {
                var target_x = target_transform.position.x;
                var target_y = target_transform.position.y;

                // Center offset; if rotation is present, apply a simple rotated offset.
                if (world.sprite_renderers.get(cam.follow_target)) |sr| {
                    const w: f32 = @floatFromInt(sr.texture.width);
                    const h: f32 = @floatFromInt(sr.texture.height);
                    const angle = target_transform.rotation;
                    const half_w = w / 2;
                    const half_h = h / 2;
                    target_x += half_w * @cos(angle);
                    target_y += half_h * @sin(angle);
                } else if (world.box_colliders.get(cam.follow_target)) |col| {
                    target_x += col.width / 2;
                    target_y += col.height / 2;
                }

                var desired = rl.Vector2{ .x = target_x, .y = target_y };
                if (cam.clamp_to_scene) {
                    const view_w = @as(f32, @floatFromInt(rl.getScreenWidth())) / @max(cam.zoom, 0.001);
                    const view_h = @as(f32, @floatFromInt(rl.getScreenHeight())) / @max(cam.zoom, 0.001);
                    if (world.bounds_width > view_w) {
                        desired.x = std.math.clamp(desired.x, view_w / 2, world.bounds_width - view_w / 2);
                    }
                    if (world.bounds_height > view_h) {
                        desired.y = std.math.clamp(desired.y, view_h / 2, world.bounds_height - view_h / 2);
                    }
                }

                if (cam.smoothing <= 0) {
                    cam.target = desired;
                } else {
                    const t = 1.0 - @exp(-cam.smoothing * rl.getFrameTime());
                    cam.target.x += (desired.x - cam.target.x) * t;
                    cam.target.y += (desired.y - cam.target.y) * t;
                }
            }

            if (cam.shake_time > 0 and cam.shake_duration > 0) {
                cam.shake_time = @max(0, cam.shake_time - rl.getFrameTime());
                const t = cam.shake_time / cam.shake_duration;
                const amount = cam.shake_intensity * t;
                const phase = cam.shake_time * 77.0;
                cam.target.x += @sin(phase) * amount;
                cam.target.y += @cos(phase * 1.37) * amount;
            }
        }
    }

    pub fn spriteAnimation(world: *World, dt: f32) void {
        var it = world.sprite_renderers.iterator();
        while (it.next()) |item| {
            var sr = item.data;
            if (sr.frames <= 1 or sr.fps <= 0) continue;
            sr.frame_timer += dt;
            const frame_time = 1.0 / sr.fps;
            while (sr.frame_timer >= frame_time) {
                sr.frame_timer -= frame_time;
                const end_frame = sr.start_frame + sr.frames;
                if (sr.current_frame + 1 < end_frame) {
                    sr.current_frame += 1;
                } else if (sr.loop) {
                    sr.current_frame = sr.start_frame;
                } else {
                    sr.current_frame = end_frame - 1;
                    sr.frame_timer = 0;
                    break;
                }
            }
        }
    }

    pub fn tweenUpdate(world: *World, dt: f32) void {
        var it = world.tweens.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            const tr = world.transforms.get(entity) orelse continue;
            const tween = item.data;
            if (!tween.started) {
                tween.from = tr.position;
                tween.started = true;
            }
            tween.elapsed += dt;
            const ratio = std.math.clamp(tween.elapsed / @max(tween.duration, 0.001), 0, 1);
            const eased = ratio * ratio * (3 - 2 * ratio);
            tr.position.x = tween.from.x + (tween.to.x - tween.from.x) * eased;
            tr.position.y = tween.from.y + (tween.to.y - tween.from.y) * eased;
            if (ratio >= 1) {
                if (tween.loop) {
                    const old_from = tween.from;
                    tween.from = tween.to;
                    tween.to = old_from;
                    tween.elapsed = 0;
                } else {
                    world.tweens.remove(entity);
                }
            }
        }
    }

    pub fn particlesUpdate(world: *World, dt: f32) void {
        var it = world.particle_emitters.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            const tr = world.transforms.get(entity) orelse continue;
            const emitter = item.data;

            var spawn_count: usize = emitter.burst;
            emitter.burst = 0;
            emitter.timer += dt * emitter.rate;
            while (emitter.timer >= 1) {
                emitter.timer -= 1;
                spawn_count += 1;
            }
            for (0..spawn_count) |_| spawnParticle(emitter, tr.position);

            for (&emitter.particles) |*p| {
                if (p.life <= 0) continue;
                p.life -= dt;
                p.position.x += p.velocity.x * dt;
                p.position.y += p.velocity.y * dt;
            }
        }
    }

    /// Check trigger collisions
    pub fn triggerCheck(world: *World) void {
        // Find player collider
        var player_entity: Entity = Entity.INVALID;
        var player_rect: rl.Rectangle = undefined;
        var have_player_rect = false;

        var player_it = world.player_controllers.iterator();
        while (player_it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            player_entity = entity;

            if (world.transforms.get(entity)) |tr| {
                if (world.box_colliders.get(entity)) |col| {
                    player_rect = col.getRect(tr);
                    have_player_rect = true;
                } else if (world.sprite_renderers.get(entity)) |sr| {
                    const abs_scale = @abs(tr.scale.x);
                    player_rect = .{
                        .x = tr.position.x,
                        .y = tr.position.y,
                        .width = @as(f32, @floatFromInt(sr.texture.width)) * abs_scale,
                        .height = @as(f32, @floatFromInt(sr.texture.height)) * abs_scale,
                    };
                    have_player_rect = true;
                }
            }
            break;
        }

        if (!player_entity.isValid() or !have_player_rect) return;

        var it = world.triggers.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;

            const trigger = item.data;
            if (trigger.one_shot and trigger.triggered) continue;

            const inside = rl.checkCollisionRecs(player_rect, trigger.bounds);

            if (inside and !trigger.was_inside) {
                executeAction(world, trigger.action);
                if (trigger.one_shot) trigger.triggered = true;
            }

            trigger.was_inside = inside;
        }
    }

    pub fn portalCheck(world: *World) void {
        const player_rect = getPlayerRect(world) orelse return;
        var it = world.portals.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            const portal = item.data;
            if (!rl.checkCollisionRecs(player_rect, portal.bounds)) continue;
            world.state.eventQueue.push(events.changeSceneByNameToSpawn(portal.sceneName(), portal.spawnName())) catch {};
            return;
        }
    }

    pub fn interactionCheck(world: *World) void {
        const player = firstPlayer(world) orelse return;
        const player_rect = entityRect(world, player) orelse return;
        const controller = world.player_controllers.get(player) orelse return;
        const probe = interactionProbe(player_rect, controller.facing);
        var prompt: ?[]const u8 = null;
        var target: ?Entity = null;

        var it = world.interactables.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            const interactable = item.data;
            if (!interactable.repeatable and interactable.used) continue;
            if (!rl.checkCollisionRecs(probe, interactable.bounds)) continue;
            prompt = interactable.promptText();
            target = entity;
            break;
        }

        if (target) |entity| {
            if (rl.isKeyPressed(.space) or rl.isKeyPressed(.enter) or rl.isKeyPressed(.e)) {
                if (world.interactables.get(entity)) |interactable| {
                    executeAction(world, interactable.action);
                    if (!interactable.repeatable) interactable.used = true;
                }
            }
        }
    }

    pub fn drawInteractionPrompt(world: *World) void {
        const player = firstPlayer(world) orelse return;
        const player_rect = entityRect(world, player) orelse return;
        const controller = world.player_controllers.get(player) orelse return;
        const probe = interactionProbe(player_rect, controller.facing);

        var it = world.interactables.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            const interactable = item.data;
            if (!interactable.repeatable and interactable.used) continue;
            if (!rl.checkCollisionRecs(probe, interactable.bounds)) continue;
            const text = interactable.promptText();
            if (text.len > 0) drawPromptHint(text);
            return;
        }
    }

    pub fn render(world: *World) void {
        {
            var it = world.tilemaps.iterator();
            while (it.next()) |item| {
                const entity = world.entityFromId(item.entity_id);
                if (!world.isActive(entity)) continue;
                const tr = world.transforms.getConst(entity) orelse continue;
                const map = item.data;
                for (0..map.rows) |row| {
                    for (0..map.columns) |col| {
                        const tile = map.tileAt(col, row);
                        if (tile == 0) continue;
                        const color = if (tile - 1 < map.palette.len) map.palette[tile - 1] else rl.Color.gray;
                        rl.drawRectangle(
                            @intFromFloat(tr.position.x + @as(f32, @floatFromInt(col)) * map.tile_width),
                            @intFromFloat(tr.position.y + @as(f32, @floatFromInt(row)) * map.tile_height),
                            @intFromFloat(map.tile_width),
                            @intFromFloat(map.tile_height),
                            color,
                        );
                    }
                }
            }
        }

        {
            var it = world.circle_renderers.iterator();
            while (it.next()) |item| {
                const entity = world.entityFromId(item.entity_id);
                if (!world.isActive(entity)) continue;
                const tr = world.transforms.getConst(entity) orelse continue;
                rl.drawCircle(
                    @intFromFloat(tr.position.x),
                    @intFromFloat(tr.position.y),
                    item.data.radius,
                    item.data.color,
                );
            }
        }

        {
            var it = world.rect_renderers.iterator();
            while (it.next()) |item| {
                const entity = world.entityFromId(item.entity_id);
                if (!world.isActive(entity)) continue;
                const tr = world.transforms.getConst(entity) orelse continue;
                rl.drawRectangle(
                    @intFromFloat(tr.position.x),
                    @intFromFloat(tr.position.y),
                    @intFromFloat(item.data.width),
                    @intFromFloat(item.data.height),
                    item.data.color,
                );
            }
        }

        {
            var it = world.sprite_renderers.iterator();
            while (it.next()) |item| {
                const entity = world.entityFromId(item.entity_id);
                if (!world.isActive(entity)) continue;
                const tr = world.transforms.getConst(entity) orelse continue;
                const sr = item.data;

                const texture_w: f32 = @floatFromInt(sr.texture.width);
                const texture_h: f32 = @floatFromInt(sr.texture.height);
                const sprite_w: f32 = if (sr.frame_width > 0) sr.frame_width else texture_w;
                const sprite_h: f32 = if (sr.frame_height > 0) sr.frame_height else texture_h;
                const columns = @max(1, @as(usize, @intFromFloat(@floor(texture_w / sprite_w))));
                const frame = @min(sr.current_frame, sr.start_frame + sr.frames - 1);
                const frame_x: f32 = @floatFromInt(frame % columns);
                const frame_y: f32 = @floatFromInt(frame / columns);

                const flip = sr.flip_x or tr.scale.x < 0;
                const src = rl.Rectangle{
                    .x = frame_x * sprite_w + if (flip) sprite_w else 0,
                    .y = frame_y * sprite_h,
                    .width = if (flip) -sprite_w else sprite_w,
                    .height = sprite_h,
                };

                const abs_scale = @abs(tr.scale.x);
                const dest = rl.Rectangle{
                    .x = tr.position.x,
                    .y = tr.position.y,
                    .width = sprite_w * abs_scale,
                    .height = sprite_h * abs_scale,
                };

                rl.drawTexturePro(sr.texture, src, dest, .{ .x = 0, .y = 0 }, tr.rotation, sr.tint);
            }
        }

        {
            var it = world.particle_emitters.iterator();
            while (it.next()) |item| {
                const entity = world.entityFromId(item.entity_id);
                if (!world.isActive(entity)) continue;
                const emitter = item.data;
                for (emitter.particles) |p| {
                    if (p.life <= 0) continue;
                    const alpha = @as(u8, @intFromFloat(std.math.clamp(p.life / @max(p.max_life, 0.001), 0, 1) * 255));
                    var color = emitter.color;
                    color.a = alpha;
                    rl.drawCircle(@intFromFloat(p.position.x), @intFromFloat(p.position.y), emitter.radius, color);
                }
            }
        }
    }

    pub fn drawWorldUi(world: *World) void {
        _ = world;
    }

    pub fn getActiveCamera(world: *World) !rl.Camera2D {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            return item.data.toRaylib();
        }
        return error.NoActiveCamera;
    }

    pub fn getPlayerRect(world: *World) ?rl.Rectangle {
        var it = world.player_controllers.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;

            if (world.transforms.get(entity)) |tr| {
                if (world.sprite_renderers.get(entity)) |sr| {
                    const abs_scale = @abs(tr.scale.x);
                    return .{
                        .x = tr.position.x,
                        .y = tr.position.y,
                        .width = @as(f32, @floatFromInt(sr.texture.width)) * abs_scale,
                        .height = @as(f32, @floatFromInt(sr.texture.height)) * abs_scale,
                    };
                } else if (world.box_colliders.get(entity)) |col| {
                    return col.getRect(tr);
                }
            }
        }
        return null;
    }

    pub fn setCameraZoom(world: *World, zoom: f32) void {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            item.data.zoom = zoom;
            break;
        }
    }

    pub fn setCameraTarget(world: *World, target: rl.Vector2) void {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            item.data.target = target;
            break;
        }
    }

    pub fn shakeCamera(world: *World, intensity: f32, duration: f32) void {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            item.data.shake_intensity = intensity;
            item.data.shake_duration = duration;
            item.data.shake_time = duration;
            break;
        }
    }

    pub fn setAnimation(world: *World, tag: []const u8, name: []const u8) bool {
        const entity = world.findByTag(tag) orelse return false;
        const anim = world.animation_states.get(entity) orelse return false;
        const sr = world.sprite_renderers.get(entity) orelse return false;
        for (anim.clips, 0..) |clip, i| {
            if (!clip.matches(name)) continue;
            anim.current = i;
            sr.current_frame = clip.start;
            sr.start_frame = clip.start;
            sr.frames = clip.frames;
            sr.fps = clip.fps;
            sr.loop = clip.loop;
            sr.frame_timer = 0;
            return true;
        }
        return false;
    }

    pub fn setPlayerPaused(world: *World, paused: bool) void {
        var it = world.player_controllers.iterator();
        while (it.next()) |item| {
            item.data.paused = paused;
        }
    }

    pub fn resetTriggers(world: *World) void {
        var it = world.triggers.iterator();
        while (it.next()) |item| {
            item.data.reset();
        }
    }

    fn spawnParticle(emitter: *ParticleEmitter, origin: rl.Vector2) void {
        for (&emitter.particles) |*p| {
            if (p.life > 0) continue;
            emitter.seed = emitter.seed *% 1664525 +% 1013904223;
            const unit = @as(f32, @floatFromInt(emitter.seed & 0xffff)) / 65535.0;
            const angle = (unit - 0.5) * emitter.spread;
            p.position = origin;
            p.velocity = .{ .x = @cos(angle) * emitter.speed, .y = @sin(angle) * emitter.speed };
            p.life = emitter.lifetime;
            p.max_life = emitter.lifetime;
            return;
        }
    }

    pub fn executeAction(world: *World, action: TriggerAction) void {
        switch (action) {
            .show_message => |payload| {
                const len = std.mem.indexOfScalar(u8, &payload.text, 0) orelse payload.text.len;
                world.state.eventQueue.push(events.showMessage(payload.text[0..len], payload.duration)) catch {};
            },
            .start_dialogue => |payload| {
                if (payload.id_len > 0) {
                    const label = if (payload.label_len > 0) payload.label[0..payload.label_len] else null;
                    world.state.eventQueue.push(events.startDialogueById(payload.runner, payload.context, payload.id[0..payload.id_len], label)) catch {};
                } else if (payload.label_len > 0) {
                    world.state.eventQueue.push(events.startDialogueAt(payload.runner, payload.context, payload.label[0..payload.label_len])) catch {};
                } else {
                    world.state.eventQueue.push(events.startDialogue(payload.runner, payload.context)) catch {};
                }
            },
            .change_scene => |cs| {
                if (cs.use_index) {
                    world.state.eventQueue.push(events.changeSceneByIndex(cs.index)) catch {};
                } else {
                    world.state.eventQueue.push(events.changeSceneByName(cs.name[0..cs.name_len])) catch {};
                }
            },
            .set_flag => |sf| {
                world.state.eventQueue.push(events.setFlag(sf.name[0..sf.name_len], sf.value)) catch {};
            },
            .start_combat => |sc| {
                _ = world.state.combatState.start(sc.encounter[0..sc.encounter_len]);
            },
            .sequence => |items| {
                for (items) |item| executeAction(world, item);
            },
            .run_action => |action_fn| {
                world.state.eventQueue.push(events.customEvent(action_fn(world))) catch {};
            },
        }
    }

    fn firstPlayer(world: *World) ?Entity {
        var it = world.player_controllers.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (world.isActive(entity)) return entity;
        }
        return null;
    }

    fn inputVector(mode: MovementMode) rl.Vector2 {
        var out = rl.Vector2{ .x = 0, .y = 0 };
        if (rl.isKeyDown(.right)) out.x += 1;
        if (rl.isKeyDown(.left)) out.x -= 1;
        if (rl.isKeyDown(.down)) out.y += 1;
        if (rl.isKeyDown(.up)) out.y -= 1;
        if (mode == .smooth4 or mode == .grid4) {
            if (@abs(out.x) > 0 and @abs(out.y) > 0) out.y = 0;
        } else if (out.x != 0 and out.y != 0) {
            const inv = 0.70710677;
            out.x *= inv;
            out.y *= inv;
        }
        return out;
    }

    fn directionFromVector(v: rl.Vector2, fallback: Direction) Direction {
        if (@abs(v.x) > @abs(v.y)) return if (v.x > 0) .right else .left;
        if (v.y > 0) return .down;
        if (v.y < 0) return .up;
        return fallback;
    }

    fn updateGridMovement(world: *World, entity: Entity, transform: *Transform, pc: *PlayerController, input: rl.Vector2, dt: f32) void {
        if (pc.stepping) {
            pc.step_elapsed += dt;
            const t = std.math.clamp(pc.step_elapsed / @max(pc.step_time, 0.001), 0, 1);
            const eased = t * t * (3 - 2 * t);
            transform.position.x = pc.step_from.x + (pc.step_to.x - pc.step_from.x) * eased;
            transform.position.y = pc.step_from.y + (pc.step_to.y - pc.step_from.y) * eased;
            if (t >= 1) {
                pc.stepping = false;
                transform.position = pc.step_to;
            }
            return;
        }

        if (input.x == 0 and input.y == 0) return;
        pc.step_from = transform.position;
        pc.step_to = .{ .x = transform.position.x + input.x * pc.step_size, .y = transform.position.y + input.y * pc.step_size };
        transform.position = pc.step_to;
        clampEntityToWorld(world, entity);
        if (collidesWithSolid(world, entity)) {
            transform.position = pc.step_from;
            return;
        }
        pc.step_to = transform.position;
        transform.position = pc.step_from;
        pc.step_elapsed = 0;
        pc.stepping = true;
    }

    fn clampEntityToWorld(world: *World, entity: Entity) void {
        const tr = world.transforms.get(entity) orelse return;
        const rect = entityRect(world, entity) orelse return;
        if (rect.x < 0) tr.position.x += -rect.x;
        if (rect.y < 0) tr.position.y += -rect.y;
        if (rect.x + rect.width > world.bounds_width) tr.position.x -= rect.x + rect.width - world.bounds_width;
        if (rect.y + rect.height > world.bounds_height) tr.position.y -= rect.y + rect.height - world.bounds_height;
    }

    fn interactionProbe(player_rect: rl.Rectangle, facing: Direction) rl.Rectangle {
        const reach: f32 = 14;
        const v = facing.vector();
        var probe = player_rect;
        probe.x += v.x * reach;
        probe.y += v.y * reach;
        if (v.x != 0) {
            probe.width += reach;
            if (v.x < 0) probe.x -= reach;
        }
        if (v.y != 0) {
            probe.height += reach;
            if (v.y < 0) probe.y -= reach;
        }
        return probe;
    }

    fn drawPromptHint(text: []const u8) void {
        var buf: [96]u8 = undefined;
        const line = std.fmt.bufPrintZ(&buf, "[E] {s}", .{text}) catch return;
        const width = rl.measureText(line, 18);
        rl.drawRectangle(16, rl.getScreenHeight() - 42, width + 18, 28, rl.Color{ .r = 8, .g = 10, .b = 12, .a = 210 });
        rl.drawText(line, 25, rl.getScreenHeight() - 36, 18, rl.Color.white);
    }

    fn entityRect(world: *World, entity: Entity) ?rl.Rectangle {
        const tr = world.transforms.get(entity) orelse return null;
        if (world.box_colliders.get(entity)) |col| return col.getRect(tr);
        if (world.sprite_renderers.get(entity)) |sr| {
            const sprite_w = if (sr.frame_width > 0) sr.frame_width else @as(f32, @floatFromInt(sr.texture.width));
            const sprite_h = if (sr.frame_height > 0) sr.frame_height else @as(f32, @floatFromInt(sr.texture.height));
            const abs_scale = @abs(tr.scale.x);
            return .{ .x = tr.position.x, .y = tr.position.y, .width = sprite_w * abs_scale, .height = sprite_h * abs_scale };
        }
        return null;
    }

    fn collidesWithSolid(world: *World, moving: Entity) bool {
        const rect = entityRect(world, moving) orelse return false;

        var solid_it = world.solids.iterator();
        while (solid_it.next()) |item| {
            if (!item.data.enabled) continue;
            const other = world.entityFromId(item.entity_id);
            if (!world.isActive(other) or other.eql(moving)) continue;
            const other_rect = entityRect(world, other) orelse continue;
            if (rl.checkCollisionRecs(rect, other_rect)) return true;
        }

        var map_it = world.tilemaps.iterator();
        while (map_it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            const tr = world.transforms.get(entity) orelse continue;
            const map = item.data;
            for (0..map.rows) |row| {
                for (0..map.columns) |col| {
                    const tile = map.tileAt(col, row);
                    if (!map.tileIsSolid(tile)) continue;
                    const tile_rect = rl.Rectangle{
                        .x = tr.position.x + @as(f32, @floatFromInt(col)) * map.tile_width,
                        .y = tr.position.y + @as(f32, @floatFromInt(row)) * map.tile_height,
                        .width = map.tile_width,
                        .height = map.tile_height,
                    };
                    if (rl.checkCollisionRecs(rect, tile_rect)) return true;
                }
            }
        }

        return false;
    }
};

pub const EntityBuilder = struct {
    world: *World,
    entity: Entity,

    pub fn init(world: *World) EntityBuilder {
        return .{
            .world = world,
            .entity = world.spawn(),
        };
    }

    pub fn withTag(self: *EntityBuilder, name: []const u8) *EntityBuilder {
        self.world.tags.set(self.world.allocator, self.entity, TagComponent.init(name)) catch {};
        return self;
    }

    pub fn withTransform(self: *EntityBuilder, pos: rl.Vector2) *EntityBuilder {
        self.world.transforms.set(self.world.allocator, self.entity, .{ .position = pos }) catch {};
        return self;
    }

    pub fn withTransformFull(self: *EntityBuilder, transform: Transform) *EntityBuilder {
        self.world.transforms.set(self.world.allocator, self.entity, transform) catch {};
        return self;
    }

    pub fn withSprite(self: *EntityBuilder, texture: rl.Texture) *EntityBuilder {
        self.world.sprite_renderers.set(self.world.allocator, self.entity, SpriteRenderer.init(texture)) catch {};
        return self;
    }

    pub fn withCircle(self: *EntityBuilder, radius: f32, color: rl.Color) *EntityBuilder {
        self.world.circle_renderers.set(self.world.allocator, self.entity, .{ .radius = radius, .color = color }) catch {};
        return self;
    }

    pub fn withRect(self: *EntityBuilder, width: f32, height: f32, color: rl.Color) *EntityBuilder {
        self.world.rect_renderers.set(self.world.allocator, self.entity, .{ .width = width, .height = height, .color = color }) catch {};
        return self;
    }

    pub fn withPlayerController(self: *EntityBuilder, speed: f32) *EntityBuilder {
        self.world.player_controllers.set(self.world.allocator, self.entity, .{ .speed = speed }) catch {};
        return self;
    }

    pub fn withSolid(self: *EntityBuilder) *EntityBuilder {
        self.world.solids.set(self.world.allocator, self.entity, .{}) catch {};
        return self;
    }

    pub fn withCamera(self: *EntityBuilder, offset: rl.Vector2, follow: Entity) *EntityBuilder {
        self.world.cameras.set(self.world.allocator, self.entity, .{
            .offset = offset,
            .follow_target = follow,
        }) catch {};
        return self;
    }

    pub fn withCameraFull(self: *EntityBuilder, cam: Camera) *EntityBuilder {
        self.world.cameras.set(self.world.allocator, self.entity, cam) catch {};
        return self;
    }

    pub fn withTrigger(self: *EntityBuilder, bounds: rl.Rectangle, action: TriggerAction, one_shot: bool) *EntityBuilder {
        self.world.triggers.set(self.world.allocator, self.entity, .{
            .bounds = bounds,
            .action = action,
            .one_shot = one_shot,
        }) catch {};
        return self;
    }

    pub fn withBoxCollider(self: *EntityBuilder, width: f32, height: f32) *EntityBuilder {
        self.world.box_colliders.set(self.world.allocator, self.entity, .{ .width = width, .height = height }) catch {};
        return self;
    }

    pub fn build(self: *EntityBuilder) Entity {
        return self.entity;
    }
};
