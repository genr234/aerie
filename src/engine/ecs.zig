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
};

pub const Camera = struct {
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },
    target: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
    zoom: f32 = 1.0,
    follow_target: Entity = Entity.INVALID,

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
        label: [events.MAX_ID_LEN]u8,
        label_len: usize = 0,
    },
    change_scene: struct {
        index: usize,
    },
    set_flag: struct {
        name: [events.MAX_ID_LEN]u8,
        name_len: usize,
        value: bool,
    },
    run_action: dialogue.ActionFn,
};

pub fn TriggerShowMessage(text: []const u8, duration: f32) TriggerAction {
    var action = TriggerAction{ .show_message = .{ .text = [_]u8{0} ** 128, .duration = duration } };
    const copy_len: usize = @min(text.len, action.show_message.text.len - 1);
    @memcpy(action.show_message.text[0..copy_len], text[0..copy_len]);
    action.show_message.text[copy_len] = 0;
    return action;
}

pub fn TriggerDialogueStart(runner: *dialogue.Runner, context: ?*anyopaque, label: ?[]const u8) TriggerAction {
    var out: TriggerAction = .{ .start_dialogue = .{
        .runner = runner,
        .context = context,
        .label = [_]u8{0} ** events.MAX_ID_LEN,
        .label_len = 0,
    } };

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

pub const Active = struct {
    value: bool = true,
};

pub fn ComponentStorage(comptime T: type) type {
    return struct {
        const Self = @This();

        /// sparse maps entity_id -> dense index
        sparse: std.array_list.Aligned(?u32, null) = .{},
        generations: std.array_list.Aligned(u16, null) = .{},

        dense_entities: std.array_list.Aligned(u32, null) = .{},
        dense_data: std.array_list.Aligned(T, null) = .{},

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

    entity_generations: std.array_list.Aligned(u16, null) = .{},
    entity_alive: std.array_list.Aligned(bool, null) = .{},

    free_list: std.array_list.Aligned(u32, null) = .{},
    entity_count: u32 = 0,

    state: *state.GameState = undefined,

    tags: ComponentStorage(TagComponent) = .{},
    transforms: ComponentStorage(Transform) = .{},
    sprite_renderers: ComponentStorage(SpriteRenderer) = .{},
    circle_renderers: ComponentStorage(CircleRenderer) = .{},
    rect_renderers: ComponentStorage(RectRenderer) = .{},
    player_controllers: ComponentStorage(PlayerController) = .{},
    cameras: ComponentStorage(Camera) = .{},
    triggers: ComponentStorage(Trigger) = .{},
    box_colliders: ComponentStorage(BoxCollider) = .{},
    actives: ComponentStorage(Active) = .{},

    bounds_width: f32 = 800,
    bounds_height: f32 = 450,

    max_entities: usize = 0,

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
        try self.cameras.init(allocator, max_entities);
        try self.triggers.init(allocator, max_entities);
        try self.box_colliders.init(allocator, max_entities);
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
        self.cameras.deinit(self.allocator);
        self.triggers.deinit(self.allocator);
        self.box_colliders.deinit(self.allocator);
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
        try self.cameras.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.triggers.ensureEntityCapacity(self.allocator, self.max_entities);
        try self.box_colliders.ensureEntityCapacity(self.allocator, self.max_entities);
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
            const next_id: u32 = @intCast(self.entity_alive.items.len);
            if (next_id >= self.max_entities) {
                self.ensureCapacity(@as(usize, next_id) + 1) catch return Entity.INVALID;
            }
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
        self.cameras.remove(entity);
        self.triggers.remove(entity);
        self.box_colliders.remove(entity);
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

            const right_down = rl.isKeyDown(.right);
            const left_down = rl.isKeyDown(.left);

            if (right_down) {
                transform.position.x += speed * dt;
                transform.scale.x = -1.0;
            } else if (left_down) {
                transform.position.x -= speed * dt;
                transform.scale.x = 1.0;
            } else {
                // Reset facing direction when not moving horizontally
                transform.scale.x = 1.0;
            }

            if (rl.isKeyDown(.up)) {
                transform.position.y -= speed * dt;
            }
            if (rl.isKeyDown(.down)) {
                transform.position.y += speed * dt;
            }

            var sprite_w: f32 = 32;
            var sprite_h: f32 = 32;
            if (world.sprite_renderers.get(entity)) |sr| {
                sprite_w = @floatFromInt(sr.texture.width);
                sprite_h = @floatFromInt(sr.texture.height);
            } else if (world.box_colliders.get(entity)) |col| {
                sprite_w = col.width;
                sprite_h = col.height;
            }

            if (transform.position.x < 0) transform.position.x = 0;
            if (transform.position.y < 0) transform.position.y = 0;
            if (transform.position.x + sprite_w > world.bounds_width) {
                transform.position.x = world.bounds_width - sprite_w;
            }
            if (transform.position.y + sprite_h > world.bounds_height) {
                transform.position.y = world.bounds_height - sprite_h;
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

                cam.target = .{ .x = target_x, .y = target_y };
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
                // Just entered trigger
                switch (trigger.action) {
                    .show_message => |payload| {
                        const len = std.mem.indexOfScalar(u8, &payload.text, 0) orelse payload.text.len;
                        world.state.eventQueue.push(events.showMessage(payload.text[0..len], payload.duration)) catch {};
                    },
                    .start_dialogue => |payload| {
                        if (payload.label_len > 0) {
                            world.state.eventQueue.push(events.startDialogueAt(payload.runner, payload.context, payload.label[0..payload.label_len])) catch {};
                        } else {
                            world.state.eventQueue.push(events.startDialogue(payload.runner, payload.context)) catch {};
                        }
                    },
                    .change_scene => |cs| {
                        world.state.eventQueue.push(events.changeSceneByIndex(cs.index)) catch {};
                    },
                    .set_flag => |sf| {
                        world.state.eventQueue.push(events.setFlag(sf.name[0..sf.name_len], sf.value)) catch {};
                    },
                    .run_action => |action| {
                        world.state.eventQueue.push(events.customEvent(action(world))) catch {};
                    },
                }
                if (trigger.one_shot) trigger.triggered = true;
            }

            trigger.was_inside = inside;
        }
    }

    pub fn render(world: *World) void {
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

                const sprite_w: f32 = @floatFromInt(sr.texture.width);
                const sprite_h: f32 = @floatFromInt(sr.texture.height);

                const flip = sr.flip_x or tr.scale.x < 0;
                const src = rl.Rectangle{
                    .x = if (flip) sprite_w else 0,
                    .y = 0,
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
